@IsTest
private class KT_DocumentUploadServiceTest {
    private class CleanScanMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"isClean":true,"status":"clean"}');
            return response;
        }
    }

    private class InfectedScanMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"isClean":false,"status":"infected","threatName":"EICAR-Test-File"}');
            return response;
        }
    }

    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    @IsTest
    static void uploadDocumentCreatesContentVaultAndRequestLink() {
        Test.setMock(HttpCalloutMock.class, new CleanScanMock());
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Inbound ID',
            Output_Format__c = 'PDF',
            Is_Active__c = true,
            Version__c = 1
        );
        insert template;
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert request;

        Test.startTest();
        KT_DocumentUploadService.UploadResult result = KT_DocumentUploadService.uploadDocument(
            onboarding.Id,
            request.Id,
            'passport.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('file body')),
            'application/pdf'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.vaultEntryId);
        System.assertNotEquals(null, result.contentDocumentId);

        KT_DocumentVault__c vault = [
            SELECT Document_Name__c, Document_Type__c, Status__c, OCR_Status__c, Document_Request__c
            FROM KT_DocumentVault__c
            WHERE Id = :result.vaultEntryId
        ];
        System.assertEquals('passport.pdf', vault.Document_Name__c);
        System.assertEquals('Uploaded', vault.Document_Type__c);
        System.assertEquals('Draft', vault.Status__c);
        System.assertEquals('Pending', vault.OCR_Status__c);
        System.assertEquals(request.Id, vault.Document_Request__c);

        KT_Document_Request__c updatedRequest = [
            SELECT Status__c, Document_Vault_Entry__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('In Progress', updatedRequest.Status__c);
        System.assertEquals(result.vaultEntryId, updatedRequest.Document_Vault_Entry__c);
    }

    @IsTest
    static void rejectsInvalidInputs() {
        KT_Onboarding__c onboarding = createOnboarding();

        try {
            KT_DocumentUploadService.uploadDocument(null, null, 'passport.pdf', 'abc', 'application/pdf');
            System.assert(false, 'Expected missing onboarding id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentUploadService.uploadDocument(onboarding.Id, null, null, 'abc', 'application/pdf');
            System.assert(false, 'Expected missing file name to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentUploadService.uploadDocument(onboarding.Id, null, 'passport.pdf', null, 'application/pdf');
            System.assert(false, 'Expected missing file data to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentUploadService.uploadDocument(onboarding.Id, null, 'script.exe', 'abc', 'application/octet-stream');
            System.assert(false, 'Expected unsupported file type to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }

    @IsTest
    static void uploadDocumentSupportsDataUrlWithoutDocumentRequest() {
        Test.setMock(HttpCalloutMock.class, new CleanScanMock());
        KT_Onboarding__c onboarding = createOnboarding();
        String dataUrl = 'data:image/png;base64,' + EncodingUtil.base64Encode(Blob.valueOf('png body'));

        Test.startTest();
        KT_DocumentUploadService.UploadResult result = KT_DocumentUploadService.uploadDocument(
            onboarding.Id,
            null,
            'avatar.png',
            dataUrl,
            'image/png'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        KT_DocumentVault__c vault = [
            SELECT Document_Name__c, Content_Document_Id__c
            FROM KT_DocumentVault__c
            WHERE Id = :result.vaultEntryId
        ];
        System.assertEquals('avatar.png', vault.Document_Name__c);
        System.assertEquals(result.contentDocumentId, vault.Content_Document_Id__c);
    }

    @IsTest
    static void uploadDocumentQuarantinesInfectedFilesBeforeContentInsert() {
        Test.setMock(HttpCalloutMock.class, new InfectedScanMock());
        KT_Onboarding__c onboarding = createOnboarding();
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert request;

        Test.startTest();
        KT_DocumentUploadService.UploadResult result = KT_DocumentUploadService.uploadDocument(
            onboarding.Id,
            request.Id,
            'infected.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('bad body')),
            'application/pdf'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.contentDocumentId);

        KT_DocumentVault__c vault = [
            SELECT Status__c, OCR_Status__c, Content_Document_Id__c
            FROM KT_DocumentVault__c
            WHERE Id = :result.vaultEntryId
        ];
        System.assertEquals('Quarantined', vault.Status__c);
        System.assertEquals('Failed', vault.OCR_Status__c);
        System.assertEquals(null, vault.Content_Document_Id__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :result.vaultEntryId]);
    }
}
