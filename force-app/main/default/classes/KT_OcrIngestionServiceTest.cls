@IsTest
private class KT_OcrIngestionServiceTest {
    private class TextractSyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assertEquals('Textract.AnalyzeDocument', request.getHeader('X-Amz-Target'));
            System.assert(request.getEndpoint().startsWith('callout:KT_AWS_Textract_NC'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"DocumentType":"Passport","IdentityDocuments":[{"IdentityDocumentFields":['
                + '{"Type":{"Text":"LAST_NAME"},"ValueDetection":{"Text":"Doe","Confidence":0.98}},'
                + '{"Type":{"Text":"FIRST_NAME"},"ValueDetection":{"Text":"Jane","Confidence":0.97}},'
                + '{"Type":{"Text":"DATE_OF_BIRTH"},"ValueDetection":{"Text":"1990-05-15","Confidence":0.96}},'
                + '{"Type":{"Text":"DOCUMENT_NUMBER"},"ValueDetection":{"Text":"P1234567","Confidence":0.95}},'
                + '{"Type":{"Text":"EXPIRATON_DATE"},"ValueDetection":{"Text":"2030-05-15","Confidence":0.94}},'
                + '{"Type":{"Text":"NATIONALITY"},"ValueDetection":{"Text":"British","Confidence":0.93}}'
                + ']}]}'
            );
            return response;
        }
    }

    private class TextractAsyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('Textract.StartDocumentAnalysis', request.getHeader('X-Amz-Target'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"JobId":"aws-job-123"}');
            return response;
        }
    }

    private class AzureAsyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:KT_Azure_FormRecognizer_NC/analyze'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(202);
            response.setHeader('Operation-Location', 'https://example.azure.com/operations/123');
            response.setBody('{"status":"running"}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('{"message":"unavailable"}');
            return response;
        }
    }

    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static Contact createContact() {
        Contact contact = new Contact(FirstName = 'Current', LastName = 'Original');
        insert contact;
        return contact;
    }

    private static Id createContentDocument(String pathOnClient, Blob versionData) {
        ContentVersion version = new ContentVersion(
            Title = 'OCR Source',
            PathOnClient = pathOnClient,
            VersionData = versionData
        );
        insert version;

        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static KT_OCR_Job__c createOcrJob(KT_Onboarding__c onboarding, String pathOnClient, Blob versionData) {
        Id contentDocumentId = createContentDocument(pathOnClient, versionData);
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = pathOnClient,
            Content_Document_Id__c = contentDocumentId,
            Document_Type__c = 'Identity Document',
            Status__c = 'Draft',
            OCR_Status__c = 'Pending',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;

        KT_OCR_Job__c ocrJob = new KT_OCR_Job__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Submitted'
        );
        insert ocrJob;
        return ocrJob;
    }

