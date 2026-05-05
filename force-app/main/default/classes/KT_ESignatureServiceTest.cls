@IsTest
private class KT_ESignatureServiceTest {
    private static KT_Signer__c createSigner(String status) {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Evidence Document',
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
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7),
            Signing_Order__c = 'Sequential',
            Initiated_By__c = UserInfo.getUserId()
        );
        insert request;
        KT_Signer__c signer = new KT_Signer__c(
            KT_Signature_Request__c = request.Id,
            Signer_Name__c = 'Signer',
            Signer_Email__c = 'signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = status
        );
        insert signer;
        return signer;
    }

    @IsTest
    static void tokenLifecycleIssuesValidatesAndInvalidates() {
        KT_Signer__c signer = createSigner('Invitation Sent');

        Test.startTest();
        KT_ESignatureService.SessionTokenResult issued = KT_ESignatureService.issueSessionToken(signer.Id);
        Boolean valid = KT_ESignatureService.validateSessionToken(signer.Id, issued.sessionToken);
        KT_ESignatureService.SigningSession session = KT_ESignatureService.getSigningSession(signer.Id, issued.sessionToken);
        KT_ESignatureService.invalidateSessionToken(signer.Id);
        Boolean validAfterInvalidation = KT_ESignatureService.validateSessionToken(signer.Id, issued.sessionToken);
        Test.stopTest();

        System.assertEquals(true, issued.valid);
        System.assertEquals(true, valid);
        System.assertEquals(true, session.valid);
        System.assertEquals('signer@example.com', session.signerEmail);
        System.assertEquals(false, validAfterInvalidation);
    }

    @IsTest
    static void captureLegalEvidenceCreatesAuditAndUpdatesSigner() {
        KT_Signer__c signer = createSigner('Invitation Sent');
        KT_ESignatureService.LegalEvidence evidence = new KT_ESignatureService.LegalEvidence();
        evidence.ipAddress = '203.0.113.50';
        evidence.deviceUserAgent = 'Unit Test Browser';
        evidence.latitude = 10.12345;
        evidence.longitude = 20.12345;
        evidence.sessionToken = 'token';

        Test.startTest();
        Id auditId = KT_ESignatureService.captureLegalEvidence(signer.Id, 'Document Viewed', evidence);
        String hashValue = KT_ESignatureService.generateSignatureHash('doc-hash', 'SIGNER@EXAMPLE.COM', Datetime.newInstance(2026, 1, 1, 0, 0, 0));
        Test.stopTest();

        System.assertNotEquals(null, hashValue);
        KT_Signature_Audit__c audit = [
            SELECT Event_Type__c, IP_Address__c, Device_User_Agent__c, Session_Token__c
            FROM KT_Signature_Audit__c
            WHERE Id = :auditId
        ];
        System.assertEquals('Document Viewed', audit.Event_Type__c);
        System.assertEquals('203.0.113.50', audit.IP_Address__c);
        System.assertEquals('Unit Test Browser', audit.Device_User_Agent__c);
        System.assertEquals('token', audit.Session_Token__c);

        KT_Signer__c updatedSigner = [
            SELECT IP_Address__c, Device_User_Agent__c
            FROM KT_Signer__c
            WHERE Id = :signer.Id
        ];
        System.assertEquals('203.0.113.50', updatedSigner.IP_Address__c);
        System.assertEquals('Unit Test Browser', updatedSigner.Device_User_Agent__c);
    }

    @IsTest
    static void rejectsIneligibleOrMissingInputs() {
        KT_Signer__c signed = createSigner('Signed');

        try {
            KT_ESignatureService.issueSessionToken(signed.Id);
            System.assert(false, 'Expected signed signer to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        System.assertEquals(false, KT_ESignatureService.validateSessionToken(null, 'token'));

        try {
            KT_ESignatureService.captureLegalEvidence(null, 'Signed', null);
            System.assert(false, 'Expected missing signer id to fail.');
        } catch (KT_ESignatureService.ESignatureServiceException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
