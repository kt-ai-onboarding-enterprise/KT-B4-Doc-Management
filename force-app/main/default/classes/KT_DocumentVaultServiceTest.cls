@IsTest
private class KT_DocumentVaultServiceTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static Id createContentDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'Vault File',
            PathOnClient = 'vault-file.pdf',
            VersionData = Blob.valueOf('v1')
        );
        insert version;
        Id documentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
        insert new ContentVersion(
            Title = 'Vault File',
            PathOnClient = 'vault-file.pdf',
            ContentDocumentId = documentId,
            VersionData = Blob.valueOf('v2')
        );
        return documentId;
    }

    @IsTest
    static void getVaultEntriesAndVersionHistoryReturnRows() {
        KT_Onboarding__c onboarding = createOnboarding();
        Id contentDocumentId = createContentDocument();
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Vault File',
            Content_Document_Id__c = contentDocumentId,
            Document_Type__c = 'Uploaded',
            Status__c = 'Draft',
            Expiry_Date__c = Date.today().addDays(-1),
            Uploaded_By__c = UserInfo.getUserId(),
            Upload_Timestamp__c = System.now(),
            OCR_Status__c = 'Pending',
            Version_Number__c = 2,
            Signature_Status__c = 'Not Required',
            Regulatory_Tag__c = 'SOX'
        );
        insert vaultEntry;

        Test.startTest();
        List<KT_DocumentVaultService.VaultEntryRow> entries = KT_DocumentVaultService.getVaultEntries(onboarding.Id);
        List<KT_DocumentVaultService.VersionRow> versions =
            KT_DocumentVaultService.getVersionHistory(String.valueOf(contentDocumentId));
        Test.stopTest();

        System.assertEquals(1, entries.size());
        System.assertEquals('Vault File', entries[0].documentName);
        System.assertEquals(true, entries[0].isExpired);
        System.assertEquals('SOX', entries[0].regulatoryTag);
        System.assertEquals(2, versions.size());
    }

    @IsTest
    static void quickActionsUpdateVaultAndRequest() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'In Progress',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert request;
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Action File',
            Document_Type__c = 'Uploaded',
            Status__c = 'Draft',
            Document_Request__c = request.Id,
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;

        Test.startTest();
        KT_DocumentVaultService.requestSignature(vaultEntry.Id);
        KT_DocumentVaultService.triggerOCR(vaultEntry.Id);
        KT_DocumentVaultService.archiveVaultEntry(vaultEntry.Id);
        KT_DocumentVaultService.waiveDocument(vaultEntry.Id, 'No longer needed');
        Test.stopTest();

        KT_DocumentVault__c updatedVault = [
            SELECT Status__c, Signature_Status__c, OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntry.Id
        ];
        System.assertEquals('Archived', updatedVault.Status__c);
        System.assertEquals('Pending', updatedVault.Signature_Status__c);
        System.assertEquals('Pending', updatedVault.OCR_Status__c);

        KT_Document_Request__c updatedRequest = [
            SELECT Status__c, Waiver_Reason__c, Completed_Date__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('Waived', updatedRequest.Status__c);
        System.assertEquals('No longer needed', updatedRequest.Waiver_Reason__c);
        System.assertNotEquals(null, updatedRequest.Completed_Date__c);

        List<KT_DocumentVaultService.VaultEntryRow> rows = KT_DocumentVaultService.getVaultEntries(onboarding.Id);
        System.assertEquals('No longer needed', rows[0].hrNotes);
    }

    @IsTest
    static void emptyInputsReturnEmptyListsOrErrors() {
        System.assertEquals(0, KT_DocumentVaultService.getVaultEntries(null).size());
        System.assertEquals(0, KT_DocumentVaultService.getVersionHistory(null).size());

        try {
            KT_DocumentVaultService.archiveVaultEntry(null);
            System.assert(false, 'Expected missing vault entry id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentVaultService.waiveDocument(null, 'reason');
            System.assert(false, 'Expected missing vault entry id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
