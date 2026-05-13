public with sharing class KT_OcrUploadPipelineService {
    private static final Set<String> TERMINAL_OR_ACTIVE_STATUSES = new Set<String>{
        'Submitted',
        'Processing',
        'Review Required',
        'Accepted'
    };
    private static final List<String> DOMAIN_FIELD_CANDIDATES = new List<String>{
        'Domain_Code__c', 'Domain__c', 'Primary_Domain__c'
    };
    private static final List<String> PERSONA_FIELD_CANDIDATES = new List<String>{
        'Persona_Code__c', 'Persona__c', 'Persona_Type__c'
    };
    @TestVisible private static Boolean executeSubmission = true;
    @TestVisible private static List<KT_Document_Template_Config__mdt> templateConfigOverrides;

    public class UploadPipelineRequest {
        @InvocableVariable public String vaultId;
        @InvocableVariable public String contentDocumentId;
        @InvocableVariable public String onboardingId;
        @InvocableVariable public String documentType;
        @InvocableVariable public String uploadedBy;
    }

    public class UploadPipelineResult {
        @InvocableVariable public String ocrJobId;
        @InvocableVariable public Boolean processed;
        @InvocableVariable public Boolean ocrRequired;
        @InvocableVariable public String status;
        @InvocableVariable public String provider;
        @InvocableVariable public String message;
    }

    private class OnboardingContext {
        String domainCode;
        String personaCode;
    }

    @InvocableMethod(
        label='Run KT OCR Upload Pipeline'
        description='Routes uploaded documents into the OCR ingestion pipeline when the matching template configuration requires OCR.'
    )
    public static List<UploadPipelineResult> runUploadPipeline(List<UploadPipelineRequest> requests) {
        List<UploadPipelineResult> results = new List<UploadPipelineResult>();
        if (requests == null) {
            return results;
        }

        for (UploadPipelineRequest request : requests) {
            UploadPipelineResult result = new UploadPipelineResult();
            result.processed = false;
            result.ocrRequired = false;
            result.status = 'Skipped';
            result.message = 'No action performed.';

            try {
                if (request == null || String.isBlank(request.onboardingId)) {
                    result.message = 'onboardingId is required.';
                    results.add(result);
                    continue;
                }

                KT_DocumentVault__c vaultEntry = loadVaultEntry(request);
                if (vaultEntry == null) {
                    result.message = 'No matching document vault entry was found for the upload event.';
                    results.add(result);
                    continue;
                }

                KT_OCR_Job__c existingJob = findExistingJob(vaultEntry.Id);
                if (existingJob != null) {
                    result.ocrJobId = existingJob.Id;
                    result.ocrRequired = true;
                    result.status = existingJob.Status__c;
                    result.message = 'An OCR job already exists for this vault entry.';
                    results.add(result);
                    continue;
                }

                OCRDecision decision = evaluateOcrRequirement(vaultEntry);
                result.ocrRequired = decision.requiresOcr;
                if (!decision.requiresOcr) {
                    result.message = decision.message;
                    results.add(result);
                    continue;
                }

                update new KT_DocumentVault__c(
                    Id = vaultEntry.Id,
                    OCR_Status__c = 'Pending'
                );

                KT_OCR_Job__c ocrJob = new KT_OCR_Job__c(
                    KT_DocumentVault__c = vaultEntry.Id,
                    KT_Onboarding__c = vaultEntry.KT_Onboarding__c,
                    Status__c = 'Submitted'
                );
                insert ocrJob;

                result.ocrJobId = ocrJob.Id;
                result.processed = true;
                if (executeSubmission) {
                    KT_OcrIngestionService.SubmitJobResult submitResult = KT_OcrIngestionService.submitJob(ocrJob.Id);
                    result.status = submitResult == null ? 'Submitted' : submitResult.status;
                    result.provider = submitResult == null ? null : submitResult.provider;
                    result.message = submitResult == null
                        ? 'OCR job created and submitted.'
                        : submitResult.message;
                } else {
                    result.status = 'Submitted';
                    result.message = 'OCR job created and queued for submission.';
                }
            } catch (Exception ex) {
                result.status = 'Failed';
                result.message = ex.getMessage();
            }
            results.add(result);
        }
        return results;
    }

    private class OCRDecision {
        Boolean requiresOcr;
        String message;

        OCRDecision(Boolean requiresOcr, String message) {
            this.requiresOcr = requiresOcr;
            this.message = message;
        }
    }

    private static KT_DocumentVault__c loadVaultEntry(UploadPipelineRequest request) {
        Id vaultRecordId = toId(request == null ? null : request.vaultId);
        if (vaultRecordId != null) {
            List<KT_DocumentVault__c> byId = [
                SELECT Id, KT_Onboarding__c, Content_Document_Id__c, Document_Request__c,
                       Document_Request__r.Document_Template__c,
                       Document_Request__r.Document_Template__r.Name,
                       Document_Request__r.Document_Template__r.Template_Name__c
                FROM KT_DocumentVault__c
                WHERE Id = :vaultRecordId
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }

        String contentDocumentId = request == null ? null : request.contentDocumentId;
        Id onboardingId = toId(request == null ? null : request.onboardingId);
        if (String.isBlank(contentDocumentId) || onboardingId == null) {
            return null;
        }

        List<KT_DocumentVault__c> vaultEntries = [
            SELECT Id, KT_Onboarding__c, Content_Document_Id__c, Document_Request__c,
                   Document_Request__r.Document_Template__c,
                   Document_Request__r.Document_Template__r.Name,
                   Document_Request__r.Document_Template__r.Template_Name__c
            FROM KT_DocumentVault__c
            WHERE Content_Document_Id__c = :contentDocumentId
            AND KT_Onboarding__c = :onboardingId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return vaultEntries.isEmpty() ? null : vaultEntries[0];
    }

    private static KT_OCR_Job__c findExistingJob(Id vaultEntryId) {
        if (vaultEntryId == null) {
            return null;
        }

        List<KT_OCR_Job__c> jobs = [
            SELECT Id, Status__c
            FROM KT_OCR_Job__c
            WHERE KT_DocumentVault__c = :vaultEntryId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            return null;
        }
        return TERMINAL_OR_ACTIVE_STATUSES.contains(jobs[0].Status__c) ? jobs[0] : null;
    }

    private static OCRDecision evaluateOcrRequirement(KT_DocumentVault__c vaultEntry) {
        if (vaultEntry == null || vaultEntry.Document_Request__r == null || vaultEntry.Document_Request__r.Document_Template__c == null) {
            return new OCRDecision(false, 'The uploaded document is not linked to a document request template configuration.');
        }

        OnboardingContext context = getOnboardingContext(vaultEntry.KT_Onboarding__c);
        Set<String> templateKeys = new Set<String>{
            String.valueOf(vaultEntry.Document_Request__r.Document_Template__c)
        };
        if (vaultEntry.Document_Request__r.Document_Template__r != null) {
            if (!String.isBlank(vaultEntry.Document_Request__r.Document_Template__r.Name)) {
                templateKeys.add(vaultEntry.Document_Request__r.Document_Template__r.Name);
            }
            if (!String.isBlank(vaultEntry.Document_Request__r.Document_Template__r.Template_Name__c)) {
                templateKeys.add(vaultEntry.Document_Request__r.Document_Template__r.Template_Name__c);
            }
        }

        for (KT_Document_Template_Config__mdt config : getTemplateConfigs(templateKeys)) {
            if (!appliesTo(config.Domain_Code__c, context.domainCode)
                || !appliesTo(config.Persona_Code__c, context.personaCode)) {
                continue;
            }
            if (config.Requires_OCR__c) {
                return new OCRDecision(true, 'Document upload matched a template configuration that requires OCR.');
            }
            return new OCRDecision(false, 'Document upload matched a template configuration that does not require OCR.');
        }

        return new OCRDecision(false, 'No template configuration requiring OCR matched the uploaded document.');
    }

    private static List<KT_Document_Template_Config__mdt> getTemplateConfigs(Set<String> templateKeys) {
        if (templateKeys == null || templateKeys.isEmpty()) {
            return new List<KT_Document_Template_Config__mdt>();
        }
        if (templateConfigOverrides != null) {
            List<KT_Document_Template_Config__mdt> filteredOverrides = new List<KT_Document_Template_Config__mdt>();
            for (KT_Document_Template_Config__mdt config : templateConfigOverrides) {
                if (config != null && templateKeys.contains(config.Template_API_Name__c)) {
                    filteredOverrides.add(config);
                }
            }
            return filteredOverrides;
        }

        return [
            SELECT DeveloperName, Domain_Code__c, Persona_Code__c, Template_API_Name__c, Requires_OCR__c
            FROM KT_Document_Template_Config__mdt
            WHERE Template_API_Name__c IN :templateKeys
            ORDER BY Display_Order__c ASC, DeveloperName ASC
        ];
    }

    private static OnboardingContext getOnboardingContext(Id onboardingId) {
        if (onboardingId == null) {
            return new OnboardingContext();
        }

        Map<String, Schema.SObjectField> onboardingFields = KT_Onboarding__c.SObjectType.getDescribe().fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id' };
        String domainField = firstExistingField(onboardingFields, DOMAIN_FIELD_CANDIDATES);
        String personaField = firstExistingField(onboardingFields, PERSONA_FIELD_CANDIDATES);
        if (domainField != null) {
            selectedFields.add(domainField);
        }
        if (personaField != null && personaField != domainField) {
            selectedFields.add(personaField);
        }

        SObject onboardingRecord = Database.query(
            'SELECT ' + String.join(selectedFields, ',')
            + ' FROM KT_Onboarding__c WHERE Id = :onboardingId LIMIT 1'
        );
        OnboardingContext context = new OnboardingContext();
        context.domainCode = domainField == null ? null : asString(onboardingRecord.get(domainField));
        context.personaCode = personaField == null ? null : asString(onboardingRecord.get(personaField));
        return context;
    }

    private static Boolean appliesTo(String configuredValues, String requestedValue) {
        if (String.isBlank(configuredValues) || configuredValues.trim().toLowerCase() == 'all') {
            return true;
        }
        if (String.isBlank(requestedValue)) {
            return false;
        }

        String normalizedRequestedValue = requestedValue.trim().toLowerCase();
        for (String configuredValue : configuredValues.split(',')) {
            String normalizedConfiguredValue = configuredValue.trim().toLowerCase();
            if (normalizedConfiguredValue == normalizedRequestedValue || normalizedConfiguredValue == 'all') {
                return true;
            }
        }
        return false;
    }

    private static String firstExistingField(Map<String, Schema.SObjectField> fieldMap, List<String> candidates) {
        for (String candidate : candidates) {
            if (fieldMap.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }
}
