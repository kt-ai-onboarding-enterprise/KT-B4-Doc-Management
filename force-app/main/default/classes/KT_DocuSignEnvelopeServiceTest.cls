@IsTest
private class KT_DocuSignEnvelopeServiceTest {
    private class DocuSignMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getMethod() == 'POST') {
                System.assert(request.getEndpoint().contains('callout:KT_DocuSign_NC/v2.1/accounts/default/envelopes'));
                System.assert(request.getBody().contains('documentBase64'));
                response.setStatusCode(201);
                response.setBody('{"envelopeId":"env-123","status":"created"}');
                return response;
            }
            if (request.getMethod() == 'PUT') {
                System.assert(request.getEndpoint().endsWith('/env-123'));
                response.setStatusCode(200);
                response.setBody('{"envelopeId":"env-123","status":"sent"}');
                return response;
            }
            if (request.getMethod() == 'GET' && request.getEndpoint().endsWith('/documents/combined')) {
                response.setHeader('Content-Type', 'application/pdf');
                response.setStatusCode(200);
                response.setBody('%PDF-1.4 completed');
                return response;
            }
            if (request.getMethod() == 'GET') {
                response.setStatusCode(200);
                response.setBody('{"envelopeId":"env-123","status":"completed"}');
                return response;
            }

            response.setStatusCode(500);
            response.setBody('{"message":"unexpected"}');
            return response;
        }
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'DocuSign Source',
            PathOnClient = 'docusign-source.pdf',
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

    private static KT_Signature_Request__c createSignatureRequest(Boolean withEnvelopeId) {
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
            Document_Name__c = 'DocuSign Source',
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
            Signing_Provider__c = 'DocuSign',
            Status__c = 'Configured',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7),
            External_Envelope_Id__c = withEnvelopeId ? 'env-123' : null
        );
        insert signatureRequest;

        insert new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Docu Signer',
            Signer_Email__c = 'docu.signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Pending'
        );

        return signatureRequest;
    }

    @IsTest
    static void createEnvelopeUpdatesSignatureRequest() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(false);
        Test.setMock(HttpCalloutMock.class, new DocuSignMock());

        Test.startTest();
        KT_DocuSignEnvelopeService.EnvelopeResult createResult =
            KT_DocuSignEnvelopeService.createEnvelope(signatureRequest.Id, null);
        Test.stopTest();

        System.assertEquals('env-123', createResult.envelopeId);

        KT_Signature_Request__c updatedRequest = [
            SELECT External_Envelope_Id__c, Status__c, Signing_Provider__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('env-123', updatedRequest.External_Envelope_Id__c);
        System.assertEquals('Configured', updatedRequest.Status__c);
        System.assertEquals('DocuSign', updatedRequest.Signing_Provider__c);
    }

    @IsTest
    static void sendEnvelopeUpdatesSignerAndVaultStatus() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new DocuSignMock());

        Test.startTest();
        KT_DocuSignEnvelopeService.EnvelopeResult sendResult =
            KT_DocuSignEnvelopeService.sendEnvelope(signatureRequest.Id, null);
        Test.stopTest();

        System.assertEquals('sent', sendResult.status);

        KT_Signature_Request__c updatedRequest = [
            SELECT External_Envelope_Id__c, Status__c, Signing_Provider__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('env-123', updatedRequest.External_Envelope_Id__c);
        System.assertEquals('In Progress', updatedRequest.Status__c);
        System.assertEquals('DocuSign', updatedRequest.Signing_Provider__c);

        System.assertEquals('Invitation Sent', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void statusSyncsCompletedEnvelope() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new DocuSignMock());

        Test.startTest();
        KT_DocuSignEnvelopeService.EnvelopeResult statusResult =
            KT_DocuSignEnvelopeService.getEnvelopeStatus(signatureRequest.Id, null);
        Test.stopTest();

        System.assertEquals('completed', statusResult.status);
        KT_Signature_Request__c updatedRequest = [
            SELECT Status__c, KT_DocumentVault__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('Fully Signed', updatedRequest.Status__c);
        System.assertEquals('Signed', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void completedDocumentSyncsDownstreamRecords() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(true);
        Test.setMock(HttpCalloutMock.class, new DocuSignMock());

        Test.startTest();
        KT_DocuSignEnvelopeService.EnvelopeResult documentResult =
            KT_DocuSignEnvelopeService.retrieveCompletedDocument(signatureRequest.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, documentResult.contentDocumentId);

        KT_Signature_Request__c updatedRequest = [
            SELECT Status__c, Completed_Document_Id__c, KT_DocumentVault__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('Fully Signed', updatedRequest.Status__c);
        System.assertEquals(String.valueOf(documentResult.contentDocumentId), updatedRequest.Completed_Document_Id__c);

        KT_DocumentVault__c updatedVault = [
            SELECT Status__c, Signature_Status__c, Content_Document_Id__c, Document_Request__c
            FROM KT_DocumentVault__c
            WHERE Id = :updatedRequest.KT_DocumentVault__c
        ];
        System.assertEquals('Signed', updatedVault.Status__c);
        System.assertEquals('Fully Signed', updatedVault.Signature_Status__c);
        System.assertEquals(documentResult.contentDocumentId, updatedVault.Content_Document_Id__c);

        System.assertEquals('Complete', [
            SELECT Status__c
            FROM KT_Document_Request__c
            WHERE Id = :updatedVault.Document_Request__c
        ].Status__c);
    }

    @IsTest
    static void missingEnvelopeIdIsRejected() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest(false);

        try {
            KT_DocuSignEnvelopeService.sendEnvelope(signatureRequest.Id, null);
            System.assert(false, 'Expected send without envelope id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
