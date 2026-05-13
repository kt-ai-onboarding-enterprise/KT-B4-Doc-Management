@IsTest
private class KT_OcrCallbackHandlerTest {
    private class AzureResultMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"status":"succeeded","analyzeResult":{"documents":[{"docType":"idDocument.passport","fields":{'
                + '"LastName":{"content":"Doe","confidence":0.99},'
                + '"FirstName":{"content":"Jane","confidence":0.98},'
                + '"DateOfBirth":{"content":"1990-05-15","confidence":0.97},'
                + '"DocumentNumber":{"content":"P1234567","confidence":0.96},'
                + '"DateOfExpiration":{"content":"2030-05-15","confidence":0.95},'
                + '"Nationality":{"content":"British","confidence":0.94}'
                + '}}]}}'
            );
            return response;
        }
    }

    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static KT_OCR_Job__c createOcrJob(KT_Onboarding__c onboarding, String providerName, String providerJobId) {
        ContentVersion version = new ContentVersion(
            Title = 'OCR Source',
            PathOnClient = 'passport.png',
            VersionData = Blob.valueOf('image-bytes')
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;

        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'passport.png',
            Content_Document_Id__c = contentDocumentId,
            Document_Type__c = 'Identity Document',
            Status__c = 'Draft',
            OCR_Status__c = 'Processing',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;

        KT_OCR_Job__c ocrJob = new KT_OCR_Job__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Processing',
            OCR_Provider__c = providerName,
            Job_Id__c = providerJobId
        );
        insert ocrJob;
        return ocrJob;
    }

