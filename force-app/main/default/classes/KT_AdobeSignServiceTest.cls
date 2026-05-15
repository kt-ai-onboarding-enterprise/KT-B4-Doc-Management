@IsTest
private class KT_AdobeSignServiceTest {
    private class AdobeSignMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getMethod() == 'POST') {
                System.assert(request.getEndpoint().endsWith('/api/rest/v6/agreements'));
                System.assert(request.getBody().contains('participantSetsInfo'));
                response.setStatusCode(201);
                response.setBody('{"id":"agr-123","status":"DRAFT"}');
                return response;
            }
            if (request.getMethod() == 'PUT') {
                System.assert(request.getEndpoint().endsWith('/agr-123/state'));
                response.setStatusCode(200);
                response.setBody('{"id":"agr-123","state":"IN_PROCESS"}');
                return response;
            }
            if (request.getMethod() == 'GET' && request.getEndpoint().endsWith('/combinedDocument')) {
                response.setHeader('Content-Type', 'application/pdf');
                response.setStatusCode(200);
                response.setBody('%PDF-1.4 adobe completed');
                return response;
            }
            if (request.getMethod() == 'GET') {
                response.setStatusCode(200);
                response.setBody('{"id":"agr-123","status":"SIGNED"}');
                return response;
            }

            response.setStatusCode(500);
            response.setBody('{"message":"unexpected"}');
            return response;
        }
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'Adobe Source',
            PathOnClient = 'adobe-source.pdf',
            VersionData = Blob.valueOf('source body')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    private static KT_Signature_Request__c createSignatureRequest(Boolean withAgreementId) {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_Document_Request__c documentRequest = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Awaiting Signature',
            Document_Direction__c = 'Outbound',
            Is_Required__c = true
        );
        insert documentRequest;

        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Adobe Source',
            Content_Document_Id__c = createContentDocument(),
            Document_Type__c = 'Generated',
            Status__c = 'Pending Signature',
            Document_Request__c = documentRequest.Id,
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Pending'
        );
        insert vault;

        KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
            KT_DocumentVault__c = vault.Id,
            KT_Onboarding__c = onboarding.Id,
            Signing_Provider__c = 'Adobe Sign',
            Status__c = 'Configured',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7),
            External_Envelope_Id__c = withAgreementId ? 'agr-123' : null
        );
        insert signatureRequest;

        insert new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Adobe Signer',
            Signer_Email__c = 'adobe.signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Pending'
        );

        return signatureRequest;
    }

    @IsTest
    static void createAgreementUpdatesSignatureRequest() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(false);
        Test.setMock(HttpCalloutMock.class, new AdobeSignMock());

        Test.startTest();
        KT_AdobeSignService.AgreementResult result = KT_AdobeSignService.createAgreement(signatureRequest.Id);
        Test.stopTest();

        System.assertEquals('agr-123', result.agreementId);
        KT_Signature_Request__c updatedRequest = [
            SELECT External_Envelope_Id__c, Signing_Provider__c, Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('agr-123', updatedRequest.External_Envelope_Id__c);
        System.assertEquals('Adobe Sign', updatedRequest.Signing_Provider__c);
        System.assertEquals('Configured', updatedRequest.Status__c);
    }

    @IsTest
    static void sendAgreementUpdatesSignerAndVaultStatus() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new AdobeSignMock());

        Test.startTest();
        KT_AdobeSignService.AgreementResult result = KT_AdobeSignService.sendAgreement(signatureRequest.Id);
        Test.stopTest();

        System.assertEquals('IN_PROCESS', result.status);
        System.assertEquals('In Progress', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
        System.assertEquals('Invitation Sent', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void statusRefreshMarksAgreementSigned() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new AdobeSignMock());

        Test.startTest();
        KT_AdobeSignService.AgreementResult result = KT_AdobeSignService.getAgreementStatus(signatureRequest.Id);
        Test.stopTest();

        System.assertEquals('SIGNED', result.status);
        System.assertEquals('Fully Signed', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
    }

    @IsTest
    static void completedDocumentUpdatesDownstreamRecords() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new AdobeSignMock());

        Test.startTest();
        KT_AdobeSignService.AgreementResult result = KT_AdobeSignService.retrieveCompletedDocument(signatureRequest.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.contentDocumentId);
        KT_Signature_Request__c updatedRequest = [
            SELECT Completed_Document_Id__c, KT_DocumentVault__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals(String.valueOf(result.contentDocumentId), updatedRequest.Completed_Document_Id__c);

        KT_DocumentVault__c vault = [
            SELECT Content_Document_Id__c, Status__c, Signature_Status__c, Document_Request__c
            FROM KT_DocumentVault__c
            WHERE Id = :updatedRequest.KT_DocumentVault__c
        ];
        System.assertEquals(result.contentDocumentId, vault.Content_Document_Id__c);
        System.assertEquals('Signed', vault.Status__c);
        System.assertEquals('Fully Signed', vault.Signature_Status__c);
        System.assertEquals('Complete', [
            SELECT Status__c
            FROM KT_Document_Request__c
            WHERE Id = :vault.Document_Request__c
        ].Status__c);
    }

    @IsTest
    static void webhookCallbackProcessesRecallAndMissingAgreement() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);

        KT_AdobeSignService.AgreementResult result = KT_AdobeSignService.webhookCallback('agr-123', 'AGREEMENT_RECALLED');

        System.assertEquals('AGREEMENT_RECALLED', result.status);
        System.assertEquals('Cancelled', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signature_Audit__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            AND Event_Type__c = 'Declined'
        ]);

        try {
            KT_AdobeSignService.webhookCallback('missing', 'SIGNED');
            System.assert(false, 'Expected missing agreement to fail.');
        } catch (KT_AdobeSignService.AdobeSignException expected) {
            System.assert(expected.getMessage().contains('No signature request'));
        }
    }

    @IsTest
    static void missingAgreementIdIsRejectedBeforeSend() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(false);

        try {
            KT_AdobeSignService.sendAgreement(signatureRequest.Id);
            System.assert(false, 'Expected send without agreement id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
