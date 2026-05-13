@IsTest
private class KT_OcrUploadPipelineServiceTest {
    private class TextractSyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
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

    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static KT_DocumentTemplate__c createTemplate() {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Inbound Passport',
            Output_Format__c = 'PDF',
            Is_Active__c = true,
            Version__c = 1
        );
        insert template;
        return template;
    }

    private static KT_Document_Request__c createRequest(Id onboardingId, Id templateId) {
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboardingId,
            Document_Template__c = templateId,
            Status__c = 'In Progress',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert request;
        return request;
    }

    private static Id createContentDocument(String fileName) {
        ContentVersion version = new ContentVersion(
            Title = 'OCR Source',
            PathOnClient = fileName,
            VersionData = Blob.valueOf('image-bytes')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static KT_DocumentVault__c createVault(Id onboardingId, Id requestId, Id contentDocumentId) {
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboardingId,
            Document_Name__c = 'passport.png',
            Content_Document_Id__c = contentDocumentId,
            Document_Type__c = 'Uploaded',
            Status__c = 'Draft',
            Document_Request__c = requestId,
            OCR_Status__c = 'Pending',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;
        return vaultEntry;
    }

    @IsTest
    static void runUploadPipelineCreatesOcrJobForRequiredTemplate() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate();
        KT_Document_Request__c request = createRequest(onboarding.Id, template.Id);
        Id contentDocumentId = createContentDocument('passport.png');
        KT_DocumentVault__c vaultEntry = createVault(onboarding.Id, request.Id, contentDocumentId);
        KT_OcrUploadPipelineService.executeSubmission = false;
        KT_OcrUploadPipelineService.templateConfigOverrides = new List<KT_Document_Template_Config__mdt>{
            new KT_Document_Template_Config__mdt(
                DeveloperName = 'Inbound_Passport_OCR',
                MasterLabel = 'Inbound Passport OCR',
                Template_API_Name__c = String.valueOf(template.Id),
                Requires_OCR__c = true
            )
        };

        KT_OcrUploadPipelineService.UploadPipelineRequest pipelineRequest =
            new KT_OcrUploadPipelineService.UploadPipelineRequest();
        pipelineRequest.vaultId = vaultEntry.Id;
        pipelineRequest.contentDocumentId = contentDocumentId;
        pipelineRequest.onboardingId = onboarding.Id;
        pipelineRequest.documentType = 'Uploaded';

        Test.startTest();
        List<KT_OcrUploadPipelineService.UploadPipelineResult> results =
            KT_OcrUploadPipelineService.runUploadPipeline(
                new List<KT_OcrUploadPipelineService.UploadPipelineRequest>{ pipelineRequest }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].processed, results[0].message);
        System.assertEquals(true, results[0].ocrRequired);
        System.assertNotEquals(null, results[0].ocrJobId);

        KT_OCR_Job__c createdJob = [
            SELECT Status__c, KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE Id = :results[0].ocrJobId
        ];
        System.assertEquals(vaultEntry.Id, createdJob.KT_DocumentVault__c);
        System.assertEquals('Submitted', createdJob.Status__c);
    }

    @IsTest
    static void runUploadPipelineSkipsWhenTemplateDoesNotRequireOcr() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate();
        KT_Document_Request__c request = createRequest(onboarding.Id, template.Id);
        Id contentDocumentId = createContentDocument('passport.png');
        KT_DocumentVault__c vaultEntry = createVault(onboarding.Id, request.Id, contentDocumentId);
        KT_OcrUploadPipelineService.templateConfigOverrides = new List<KT_Document_Template_Config__mdt>{
            new KT_Document_Template_Config__mdt(
                DeveloperName = 'Inbound_Passport_No_OCR',
                MasterLabel = 'Inbound Passport No OCR',
                Template_API_Name__c = String.valueOf(template.Id),
                Requires_OCR__c = false
            )
        };

        KT_OcrUploadPipelineService.UploadPipelineRequest pipelineRequest =
            new KT_OcrUploadPipelineService.UploadPipelineRequest();
        pipelineRequest.vaultId = vaultEntry.Id;
        pipelineRequest.onboardingId = onboarding.Id;

        Test.startTest();
        List<KT_OcrUploadPipelineService.UploadPipelineResult> results =
            KT_OcrUploadPipelineService.runUploadPipeline(
                new List<KT_OcrUploadPipelineService.UploadPipelineRequest>{ pipelineRequest }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].processed);
        System.assertEquals(false, results[0].ocrRequired);
        System.assertEquals(0, [SELECT COUNT() FROM KT_OCR_Job__c WHERE KT_DocumentVault__c = :vaultEntry.Id]);
    }

    @IsTest
    static void runUploadPipelineDoesNotDuplicateExistingJob() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate();
        KT_Document_Request__c request = createRequest(onboarding.Id, template.Id);
        Id contentDocumentId = createContentDocument('passport.png');
        KT_DocumentVault__c vaultEntry = createVault(onboarding.Id, request.Id, contentDocumentId);
        insert new KT_OCR_Job__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Processing'
        );
        KT_OcrUploadPipelineService.templateConfigOverrides = new List<KT_Document_Template_Config__mdt>{
            new KT_Document_Template_Config__mdt(
                DeveloperName = 'Inbound_Passport_OCR',
                MasterLabel = 'Inbound Passport OCR',
                Template_API_Name__c = String.valueOf(template.Id),
                Requires_OCR__c = true
            )
        };

        KT_OcrUploadPipelineService.UploadPipelineRequest pipelineRequest =
            new KT_OcrUploadPipelineService.UploadPipelineRequest();
        pipelineRequest.vaultId = vaultEntry.Id;
        pipelineRequest.onboardingId = onboarding.Id;

        Test.startTest();
        List<KT_OcrUploadPipelineService.UploadPipelineResult> results =
            KT_OcrUploadPipelineService.runUploadPipeline(
                new List<KT_OcrUploadPipelineService.UploadPipelineRequest>{ pipelineRequest }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].processed);
        System.assertEquals(true, results[0].ocrRequired);
        System.assertEquals(1, [SELECT COUNT() FROM KT_OCR_Job__c WHERE KT_DocumentVault__c = :vaultEntry.Id]);
    }

    @IsTest
    static void runUploadPipelineRejectsMissingOnboardingId() {
        KT_OcrUploadPipelineService.UploadPipelineRequest pipelineRequest =
            new KT_OcrUploadPipelineService.UploadPipelineRequest();

        Test.startTest();
        List<KT_OcrUploadPipelineService.UploadPipelineResult> results =
            KT_OcrUploadPipelineService.runUploadPipeline(
                new List<KT_OcrUploadPipelineService.UploadPipelineRequest>{ pipelineRequest }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].processed);
        System.assert(results[0].message.contains('onboardingId is required'));
    }

    @IsTest
    static void runUploadPipelineHandlesMissingVaultEntry() {
        KT_OcrUploadPipelineService.UploadPipelineRequest pipelineRequest =
            new KT_OcrUploadPipelineService.UploadPipelineRequest();
        pipelineRequest.onboardingId = 'a050000000000001AA';
        pipelineRequest.vaultId = 'a020000000000001AA';

        Test.startTest();
        List<KT_OcrUploadPipelineService.UploadPipelineResult> results =
            KT_OcrUploadPipelineService.runUploadPipeline(
                new List<KT_OcrUploadPipelineService.UploadPipelineRequest>{ pipelineRequest }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].processed);
        System.assert(results[0].message.contains('No matching document vault entry'));
    }
}
