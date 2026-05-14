@IsTest
private class KT_AuditExportServiceTest {
    private static Id createContentDocument(String title, String body) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(body)
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
        insert new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            ContentDocumentId = contentDocumentId,
            VersionData = Blob.valueOf(body + ' v2')
        );
        return contentDocumentId;
    }

    @IsTest
    static void exportAuditPackageCreatesCertifiedPdfAndVaultEntry() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Offer Letter',
            Content_Document_Id__c = createContentDocument('Offer Letter', 'offer body'),
            Document_Type__c = 'Generated',
            Status__c = 'Signed',
            OCR_Status__c = 'Accepted',
            Signature_Status__c = 'Fully Signed',
            Version_Number__c = 2,
            Regulatory_Tag__c = 'SOX'
        );
        insert vaultEntry;

        KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
            KT_Onboarding__c = onboarding.Id,
            KT_DocumentVault__c = vaultEntry.Id,
            Signing_Provider__c = 'KT Sign',
            Status__c = 'Fully Signed',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 1,
            Expiry_Date__c = Date.today().addDays(5)
        );
        insert signatureRequest;

        KT_Signer__c signer = new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Signer One',
            Signer_Email__c = 'signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Signed',
            Signed_At__c = System.now()
        );
        insert signer;

        insert new KT_Signature_Audit__c(
            KT_Signature_Request__c = signatureRequest.Id,
            KT_Signer__c = signer.Id,
            Event_Type__c = 'Signature Captured',
            Event_Timestamp__c = System.now(),
            IP_Address__c = '203.0.113.10',
            Device_User_Agent__c = 'Unit Test Browser',
            Hash_Value__c = 'abc123',
            Session_Token__c = 'token'
        );

        insert new KT_OCR_Job__c(
            KT_Onboarding__c = onboarding.Id,
            KT_DocumentVault__c = vaultEntry.Id,
            OCR_Provider__c = 'AWS Textract',
            Job_Id__c = 'job-1',
            Status__c = 'Accepted',
            Document_Type_Detected__c = 'Offer Letter',
            Confidence_Score__c = 95,
            Reviewed_By__c = UserInfo.getUserId(),
            Reviewed_At__c = System.now(),
            Retry_Count__c = 0
        );

        Test.startTest();
        KT_AuditExportService.AuditExportResult result =
            KT_AuditExportService.exportAuditPackage(onboarding.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.contentDocumentId);
        System.assertNotEquals(null, result.certificationHash);
        System.assertEquals(1, result.documentCount);
        System.assertEquals(1, result.signatureAuditCount);
        System.assertEquals(1, result.ocrJobCount);

        ContentVersion exportVersion = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :result.contentVersionId
        ];
        System.assert(exportVersion.VersionData.toString().startsWith('%PDF-1.4'));

        KT_DocumentVault__c exportVault = [
            SELECT Document_Type__c, Status__c, Content_Document_Id__c, Regulatory_Tag__c
            FROM KT_DocumentVault__c
            WHERE Id = :result.vaultEntryId
        ];
        System.assertEquals('Compliance Record', exportVault.Document_Type__c);
        System.assertEquals('Verified', exportVault.Status__c);
        System.assertEquals('Audit Export', exportVault.Regulatory_Tag__c);
        System.assertEquals(result.contentDocumentId, exportVault.Content_Document_Id__c);
    }

    @IsTest
    static void invocableHandlesMissingAndValidRequests() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_AuditExportService.AuditExportRequest missingRequest =
            new KT_AuditExportService.AuditExportRequest();

        KT_AuditExportService.AuditExportRequest validRequest =
            new KT_AuditExportService.AuditExportRequest();
        validRequest.onboardingId = onboarding.Id;

        Test.startTest();
        List<KT_AuditExportService.AuditExportResult> results =
            KT_AuditExportService.generateAuditExports(
                new List<KT_AuditExportService.AuditExportRequest>{ missingRequest, validRequest }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assert(results[0].message.contains('required'));
        System.assertEquals('Certified audit export generated.', results[1].message);
        System.assertNotEquals(null, results[1].contentDocumentId);
    }

    @IsTest
    static void auraExportRequiresOnboardingId() {
        try {
            KT_AuditExportService.exportAuditPackage(null);
            System.assert(false, 'Expected missing onboarding id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