    @IsTest
    static void awsCallbackParsesInlinePayloadWhenSignatureIsValid() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'AWS Textract', 'aws-job-123');
        String payload =
            '{"JobId":"aws-job-123","JobStatus":"SUCCEEDED","DocumentType":"Passport","IdentityDocuments":[{"IdentityDocumentFields":['
            + '{"Type":{"Text":"LAST_NAME"},"ValueDetection":{"Text":"Doe","Confidence":0.98}},'
            + '{"Type":{"Text":"FIRST_NAME"},"ValueDetection":{"Text":"Jane","Confidence":0.97}},'
            + '{"Type":{"Text":"DATE_OF_BIRTH"},"ValueDetection":{"Text":"1990-05-15","Confidence":0.96}},'
            + '{"Type":{"Text":"DOCUMENT_NUMBER"},"ValueDetection":{"Text":"P1234567","Confidence":0.95}},'
            + '{"Type":{"Text":"EXPIRATON_DATE"},"ValueDetection":{"Text":"2030-05-15","Confidence":0.94}},'
            + '{"Type":{"Text":"NATIONALITY"},"ValueDetection":{"Text":"British","Confidence":0.93}}'
            + ']}]}';

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'AWS Textract');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'aws-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('AWS Textract', 'aws-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        KT_OCR_Job__c updatedJob = [
            SELECT Status__c, Document_Type_Detected__c, Confidence_Score__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Review Required', updatedJob.Status__c);
        System.assertEquals('Passport', updatedJob.Document_Type_Detected__c);
        System.assert(updatedJob.Confidence_Score__c >= 90);
    }

    @IsTest
    static void azureCallbackQueuesRetrievalWhenOnlyStatusArrives() {
        Test.setMock(HttpCalloutMock.class, new AzureResultMock());
        KT_OcrPollingBatch.enableChainedPolling = false;
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(
            onboarding,
            'Azure Form Recognizer',
            'https://example.azure.com/operations/123'
        );

        String payload = '{"status":"succeeded","operationLocation":"https://example.azure.com/operations/123"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'Azure Form Recognizer');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'azure-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('Azure Form Recognizer', 'azure-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode);
        KT_OCR_Job__c updatedJob = [
            SELECT Status__c, Document_Type_Detected__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Review Required', updatedJob.Status__c);
        System.assertEquals('Passport', updatedJob.Document_Type_Detected__c);
    }

    @IsTest
    static void invalidSignatureReturnsUnauthorized() {
        KT_Onboarding__c onboarding = createOnboarding();
        createOcrJob(onboarding, 'AWS Textract', 'aws-job-123');

        String payload = '{"JobId":"aws-job-123","JobStatus":"SUCCEEDED"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'AWS Textract');
        request.addHeader('X-KT-Signature', 'sha256=deadbeef');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('AWS Textract', 'aws-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void failedCallbackMarksJobFailed() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'AWS Textract', 'aws-job-123');

        String payload = '{"JobId":"aws-job-123","JobStatus":"FAILED"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'AWS Textract');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'aws-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('AWS Textract', 'aws-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        KT_OCR_Job__c failedJob = [
            SELECT Status__c, Review_Notes__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Failed', failedJob.Status__c);
        System.assert(failedJob.Review_Notes__c.contains('provider failure'));
    }

    @IsTest
    static void snsWrappedPayloadWithoutMatchingJobReturnsNotFound() {
        String innerPayload = '{"JobId":"aws-job-missing","JobStatus":"SUCCEEDED"}';
        String outerPayload = '{"Type":"Notification","TopicArn":"arn:aws:sns:us-east-1:123456789012:textract-topic","Message":'
            + JSON.serialize(innerPayload) + '}';

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(outerPayload);
        request.addHeader('X-KT-Signature', buildSignature(outerPayload, 'aws-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('AWS Textract', 'aws-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @IsTest
    static void missingConfiguredSecretReturnsUnauthorized() {
        String payload = '{"JobId":"aws-job-123","JobStatus":"SUCCEEDED"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'AWS Textract');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'aws-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.clear();

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void invalidJsonReturnsBadRequest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('not-json');
        request.addHeader('X-KT-OCR-Provider', 'AWS Textract');
        request.addHeader('X-KT-Signature', buildSignature('not-json', 'aws-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('AWS Textract', 'aws-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void azureFailedCallbackUpdatesJobAndVault() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(
            onboarding,
            'Azure Form Recognizer',
            'https://example.azure.com/operations/123'
        );

        String payload = '{"status":"failed","operationLocation":"https://example.azure.com/operations/123"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'Azure Form Recognizer');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'azure-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('Azure Form Recognizer', 'azure-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        KT_OCR_Job__c updatedJob = [
            SELECT Status__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        KT_DocumentVault__c updatedVault = [
            SELECT OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :ocrJob.KT_DocumentVault__c
        ];
        System.assertEquals('Failed', updatedJob.Status__c);
        System.assertEquals('Failed', updatedVault.OCR_Status__c);
    }

    @IsTest
    static void base64SignatureAndProviderAutoDetectionAreAccepted() {
        Test.setMock(HttpCalloutMock.class, new AzureResultMock());
        KT_OcrPollingBatch.enableChainedPolling = false;
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(
            onboarding,
            'Azure Form Recognizer',
            'https://example.azure.com/operations/123'
        );

        String payload = '{"status":"succeeded","operationLocation":"https://example.azure.com/operations/123"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-Signature', buildBase64Signature(payload, 'azure-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('Azure Form Recognizer', 'azure-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode);
        KT_OCR_Job__c updatedJob = [
            SELECT Status__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Review Required', updatedJob.Status__c);
    }

    @IsTest
    static void azureCallbackMatchesStoredOperationSuffixAndAcksUnknownStatus() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(
            onboarding,
            'Azure Form Recognizer',
            '/operations/456'
        );

        String payload = '{"status":"running","operationLocation":"https://example.azure.com/operations/456"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'Azure Form Recognizer');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'azure-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('Azure Form Recognizer', 'azure-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode);
        KT_OCR_Job__c updatedJob = [
            SELECT Status__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Processing', updatedJob.Status__c);
        System.assert(
            RestContext.response.responseBody.toString().contains('No action was required for status running')
        );
    }

    @IsTest
    static void missingProviderJobIdReturnsBadRequest() {
        String payload = '{"status":"succeeded"}';
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-KT-OCR-Provider', 'Azure Form Recognizer');
        request.addHeader('X-KT-Signature', buildSignature(payload, 'azure-secret'));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_OcrCallbackHandler.callbackSecretOverrides.put('Azure Form Recognizer', 'azure-secret');

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void missingRequestBodyReturnsBadRequest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/ocr/callback';
        request.httpMethod = 'POST';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        KT_OcrCallbackHandler.handleCallback();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    private static String buildSignature(String payload, String secret) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        return 'sha256=' + EncodingUtil.convertToHex(mac).toLowerCase();
    }

    private static String buildBase64Signature(String payload, String secret) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        return EncodingUtil.base64Encode(mac);
    }
}
