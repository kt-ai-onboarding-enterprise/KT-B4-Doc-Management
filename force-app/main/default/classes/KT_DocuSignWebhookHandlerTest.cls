@IsTest
private class KT_DocuSignWebhookHandlerTest {
    private class CompletedDocumentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('/documents/combined'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/pdf');
            response.setBody('%PDF-1.4 docusign completed');
            return response;
        }
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'Webhook Source',
            PathOnClient = 'webhook-source.pdf',
            VersionData = Blob.valueOf('source')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    private static KT_Signature_Request__c createSignatureRequest(String envelopeId) {
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
            Document_Name__c = 'Webhook Source',
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
            KT_Onboarding__c = onboarding.Id,
            KT_DocumentVault__c = vault.Id,
            Signing_Provider__c = 'DocuSign',
            Status__c = 'Configured',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7),
            External_Envelope_Id__c = envelopeId
        );
        insert signatureRequest;

        insert new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Webhook Signer',
            Signer_Email__c = 'webhook.signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Pending'
        );

        return signatureRequest;
    }

    @IsTest
    static void sentWebhookMarksRequestInProgress() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-sent');
        runWebhook('{"envelopeId":"env-sent","status":"sent"}', 'secret', true);

        System.assertEquals(200, RestContext.response.statusCode);
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
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signature_Audit__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            AND Event_Type__c = 'Invitation Sent'
        ]);
    }

    @IsTest
    static void completedWebhookRetrievesDocumentAndCompletesRecords() {
        Test.setMock(HttpCalloutMock.class, new CompletedDocumentMock());
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-complete');

        Test.startTest();
        runWebhook('{"data":{"envelopeId":"env-complete","status":"completed","accountId":"acct-1"}}', 'secret', true);
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        KT_Signature_Request__c updatedRequest = [
            SELECT Status__c, Completed_Document_Id__c, KT_DocumentVault__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ];
        System.assertEquals('Fully Signed', updatedRequest.Status__c);
        System.assertNotEquals(null, updatedRequest.Completed_Document_Id__c);

        KT_DocumentVault__c vault = [
            SELECT Status__c, Signature_Status__c, Document_Request__c
            FROM KT_DocumentVault__c
            WHERE Id = :updatedRequest.KT_DocumentVault__c
        ];
        System.assertEquals('Signed', vault.Status__c);
        System.assertEquals('Fully Signed', vault.Signature_Status__c);
        System.assertEquals('Complete', [
            SELECT Status__c
            FROM KT_Document_Request__c
            WHERE Id = :vault.Document_Request__c
        ].Status__c);
    }

    @IsTest
    static void declinedWebhookCancelsRequestAndMarksSigner() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-declined');
        runWebhook('{"envelopeId":"env-declined","event":"recipient-declined"}', 'secret', true);

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Cancelled', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
        System.assertEquals('Declined', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void deliveredWebhookMarksSignerViewed() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-delivered');
        runWebhook('{"envelopeId":"env-delivered","event":"recipient-delivered"}', 'secret', true);

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Viewed', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signature_Audit__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            AND Event_Type__c = 'Document Viewed'
        ]);
    }

    @IsTest
    static void expiredWebhookMarksRequestExpired() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-expired');
        runWebhook('{"envelopeId":"env-expired","status":"expired"}', 'secret', true);

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Expired', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
        System.assertEquals('Expired', [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void voidedWebhookCancelsRequest() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('env-voided');
        runWebhook('{"envelopeId":"env-voided","status":"voided"}', 'secret', true);

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Cancelled', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
    }

    @IsTest
    static void invalidSignatureReturnsUnauthorized() {
        createSignatureRequest('env-bad');
        runWebhook('{"envelopeId":"env-bad","status":"sent"}', 'secret', false);

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void malformedPayloadReturnsBadRequest() {
        runWebhook('not-json', 'secret', true);

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void unknownEnvelopeReturnsNotFound() {
        runWebhook('{"envelopeId":"missing-env","status":"sent"}', 'secret', true);

        System.assertEquals(404, RestContext.response.statusCode);
    }

    private static void runWebhook(String payload, String secret, Boolean validSignature) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/docusign/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        request.addHeader('X-DocuSign-Signature-1', validSignature ? buildSignature(payload, secret) : 'not-valid');
        request.addHeader('User-Agent', 'DocuSign Unit Test');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_DocuSignWebhookHandler.webhookSecretOverride = secret;
        KT_DocuSignWebhookHandler.handleWebhook();
    }

    private static String buildSignature(String payload, String secret) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        return EncodingUtil.base64Encode(mac);
    }
}
