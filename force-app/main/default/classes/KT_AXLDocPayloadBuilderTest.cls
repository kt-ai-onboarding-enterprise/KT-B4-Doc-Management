@IsTest
private class KT_AXLDocPayloadBuilderTest {
    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'AXL Payload Source',
            PathOnClient = 'axl-payload-source.pdf',
            VersionData = Blob.valueOf('axl payload source')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    private static Id createSignatureRequest() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'AXL Payload Offer',
            Content_Document_Id__c = createContentDocument(),
            Document_Type__c = 'Generated',
            Status__c = 'Pending Signature',
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Pending'
        );
        insert vault;

        KT_Signature_Request__c request = new KT_Signature_Request__c(
            KT_DocumentVault__c = vault.Id,
            KT_Onboarding__c = onboarding.Id,
            Signing_Provider__c = 'KT Sign',
            Status__c = 'In Progress',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7)
        );
        insert request;

        insert new KT_Signer__c(
            KT_Signature_Request__c = request.Id,
            Signer_Name__c = 'AXL Payload Signer',
            Signer_Email__c = 'axl.payload.signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Invitation Sent'
        );
        return request.Id;
    }

    @IsTest
    static void delegatesSlackPayloadToSigningTileService() {
        Id requestId = createSignatureRequest();

        KT_AXLDocPayloadBuilder.PayloadResult result = KT_AXLDocPayloadBuilder.buildPayload(requestId, 'Slack');

        System.assertEquals(requestId, result.signatureRequestId);
        System.assertEquals('Slack', result.channel);
        System.assert(result.signingUrl.contains('c__sessionToken='));
        System.assert(result.cardPayload.contains('blocks'));
        System.assertEquals('AXL document payload generated.', result.message);
    }

    @IsTest
    static void delegatesTeamsPayloadViaInvocable() {
        Id requestId = createSignatureRequest();
        KT_AXLDocPayloadBuilder.PayloadRequest request = new KT_AXLDocPayloadBuilder.PayloadRequest();
        request.signatureRequestId = requestId;
        request.channel = 'Teams';

        List<KT_AXLDocPayloadBuilder.PayloadResult> results =
            KT_AXLDocPayloadBuilder.buildPayloads(new List<KT_AXLDocPayloadBuilder.PayloadRequest>{ request });

        System.assertEquals(1, results.size());
        System.assertEquals('Teams', results[0].channel);
        System.assert(results[0].cardPayload.contains('AdaptiveCard'));
    }
}
