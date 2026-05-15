@IsTest
private class KT_AdobeSignWebhookHandlerTest {
    private class CompletedDocumentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('/combinedDocument'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/pdf');
            response.setBody('%PDF-1.4 adobe webhook completed');
            return response;
        }
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'Adobe Webhook Source',
            PathOnClient = 'adobe-webhook-source.pdf',
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

    private static KT_Signature_Request__c createSignatureRequest(String agreementId) {
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
            Document_Name__c = 'Adobe Webhook Source',
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
            Signing_Provider__c = 'Adobe Sign',
            Status__c = 'In Progress',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7),
            External_Envelope_Id__c = agreementId
        );
        insert signatureRequest;

        insert new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Adobe Webhook Signer',
            Signer_Email__c = 'adobe.webhook@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Invitation Sent'
        );

        return signatureRequest;
    }

    @IsTest
    static void getVerificationEchoesAdobeClientId() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/adobesign/webhook';
        request.httpMethod = 'GET';
        request.addHeader('X-AdobeSign-ClientId', 'client-123');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_AdobeSignWebhookHandler.verificationTokenOverride = 'client-123';

        KT_AdobeSignWebhookHandler.verifyWebhook();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('client-123', RestContext.response.headers.get('X-AdobeSign-ClientId'));
    }

    @IsTest
    static void getVerificationRejectsWrongClientId() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/adobesign/webhook';
        request.httpMethod = 'GET';
        request.addHeader('X-AdobeSign-ClientId', 'wrong');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_AdobeSignWebhookHandler.verificationTokenOverride = 'client-123';

        KT_AdobeSignWebhookHandler.verifyWebhook();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void completedWebhookRetrievesDocumentAndCompletesRecords() {
        Test.setMock(HttpCalloutMock.class, new CompletedDocumentMock());
        KT_Signature_Request__c signatureRequest = createSignatureRequest('agr-complete');

        Test.startTest();
        runWebhook('{"event":"AGREEMENT_ACTION_COMPLETED","agreement":{"id":"agr-complete"}}', 'client-123');
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
    static void recalledWebhookCancelsRequest() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('agr-recalled');
        runWebhook('{"event":"AGREEMENT_RECALLED","agreementId":"agr-recalled"}', 'client-123');

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
    static void expiredWebhookExpiresRequest() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('agr-expired');
        runWebhook('{"data":{"eventType":"AGREEMENT_EXPIRED","agreementId":"agr-expired"}}', 'client-123');

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
    static void outForSignatureWebhookMarksRequestInProgress() {
        KT_Signature_Request__c signatureRequest = createSignatureRequest('agr-progress');
        runWebhook('{"event":"AGREEMENT_OUT_FOR_SIGNATURE","agreementInfo":{"agreementId":"agr-progress"}}', 'client-123');

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
    }

    @IsTest
    static void unsupportedEventReturnsBadRequest() {
        createSignatureRequest('agr-unsupported');
        runWebhook('{"event":"AGREEMENT_CREATED","agreementId":"agr-unsupported"}', 'client-123');

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void invalidVerificationTokenReturnsUnauthorized() {
        createSignatureRequest('agr-bad-token');
        RestRequest request = basePost('{"event":"AGREEMENT_RECALLED","agreementId":"agr-bad-token"}');
        request.addHeader('X-AdobeSign-ClientId', 'wrong');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_AdobeSignWebhookHandler.verificationTokenOverride = 'client-123';

        KT_AdobeSignWebhookHandler.handleWebhook();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void malformedPayloadReturnsBadRequest() {
        RestRequest request = basePost('not-json');
        request.addHeader('X-AdobeSign-ClientId', 'client-123');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_AdobeSignWebhookHandler.verificationTokenOverride = 'client-123';

        KT_AdobeSignWebhookHandler.handleWebhook();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    private static void runWebhook(String payload, String token) {
        RestRequest request = basePost(payload);
        request.addHeader('X-AdobeSign-ClientId', token);
        request.addHeader('User-Agent', 'Adobe Sign Unit Test');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        KT_AdobeSignWebhookHandler.verificationTokenOverride = token;
        KT_AdobeSignWebhookHandler.handleWebhook();
    }

    private static RestRequest basePost(String payload) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/kt/v1/adobesign/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(payload);
        return request;
    }
}