    @IsTest
    static void submitJobUsesActiveTextractAndParsesSyncResponse() {
        Test.setMock(HttpCalloutMock.class, new TextractSyncMock());
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.png', Blob.valueOf('image-bytes'));

        Test.startTest();
        KT_OcrIngestionService.SubmitJobResult result = KT_OcrIngestionService.submitJob(ocrJob.Id);
        Test.stopTest();

        System.assertEquals(PROVIDER_AWS(), result.provider);
        System.assertEquals(false, result.asyncProcessing);
        System.assertEquals('Review Required', result.status);

        KT_OCR_Job__c updatedJob = [
            SELECT OCR_Provider__c, Status__c, Document_Type_Detected__c, Confidence_Score__c, Extracted_Fields__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals(PROVIDER_AWS(), updatedJob.OCR_Provider__c);
        System.assertEquals('Review Required', updatedJob.Status__c);
        System.assertEquals('Passport', updatedJob.Document_Type_Detected__c);
        System.assert(updatedJob.Confidence_Score__c >= 90);
        System.assert(updatedJob.Extracted_Fields__c.contains('Passport_Number__c'));

        KT_DocumentVault__c updatedVault = [
            SELECT OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :ocrJob.KT_DocumentVault__c
        ];
        System.assertEquals('Review Required', updatedVault.OCR_Status__c);
    }

    @IsTest
    static void submitToTextractStoresAsyncJobIdForLargePdf() {
        Test.setMock(HttpCalloutMock.class, new TextractAsyncMock());
        KT_Onboarding__c onboarding = createOnboarding();
        String pdfBody = '%PDF-1.4 '
            + '/Type /Page /Type /Page /Type /Page /Type /Page /Type /Page '
            + '/Type /Page /Type /Page /Type /Page /Type /Page /Type /Page ';
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.pdf', Blob.valueOf(pdfBody));
        KT_OcrIngestionService.enqueueAsyncPolling = false;

        Test.startTest();
        KT_OcrIngestionService.SubmitJobResult result = KT_OcrIngestionService.submitToTextract(ocrJob.Id);
        Test.stopTest();
        KT_OcrIngestionService.enqueueAsyncPolling = true;

        System.assertEquals(true, result.asyncProcessing);
        System.assertEquals('Processing', result.status);
        System.assertEquals('aws-job-123', result.providerJobId);

        KT_OCR_Job__c updatedJob = [
            SELECT OCR_Provider__c, Status__c, Job_Id__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals(PROVIDER_AWS(), updatedJob.OCR_Provider__c);
        System.assertEquals('Processing', updatedJob.Status__c);
        System.assertEquals('aws-job-123', updatedJob.Job_Id__c);
    }

    @IsTest
    static void submitToAzureStoresOperationLocation() {
        Test.setMock(HttpCalloutMock.class, new AzureAsyncMock());
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'license.png', Blob.valueOf('image-bytes'));
        KT_OcrIngestionService.enqueueAsyncPolling = false;

        Test.startTest();
        KT_OcrIngestionService.SubmitJobResult result = KT_OcrIngestionService.submitToAzure(ocrJob.Id);
        Test.stopTest();
        KT_OcrIngestionService.enqueueAsyncPolling = true;

        System.assertEquals(PROVIDER_AZURE(), result.provider);
        System.assertEquals(true, result.asyncProcessing);
        System.assertEquals('Processing', result.status);
        System.assertEquals('https://example.azure.com/operations/123', result.providerJobId);
    }

    @IsTest
    static void parseAndApplyExtractionUpdatesContactAndStatuses() {
        KT_Onboarding__c onboarding = createOnboarding();
        Contact contact = createContact();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.png', Blob.valueOf('image-bytes'));
        update new KT_OCR_Job__c(Id = ocrJob.Id, OCR_Provider__c = PROVIDER_AZURE());

        String azurePayload =
            '{"status":"succeeded","analyzeResult":{"documents":[{"docType":"idDocument.passport","fields":{'
            + '"LastName":{"content":"Doe","confidence":0.99},'
            + '"FirstName":{"content":"Jane","confidence":0.98},'
            + '"DateOfBirth":{"content":"1990-05-15","confidence":0.97},'
            + '"DocumentNumber":{"content":"P1234567","confidence":0.96},'
            + '"DateOfExpiration":{"content":"2030-05-15","confidence":0.95},'
            + '"Nationality":{"content":"British","confidence":0.94}'
            + '}}]}}';

        Test.startTest();
        KT_OcrIngestionService.ParseResult parseResult = KT_OcrIngestionService.parseAndMap(ocrJob.Id, azurePayload);
        KT_OcrIngestionService.ApplyResult applyResult = KT_OcrIngestionService.applyExtraction(
            ocrJob.Id,
            new List<String>{ 'LastName', 'FirstName', 'DateOfBirth' },
            contact.Id
        );
        Test.stopTest();

        System.assertEquals('Passport', parseResult.documentType);
        System.assertEquals('Review Required', parseResult.status);
        System.assertEquals('Accepted', applyResult.status);
        System.assertEquals(3, applyResult.acceptedFieldCount);
        System.assertEquals(true, applyResult.contactUpdated);

        Contact refreshedContact = [
            SELECT FirstName, LastName, Birthdate
            FROM Contact
            WHERE Id = :contact.Id
        ];
        System.assertEquals('Jane', refreshedContact.FirstName);
        System.assertEquals('Doe', refreshedContact.LastName);
        System.assertEquals(Date.newInstance(1990, 5, 15), refreshedContact.Birthdate);

        KT_OCR_Job__c updatedJob = [
            SELECT Status__c, Reviewed_By__c, Reviewed_At__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Accepted', updatedJob.Status__c);
        System.assertNotEquals(null, updatedJob.Reviewed_By__c);
        System.assertNotEquals(null, updatedJob.Reviewed_At__c);

        KT_DocumentVault__c updatedVault = [
            SELECT OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :ocrJob.KT_DocumentVault__c
        ];
        System.assertEquals('Accepted', updatedVault.OCR_Status__c);
    }

    @IsTest
    static void getReviewDataReturnsCurrentSalesforceValues() {
        KT_Onboarding__c onboarding = createOnboarding();
        Contact contact = createContact();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.png', Blob.valueOf('image-bytes'));
        update new KT_OCR_Job__c(Id = ocrJob.Id, OCR_Provider__c = PROVIDER_AZURE());

        String azurePayload =
            '{"status":"succeeded","analyzeResult":{"documents":[{"docType":"idDocument.passport","fields":{'
            + '"LastName":{"content":"Doe","confidence":0.99},'
            + '"FirstName":{"content":"Jane","confidence":0.98},'
            + '"DateOfBirth":{"content":"1990-05-15","confidence":0.97},'
            + '"DocumentNumber":{"content":"P1234567","confidence":0.96},'
            + '"DateOfExpiration":{"content":"2030-05-15","confidence":0.95},'
            + '"Nationality":{"content":"British","confidence":0.94}'
            + '}}]}}';

        Test.startTest();
        KT_OcrIngestionService.parseAndMap(ocrJob.Id, azurePayload);
        KT_OcrIngestionService.ReviewData reviewData = KT_OcrIngestionService.getReviewData(ocrJob.Id, contact.Id);
        Test.stopTest();

        System.assertEquals(ocrJob.Id, reviewData.ocrJobId);
        System.assertEquals(contact.Id, reviewData.contactId);
        System.assertEquals('Review Required', reviewData.status);
        System.assertEquals('Passport', reviewData.documentType);
        System.assertEquals(6, reviewData.fieldCount);
        System.assertEquals(6, reviewData.highConfidenceFieldCount);

        KT_OcrIngestionService.ReviewField lastNameField;
        for (KT_OcrIngestionService.ReviewField field : reviewData.fields) {
            if (field.providerFieldPath == 'LastName') {
                lastNameField = field;
                break;
            }
        }

        System.assertNotEquals(null, lastNameField);
        System.assertEquals('Contact', lastNameField.targetObject);
        System.assertEquals('LastName', lastNameField.targetField);
        System.assertEquals('Doe', lastNameField.extractedValue);
        System.assertEquals('Original', lastNameField.currentValue);
        System.assertEquals(true, lastNameField.highConfidence);
        System.assertEquals('Last Name', lastNameField.targetFieldLabel);
    }

    @IsTest
    static void parseFromStoredJsonAndApplyHighConfidenceDefaults() {
        KT_Onboarding__c onboarding = createOnboarding();
        Contact contact = createContact();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.png', Blob.valueOf('image-bytes'));
        String azurePayload =
            '{"status":"succeeded","analyzeResult":{"documents":[{"docType":"idDocument.passport","fields":{'
            + '"LastName":{"content":"Doe","confidence":0.99},'
            + '"FirstName":{"content":"Jane","confidence":0.98},'
            + '"DateOfBirth":{"content":"1990-05-15","confidence":0.97},'
            + '"DocumentNumber":{"content":"P1234567","confidence":0.96},'
            + '"DateOfExpiration":{"content":"2030-05-15","confidence":0.95},'
            + '"Nationality":{"content":"British","confidence":0.94}'
            + '}}]}}';
        update new KT_OCR_Job__c(
            Id = ocrJob.Id,
            OCR_Provider__c = PROVIDER_AZURE(),
            Extracted_JSON__c = azurePayload
        );

        Test.startTest();
        KT_OcrIngestionService.ParseResult parseResult = KT_OcrIngestionService.parseAndMap(ocrJob.Id);
        KT_OcrIngestionService.ApplyResult applyResult = KT_OcrIngestionService.applyExtraction(
            ocrJob.Id,
            null,
            contact.Id
        );
        Test.stopTest();

        System.assertEquals(6, parseResult.mappedFieldCount);
        System.assertEquals(6, parseResult.highConfidenceFieldCount);
        System.assertEquals(true, applyResult.contactUpdated);
        System.assert(applyResult.skippedFieldCount > 0);
    }

    @IsTest
    static void invocableSubmitJobHandlesMissingIdsAndProviderFailures() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding, 'passport.png', Blob.valueOf('image-bytes'));

        KT_OcrIngestionService.SubmitJobRequest missingRequest = new KT_OcrIngestionService.SubmitJobRequest();
        KT_OcrIngestionService.SubmitJobRequest failingRequest = new KT_OcrIngestionService.SubmitJobRequest();
        failingRequest.ocrJobId = ocrJob.Id;

        Test.startTest();
        List<KT_OcrIngestionService.SubmitJobResult> results = KT_OcrIngestionService.submitJob(
            new List<KT_OcrIngestionService.SubmitJobRequest>{ missingRequest, failingRequest }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Failed', results[0].status);
        System.assert(results[0].message.contains('ocrJobId is required'));
        System.assertEquals('Failed', results[1].status);
        System.assert(results[1].message.contains('HTTP 503'));

        KT_OCR_Job__c failedJob = [
            SELECT Status__c, OCR_Provider__c, Review_Notes__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Failed', failedJob.Status__c);
        System.assertEquals(PROVIDER_AWS(), failedJob.OCR_Provider__c);
        System.assert(failedJob.Review_Notes__c.contains('HTTP 503'));
    }

    private static String PROVIDER_AWS() {
        return 'AWS Textract';
    }

    private static String PROVIDER_AZURE() {
        return 'Azure Form Recognizer';
    }
}
