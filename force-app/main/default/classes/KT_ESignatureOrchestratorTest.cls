@IsTest
private class KT_ESignatureOrchestratorTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'Signable Document',
            PathOnClient = 'signable.pdf',
            VersionData = Blob.valueOf('contract body')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static KT_DocumentVault__c createVault(Id onboardingId) {
        return createVault(onboardingId, null);
    }

    private static KT_DocumentVault__c createVault(Id onboardingId, String regulatoryTag) {
        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboardingId,
            Document_Name__c = 'Signable Document',
            Content_Document_Id__c = createContentDocument(),
            Document_Type__c = 'Generated',
            Status__c = 'Draft',
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required',
            Regulatory_Tag__c = regulatoryTag
        );
        insert vault;
        return vault;
    }

    private static KT_ESignatureOrchestrator.SignatureConfig twoSignerConfig(String signingOrder) {
        KT_ESignatureOrchestrator.SignatureConfig config = new KT_ESignatureOrchestrator.SignatureConfig();
        config.signingProvider = 'KT Sign';
        config.signingOrder = signingOrder;
        config.expiryDays = 7;
        config.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();

        KT_ESignatureOrchestrator.SignerConfig first = new KT_ESignatureOrchestrator.SignerConfig();
        first.signerName = 'First Signer';
        first.signerEmail = 'first@example.com';
        first.signerRole = 'Onboardee';
        first.signingOrder = 1;
        config.signers.add(first);

        KT_ESignatureOrchestrator.SignerConfig second = new KT_ESignatureOrchestrator.SignerConfig();
        second.signerName = 'Second Signer';
        second.signerEmail = 'second@example.com';
        second.signerRole = 'HR Admin';
        second.signingOrder = 2;
        config.signers.add(second);
        return config;
    }

    @IsTest
    static void sequentialWorkflowDispatchesAndCompletes() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vault = createVault(onboarding.Id);
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Awaiting Signature',
            Document_Direction__c = 'Outbound',
            Is_Required__c = true,
            Document_Vault_Entry__c = vault.Id
        );
        insert request;

        Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, twoSignerConfig('Sequential'));

        List<KT_Signer__c> signers = [
            SELECT Id, Status__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            ORDER BY Signing_Order__c ASC
        ];
        System.assertEquals('Invitation Sent', signers[0].Status__c);
        System.assertEquals('Pending', signers[1].Status__c);

        KT_ESignatureOrchestrator.SignaturePayload firstPayload = new KT_ESignatureOrchestrator.SignaturePayload();
        firstPayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('first signature'));
        firstPayload.ipAddress = '203.0.113.10';
        firstPayload.deviceUserAgent = 'Unit Test';
        firstPayload.latitude = 12.34;
        firstPayload.longitude = 56.78;
        firstPayload.sessionToken = 'token-1';

        Boolean firstCompletedWorkflow = KT_ESignatureOrchestrator.handleSignatureComplete(signers[0].Id, firstPayload);
        System.assertEquals(false, firstCompletedWorkflow);

        signers = [
            SELECT Id, Status__c, Signing_Order__c, Signature_Image_Id__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            ORDER BY Signing_Order__c ASC
        ];
        System.assertEquals('Signed', signers[0].Status__c);
        System.assertNotEquals(null, signers[0].Signature_Image_Id__c);
        System.assertEquals('Invitation Sent', signers[1].Status__c);

        KT_ESignatureOrchestrator.SignatureCompletionRequest completionRequest =
            new KT_ESignatureOrchestrator.SignatureCompletionRequest();
        completionRequest.signerId = signers[1].Id;
        completionRequest.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('second signature'));
        completionRequest.ipAddress = '203.0.113.11';
        completionRequest.deviceUserAgent = 'Unit Test';

        List<KT_ESignatureOrchestrator.SignatureCompletionResult> results =
            KT_ESignatureOrchestrator.handleSignatureComplete(
                new List<KT_ESignatureOrchestrator.SignatureCompletionRequest>{ completionRequest }
            );

        System.assertEquals(true, results[0].workflowComplete);

        KT_Signature_Request__c signatureRequest = [
            SELECT Status__c, Completed_Signers__c, Total_Signers__c, Completed_Document_Id__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
        ];
        System.assertEquals('Fully Signed', signatureRequest.Status__c);
        System.assertEquals(2, signatureRequest.Completed_Signers__c);
        System.assertEquals(2, signatureRequest.Total_Signers__c);
        System.assertNotEquals(null, signatureRequest.Completed_Document_Id__c);

        KT_DocumentVault__c updatedVault = [
            SELECT Status__c, Signature_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vault.Id
        ];
        System.assertEquals('Signed', updatedVault.Status__c);
        System.assertEquals('Fully Signed', updatedVault.Signature_Status__c);

        KT_Document_Request__c updatedRequest = [
            SELECT Status__c, Completed_Date__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('Complete', updatedRequest.Status__c);
        System.assertNotEquals(null, updatedRequest.Completed_Date__c);
    }

    @IsTest
    static void delegationCreatesDelegateAndExpiryEscalatesPendingSigner() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vault = createVault(onboarding.Id);

        Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, twoSignerConfig('Parallel'));

        KT_Signer__c original = [
            SELECT Id
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            ORDER BY Signing_Order__c ASC
            LIMIT 1
        ];

        Id delegateId = KT_ESignatureOrchestrator.handleDelegation(original.Id, 'delegate@example.com', 'Out of office');
        KT_ESignatureOrchestrator.handleExpiryEscalation(signatureRequestId);

        KT_Signer__c delegated = [
            SELECT Status__c, Delegated_To__c, Delegation_Reason__c
            FROM KT_Signer__c
            WHERE Id = :original.Id
        ];
        System.assertEquals('Delegated', delegated.Status__c);
        System.assertEquals('delegate@example.com', delegated.Delegated_To__c);
        System.assertEquals('Out of office', delegated.Delegation_Reason__c);

        KT_Signer__c delegateSigner = [
            SELECT Status__c
            FROM KT_Signer__c
            WHERE Id = :delegateId
        ];
        System.assertEquals('Expired', delegateSigner.Status__c);

        KT_Signature_Request__c request = [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
        ];
        System.assertEquals('Expired', request.Status__c);
    }

    @IsTest
    static void rejectsMissingInputs() {
        try {
            KT_ESignatureOrchestrator.initiateSigningWorkflow(null, twoSignerConfig('Sequential'));
            System.assert(false, 'Expected missing vault id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_ESignatureOrchestrator.handleDelegation(null, 'delegate@example.com', 'reason');
            System.assert(false, 'Expected missing signer id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }

    @IsTest
    static void completeSignatureAuraWrapperValidatesToken() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vault = createVault(onboarding.Id);
        Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, twoSignerConfig('Sequential'));
        KT_Signer__c signer = [
            SELECT Id
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            ORDER BY Signing_Order__c ASC
            LIMIT 1
        ];
        KT_ESignatureService.SessionTokenResult token = KT_ESignatureService.issueSessionToken(signer.Id);

        Test.startTest();
        Boolean complete = KT_ESignatureOrchestrator.completeSignature(
            signer.Id,
            EncodingUtil.base64Encode(Blob.valueOf('signature')),
            '203.0.113.20',
            'Unit Test',
            null,
            null,
            token.sessionToken
        );
        Test.stopTest();

        System.assertEquals(false, complete);
        System.assertEquals(false, KT_ESignatureService.validateSessionToken(signer.Id, token.sessionToken));
    }

    @IsTest
    static void highValueWorkflowRequiresTrustedAgentIdentity() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vault = createVault(onboarding.Id, 'HIPAA;SOX');
        KT_ESignatureOrchestrator.SignatureConfig config = twoSignerConfig('Sequential');
        config.signers.remove(1);

        Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, config);
        KT_Signature_Request__c highValueRequest = [
            SELECT Requires_Trusted_Agent_Identity__c, Trusted_Agent_Verification_Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
        ];
        System.assertEquals(true, highValueRequest.Requires_Trusted_Agent_Identity__c);
        System.assertEquals('Pending', highValueRequest.Trusted_Agent_Verification_Status__c);

        KT_Signer__c signer = [
            SELECT Id
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            LIMIT 1
        ];
        KT_ESignatureOrchestrator.SignaturePayload payload = new KT_ESignatureOrchestrator.SignaturePayload();
        payload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('high value signature'));
        payload.ipAddress = '203.0.113.31';
        payload.deviceUserAgent = 'Trusted Identity Unit Test';

        try {
            KT_ESignatureOrchestrator.handleSignatureComplete(signer.Id, payload);
            System.assert(false, 'Expected trusted identity gate to block completion.');
        } catch (KT_ESignatureOrchestrator.ESignatureException expected) {
            System.assert(expected.getMessage().contains('Trusted Agent Identity'));
        }

        KT_ESignatureOrchestrator.TrustedAgentIdentityResult verification =
            KT_ESignatureOrchestrator.verifyTrustedAgentIdentity(signatureRequestId, 'push-ref-123', true);
        System.assertEquals('Verified', verification.status);

        Boolean workflowComplete = KT_ESignatureOrchestrator.handleSignatureComplete(signer.Id, payload);
        System.assertEquals(true, workflowComplete);

        KT_Signature_Request__c completedRequest = [
            SELECT Status__c, Trusted_Agent_Verification_Status__c, Trusted_Agent_Verified_At__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
        ];
        System.assertEquals('Fully Signed', completedRequest.Status__c);
        System.assertEquals('Verified', completedRequest.Trusted_Agent_Verification_Status__c);
        System.assertNotEquals(null, completedRequest.Trusted_Agent_Verified_At__c);

        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signature_Audit__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Event_Type__c = 'Trusted Identity Verified'
        ]);
    }
}
