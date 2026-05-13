public with sharing class KT_DocumentUploadService {
    private static final Integer MAX_FILE_BYTES = 26214400;
    private static final Set<String> ALLOWED_EXTENSIONS = new Set<String>{ 'pdf', 'jpg', 'jpeg', 'png', 'docx' };

    public class UploadResult {
        @AuraEnabled public Id vaultEntryId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id documentRequestId;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class UploadException extends Exception {}

    @AuraEnabled
    public static UploadResult uploadDocument(Id onboardingId, Id documentRequestId, String fileName, String base64Data, String contentType) {
        if (onboardingId == null) {
            throw new AuraHandledException('onboardingId is required.');
        }
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('fileName is required.');
        }
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('file data is required.');
        }

        String extension = getExtension(fileName);
        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new AuraHandledException('Unsupported file type.');
        }

        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(stripDataUrlPrefix(base64Data));
        } catch (Exception decodeException) {
            throw new AuraHandledException('File data could not be decoded.');
        }

        if (fileBody.size() > MAX_FILE_BYTES) {
            throw new AuraHandledException('File exceeds the 25MB limit.');
        }

        ScanDecision scanDecision = performVirusScan(fileName, base64Data, contentType);
        if (!scanDecision.isClean) {
            return quarantineUpload(onboardingId, documentRequestId, fileName, scanDecision.message);
        }

        ContentVersion version = new ContentVersion(
            Title = removeExtension(fileName),
            PathOnClient = fileName,
            FirstPublishLocationId = onboardingId,
            VersionData = fileBody
        );
        insert version;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboardingId,
            Document_Name__c = fileName,
            Content_Document_Id__c = insertedVersion.ContentDocumentId,
            Document_Type__c = 'Uploaded',
            Status__c = 'Draft',
            Document_Request__c = documentRequestId,
            Uploaded_By__c = UserInfo.getUserId(),
            Upload_Timestamp__c = System.now(),
            OCR_Status__c = 'Pending',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;

        if (documentRequestId != null) {
            update new KT_Document_Request__c(
                Id = documentRequestId,
                Status__c = 'In Progress',
                Document_Vault_Entry__c = vaultEntry.Id
            );
        }

        publishDocumentUploadedEvent(onboardingId, vaultEntry.Id, insertedVersion.ContentDocumentId, vaultEntry.Document_Type__c);

        UploadResult result = new UploadResult();
        result.vaultEntryId = vaultEntry.Id;
        result.contentDocumentId = insertedVersion.ContentDocumentId;
        result.contentVersionId = insertedVersion.Id;
        result.documentRequestId = documentRequestId;
        result.success = true;
        result.message = 'Document uploaded successfully.';
        return result;
    }

    private class ScanDecision {
        Boolean isClean;
        Boolean manualReviewRequired;
        String message;

        ScanDecision(Boolean isClean, Boolean manualReviewRequired, String message) {
            this.isClean = isClean;
            this.manualReviewRequired = manualReviewRequired;
            this.message = message;
        }
    }

    private static ScanDecision performVirusScan(String fileName, String base64Data, String contentType) {
        KT_VirusScanService.ScanResult result = KT_VirusScanService.scanBase64(fileName, base64Data, contentType);
        return new ScanDecision(result.isClean, result.manualReviewRequired, result.message);
    }

    private static UploadResult quarantineUpload(Id onboardingId, Id documentRequestId, String fileName, String message) {
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboardingId,
            Document_Name__c = fileName,
            Document_Type__c = 'Uploaded',
            Status__c = 'Quarantined',
            Document_Request__c = documentRequestId,
            Uploaded_By__c = UserInfo.getUserId(),
            Upload_Timestamp__c = System.now(),
            OCR_Status__c = 'Failed',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required'
        );
        insert vaultEntry;

        if (documentRequestId != null) {
            update new KT_Document_Request__c(
                Id = documentRequestId,
                Status__c = 'Rejected',
                Document_Vault_Entry__c = vaultEntry.Id
            );
        }

        insert new Task(
            Subject = 'Virus scan quarantine: ' + fileName.left(200),
            WhatId = vaultEntry.Id,
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started',
            Priority = 'High'
        );

        UploadResult result = new UploadResult();
        result.vaultEntryId = vaultEntry.Id;
        result.documentRequestId = documentRequestId;
        result.success = false;
        result.message = message;
        return result;
    }

    private static void publishDocumentUploadedEvent(Id onboardingId, Id vaultEntryId, Id contentDocumentId, String documentType) {
        Schema.SObjectType eventType = Schema.getGlobalDescribe().get('KT_Document_Uploaded__e');
        if (eventType == null) {
            return;
        }

        SObject eventRecord = eventType.newSObject();
        Map<String, Schema.SObjectField> eventFields = eventType.getDescribe().fields.getMap();
        if (eventFields.containsKey('ContentDocumentId__c')) {
            eventRecord.put('ContentDocumentId__c', String.valueOf(contentDocumentId));
        }
        if (eventFields.containsKey('OnboardingId__c')) {
            eventRecord.put('OnboardingId__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('KT_Onboarding__c')) {
            eventRecord.put('KT_Onboarding__c', onboardingId);
        }
        if (eventFields.containsKey('Onboarding_Id__c')) {
            eventRecord.put('Onboarding_Id__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('DocumentType__c')) {
            eventRecord.put('DocumentType__c', documentType);
        }
        if (eventFields.containsKey('UploadedBy__c')) {
            eventRecord.put('UploadedBy__c', String.valueOf(UserInfo.getUserId()));
        }
        if (eventFields.containsKey('Timestamp__c')) {
            eventRecord.put('Timestamp__c', System.now());
        }
        if (eventFields.containsKey('VaultId__c')) {
            eventRecord.put('VaultId__c', String.valueOf(vaultEntryId));
        }
        EventBus.publish(eventRecord);
    }

    private static String stripDataUrlPrefix(String value) {
        Integer commaIndex = value.indexOf(',');
        return value.startsWith('data:') && commaIndex > -1 ? value.substring(commaIndex + 1) : value;
    }

    private static String getExtension(String fileName) {
        Integer dotIndex = fileName == null ? -1 : fileName.lastIndexOf('.');
        return dotIndex == -1 ? '' : fileName.substring(dotIndex + 1).toLowerCase();
    }

    private static String removeExtension(String fileName) {
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);
    }
}
