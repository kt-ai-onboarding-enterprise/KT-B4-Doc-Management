public with sharing class KT_DocumentVaultService {
    public class VaultEntryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String documentName;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String documentType;
        @AuraEnabled public String status;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public Boolean isExpired;
        @AuraEnabled public String ocrStatus;
        @AuraEnabled public Decimal versionNumber;
        @AuraEnabled public String signatureStatus;
        @AuraEnabled public String regulatoryTag;
        @AuraEnabled public Datetime uploadTimestamp;
        @AuraEnabled public String uploadedByName;
        @AuraEnabled public Id documentRequestId;
        @AuraEnabled public String hrNotes;
    }

    public class VersionRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String versionNumber;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String fileType;
        @AuraEnabled public Integer contentSize;
    }

    @AuraEnabled(cacheable=true)
    public static List<VaultEntryRow> getVaultEntries(Id onboardingId) {
        if (onboardingId == null) {
            return new List<VaultEntryRow>();
        }

        List<VaultEntryRow> rows = new List<VaultEntryRow>();
        for (KT_DocumentVault__c entry : [
            SELECT Id, Document_Name__c, Content_Document_Id__c, Document_Type__c, Status__c,
                   Expiry_Date__c, Is_Expired__c, OCR_Status__c, Version_Number__c,
                   Signature_Status__c, Regulatory_Tag__c, Upload_Timestamp__c,
                   Uploaded_By__r.Name, Document_Request__c, Document_Request__r.Waiver_Reason__c
            FROM KT_DocumentVault__c
            WHERE KT_Onboarding__c = :onboardingId
            ORDER BY Document_Type__c ASC, Upload_Timestamp__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            rows.add(toRow(entry));
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<VersionRow> getVersionHistory(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return new List<VersionRow>();
        }

        Id documentId = (Id) contentDocumentId;
        List<VersionRow> rows = new List<VersionRow>();
        for (ContentVersion version : [
            SELECT Id, Title, VersionNumber, CreatedDate, CreatedBy.Name, FileType, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :documentId
            ORDER BY VersionNumber DESC
        ]) {
            VersionRow row = new VersionRow();
            row.id = version.Id;
            row.title = version.Title;
            row.versionNumber = version.VersionNumber;
            row.createdDate = version.CreatedDate;
            row.createdByName = version.CreatedBy.Name;
            row.fileType = version.FileType;
            row.contentSize = version.ContentSize;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void archiveVaultEntry(Id vaultEntryId) {
        updateStatus(vaultEntryId, 'Archived', null, null);
    }

    @AuraEnabled
    public static void requestSignature(Id vaultEntryId) {
        updateStatus(vaultEntryId, 'Pending Signature', 'Pending', null);
    }

    @AuraEnabled
    public static void triggerOCR(Id vaultEntryId) {
        updateStatus(vaultEntryId, null, null, 'Pending');
    }

    @AuraEnabled
    public static void waiveDocument(Id vaultEntryId, String waiverReason) {
        if (vaultEntryId == null) {
            throw new AuraHandledException('vaultEntryId is required.');
        }
        if (String.isBlank(waiverReason)) {
            throw new AuraHandledException('waiverReason is required.');
        }

        KT_DocumentVault__c vaultEntry = [
            SELECT Id, Document_Request__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntryId
            LIMIT 1
            FOR UPDATE
        ];
        vaultEntry.Status__c = 'Archived';
        update vaultEntry;

        if (vaultEntry.Document_Request__c != null) {
            update new KT_Document_Request__c(
                Id = vaultEntry.Document_Request__c,
                Status__c = 'Waived',
                Waiver_Reason__c = waiverReason.left(255),
                Completed_Date__c = System.now()
            );
        }
    }

    private static void updateStatus(Id vaultEntryId, String status, String signatureStatus, String ocrStatus) {
        if (vaultEntryId == null) {
            throw new AuraHandledException('vaultEntryId is required.');
        }

        KT_DocumentVault__c vaultEntry = [
            SELECT Id, Status__c, Signature_Status__c, OCR_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntryId
            LIMIT 1
            FOR UPDATE
        ];
        if (status != null) {
            vaultEntry.Status__c = status;
        }
        if (signatureStatus != null) {
            vaultEntry.Signature_Status__c = signatureStatus;
        }
        if (ocrStatus != null) {
            vaultEntry.OCR_Status__c = ocrStatus;
        }
        update vaultEntry;
    }

    private static VaultEntryRow toRow(KT_DocumentVault__c entry) {
        VaultEntryRow row = new VaultEntryRow();
        row.id = entry.Id;
        row.documentName = entry.Document_Name__c;
        row.contentDocumentId = entry.Content_Document_Id__c;
        row.documentType = entry.Document_Type__c;
        row.status = entry.Status__c;
        row.expiryDate = entry.Expiry_Date__c;
        row.isExpired = entry.Is_Expired__c;
        row.ocrStatus = entry.OCR_Status__c;
        row.versionNumber = entry.Version_Number__c;
        row.signatureStatus = entry.Signature_Status__c;
        row.regulatoryTag = entry.Regulatory_Tag__c;
        row.uploadTimestamp = entry.Upload_Timestamp__c;
        row.uploadedByName = entry.Uploaded_By__r == null ? null : entry.Uploaded_By__r.Name;
        row.documentRequestId = entry.Document_Request__c;
        row.hrNotes = entry.Document_Request__r == null ? null : entry.Document_Request__r.Waiver_Reason__c;
        return row;
    }
}
