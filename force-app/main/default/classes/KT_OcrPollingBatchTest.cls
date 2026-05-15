@IsTest
private class KT_OcrPollingBatchTest {
    private class TextractPollingSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('Textract.GetDocumentAnalysis', request.getHeader('X-Amz-Target'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"JobStatus":"SUCCEEDED","DocumentType":"Passport","IdentityDocuments":[{"IdentityDocumentFields":['
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

    private class AzureRunningMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:KT_Azure_FormRecognizer_NC/operations/123'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"status":"running"}');
            return response;
        }
    }

    @TestSetup
    static void setupQueue() {
        Group hrQueue = new Group(Name = 'KT HR Queue', DeveloperName = 'KT_HR_Queue', Type = 'Queue');
        insert hrQueue;
        insert new QueueSobject(QueueId = hrQueue.Id, SObjectType = 'Task');
    }

    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static KT_OCR_Job__c createOcrJob(KT_Onboarding__c onboarding) {
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
            OCR_Provider__c = 'AWS Textract',
            Job_Id__c = 'aws-job-123'
        );
        insert ocrJob;
        return ocrJob;
    }

    @IsTest
    static void queueablePollsTextractAndParsesCompletedResult() {
        Test.setMock(HttpCalloutMock.class, new TextractPollingSuccessMock());
        KT_OcrIngestionService.enqueueAsyncPolling = false;
        KT_OcrPollingBatch.enableChainedPolling = false;
        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding);

        Test.startTest();
        System.enqueueJob(new KT_OcrPollingBatch(ocrJob.Id));
        Test.stopTest();

        KT_OCR_Job__c updatedJob = [
            SELECT Status__c, Retry_Count__c, Document_Type_Detected__c, Extracted_Fields__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Review Required', updatedJob.Status__c);
        System.assertEquals(1, updatedJob.Retry_Count__c);
        System.assertEquals('Passport', updatedJob.Document_Type_Detected__c);
        System.assert(updatedJob.Extracted_Fields__c.contains('LastName'));
    }

    @IsTest
    static void queueableFailsAtMaxRetriesAndCreatesManualReviewTask() {
        Test.setMock(HttpCalloutMock.class, new AzureRunningMock());
        KT_OcrIngestionService.enqueueAsyncPolling = false;
        KT_OcrPollingBatch.enableChainedPolling = false;

        KT_Onboarding__c onboarding = createOnboarding();
        KT_OCR_Job__c ocrJob = createOcrJob(onboarding);
        update new KT_OCR_Job__c(
            Id = ocrJob.Id,
            OCR_Provider__c = 'Azure Form Recognizer',
            Job_Id__c = 'https://example.azure.com/operations/123',
            Retry_Count__c = 11
        );

        Test.startTest();
        System.enqueueJob(new KT_OcrPollingBatch(ocrJob.Id));
        Test.stopTest();

        KT_OCR_Job__c failedJob = [
            SELECT Status__c, Retry_Count__c, Review_Notes__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJob.Id
        ];
        System.assertEquals('Failed', failedJob.Status__c);
        System.assertEquals(12, failedJob.Retry_Count__c);
        System.assert(failedJob.Review_Notes__c.contains('maximum retry count'));

        KT_DocumentVault__c failedVault = [
            SELECT OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :ocrJob.KT_DocumentVault__c
        ];
        System.assertEquals('Failed', failedVault.OCR_Status__c);

        Task reviewTask = [
            SELECT OwnerId, WhatId, Priority, Subject
            FROM Task
            WHERE WhatId = :ocrJob.Id
            LIMIT 1
        ];
        Group hrQueue = [SELECT Id FROM Group WHERE DeveloperName = 'KT_HR_Queue' LIMIT 1];
        System.assertEquals(hrQueue.Id, reviewTask.OwnerId);
        System.assertEquals('High', reviewTask.Priority);
        System.assert(reviewTask.Subject.contains('OCR manual review required'));
    }
}
