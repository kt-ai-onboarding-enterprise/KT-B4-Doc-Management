public with sharing class KT_DocumentChecklistService {
    private static final String DEFAULT_DIRECTION = 'Outbound';
    private static final List<String> DOMAIN_FIELD_CANDIDATES = new List<String>{
        'Domain_Code__c', 'Domain__c', 'Primary_Domain__c'
    };
    private static final List<String> PERSONA_FIELD_CANDIDATES = new List<String>{
        'Persona_Code__c', 'Persona__c', 'Persona_Type__c'
    };

    public class ChecklistServiceException extends Exception {}

    public class ChecklistResult {
        @InvocableVariable public Id onboardingId;
        @InvocableVariable public Integer createdCount;
        @InvocableVariable public Integer skippedCount;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    public class DocumentRequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String documentDirection;
        @AuraEnabled public String waiverReason;
        @AuraEnabled public Id vaultEntryId;
        @AuraEnabled public Boolean isOverdue;
    }

    private class OnboardingContext {
        Id onboardingId;
        String domainCode;
        String personaCode;
    }

    @InvocableMethod(label='Create KT Document Checklist' description='Creates B4 document request records for onboarding records using KT_Document_Template_Config__mdt.')
    public static List<ChecklistResult> createChecklistForOnboarding(List<Id> onboardingIds) {
        if (onboardingIds == null || onboardingIds.isEmpty()) {
            return new List<ChecklistResult>();
        }

        List<KT_Document_Template_Config__mdt> configs = [
            SELECT DeveloperName, Domain_Code__c, Persona_Code__c, Template_API_Name__c,
                   Is_Required__c, SLA_Days__c, Display_Order__c, Document_Direction__c
            FROM KT_Document_Template_Config__mdt
            ORDER BY Display_Order__c ASC, DeveloperName ASC
        ];
        Map<Id, ChecklistResult> resultsByOnboarding = createRequestsFromConfigsBulk(onboardingIds, configs);

        List<ChecklistResult> results = new List<ChecklistResult>();
        for (Id onboardingId : onboardingIds) {
            results.add(resultsByOnboarding.get(onboardingId));
        }
        return results;
    }

    public static ChecklistResult createChecklist(Id onboardingId) {
        if (onboardingId == null) {
            throw new ChecklistServiceException('onboardingId is required.');
        }

        List<KT_Document_Template_Config__mdt> configs = [
            SELECT DeveloperName, Domain_Code__c, Persona_Code__c, Template_API_Name__c,
                   Is_Required__c, SLA_Days__c, Display_Order__c, Document_Direction__c
            FROM KT_Document_Template_Config__mdt
            ORDER BY Display_Order__c ASC, DeveloperName ASC
        ];
        return createRequestsFromConfigsBulk(new List<Id>{ onboardingId }, configs).get(onboardingId);
    }

    @AuraEnabled(cacheable=true)
    public static List<DocumentRequestRow> getDocumentRequests(Id onboardingId) {
        if (onboardingId == null) {
            return new List<DocumentRequestRow>();
        }

        List<DocumentRequestRow> rows = new List<DocumentRequestRow>();
        for (KT_Document_Request__c request : [
            SELECT Id, Document_Template__c, Document_Template__r.Template_Name__c, Status__c,
                   Is_Required__c, Due_Date__c, Document_Direction__c, Waiver_Reason__c,
                   Document_Vault_Entry__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboardingId
            ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            DocumentRequestRow row = new DocumentRequestRow();
            row.id = request.Id;
            row.templateId = request.Document_Template__c;
            row.templateName = request.Document_Template__r == null
                ? 'Unassigned Document'
                : request.Document_Template__r.Template_Name__c;
            row.status = request.Status__c;
            row.isRequired = request.Is_Required__c;
            row.dueDate = request.Due_Date__c;
            row.documentDirection = request.Document_Direction__c;
            row.waiverReason = request.Waiver_Reason__c;
            row.vaultEntryId = request.Document_Vault_Entry__c;
            row.isOverdue = request.Due_Date__c != null
                && request.Due_Date__c < Date.today()
                && request.Status__c != 'Complete'
                && request.Status__c != 'Waived';
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void markUploadRequested(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('requestId is required.');
        }

        KT_Document_Request__c request = [
            SELECT Id, Status__c
            FROM KT_Document_Request__c
            WHERE Id = :requestId
            LIMIT 1
            FOR UPDATE
        ];
        request.Status__c = 'In Progress';
        update request;
    }

    @AuraEnabled
    public static void waiveDocumentRequest(Id requestId, String waiverReason) {
        if (requestId == null) {
            throw new AuraHandledException('requestId is required.');
        }
        if (String.isBlank(waiverReason)) {
            throw new AuraHandledException('waiverReason is required.');
        }

        KT_Document_Request__c request = [
            SELECT Id, Status__c, Waiver_Reason__c, Completed_Date__c
            FROM KT_Document_Request__c
            WHERE Id = :requestId
            LIMIT 1
            FOR UPDATE
        ];
        request.Status__c = 'Waived';
        request.Waiver_Reason__c = waiverReason.left(255);
        request.Completed_Date__c = System.now();
        update request;
    }

    @TestVisible
    private static ChecklistResult createRequestsFromConfigs(Id onboardingId, List<KT_Document_Template_Config__mdt> configs) {
        if (onboardingId == null) {
            throw new ChecklistServiceException('onboardingId is required.');
        }

        return createRequestsFromConfigsBulk(new List<Id>{ onboardingId }, configs).get(onboardingId);
    }

    @TestVisible
    private static Map<Id, ChecklistResult> createRequestsFromConfigsBulk(
        List<Id> onboardingIds,
        List<KT_Document_Template_Config__mdt> configs
    ) {
        if (onboardingIds == null || onboardingIds.isEmpty()) {
            return new Map<Id, ChecklistResult>();
        }

        List<Id> validOnboardingIds = new List<Id>();
        for (Id onboardingId : onboardingIds) {
            if (onboardingId == null) {
                throw new ChecklistServiceException('onboardingId is required.');
            }
            validOnboardingIds.add(onboardingId);
        }

        List<KT_Document_Template_Config__mdt> effectiveConfigs =
            configs == null ? new List<KT_Document_Template_Config__mdt>() : configs;
        Map<Id, OnboardingContext> contextsById = getOnboardingContexts(validOnboardingIds);
        Map<String, KT_DocumentTemplate__c> templatesByKey = getActiveTemplatesByKey();
        Set<Id> templateIds = new Set<Id>();
        for (KT_DocumentTemplate__c template : templatesByKey.values()) {
            templateIds.add(template.Id);
        }
        Map<Id, Set<Id>> existingTemplateIdsByOnboarding =
            getExistingTemplateIdsByOnboarding(validOnboardingIds, templateIds);

        Map<Id, ChecklistResult> resultsByOnboarding = new Map<Id, ChecklistResult>();
        List<KT_Document_Request__c> requestsToInsert = new List<KT_Document_Request__c>();

        for (Id onboardingId : validOnboardingIds) {
            OnboardingContext context = contextsById.get(onboardingId);
            if (context == null) {
                throw new ChecklistServiceException('Onboarding record not found: ' + onboardingId);
            }

            Set<Id> existingTemplateIds = existingTemplateIdsByOnboarding.containsKey(onboardingId)
                ? existingTemplateIdsByOnboarding.get(onboardingId)
                : new Set<Id>();
            Integer createdCount = 0;
            Integer skippedCount = 0;

            for (KT_Document_Template_Config__mdt config : effectiveConfigs) {
                if (config == null || String.isBlank(config.Template_API_Name__c)) {
                    skippedCount++;
                    continue;
                }
                if (!appliesTo(config.Domain_Code__c, context.domainCode)
                    || !appliesTo(config.Persona_Code__c, context.personaCode)) {
                    skippedCount++;
                    continue;
                }

                KT_DocumentTemplate__c template = templatesByKey.get(config.Template_API_Name__c.trim());
                if (template == null || existingTemplateIds.contains(template.Id)) {
                    skippedCount++;
                    continue;
                }

                requestsToInsert.add(new KT_Document_Request__c(
                    KT_Onboarding__c = onboardingId,
                    Document_Template__c = template.Id,
                    Status__c = 'Not Started',
                    Is_Required__c = config.Is_Required__c,
                    Due_Date__c = Date.today().addDays(config.SLA_Days__c == null ? 0 : config.SLA_Days__c.intValue()),
                    Document_Direction__c = getConfiguredDirection(config),
                    Reminder_Count__c = 0
                ));
                existingTemplateIds.add(template.Id);
                createdCount++;
            }

            ChecklistResult result = new ChecklistResult();
            result.onboardingId = onboardingId;
            result.createdCount = createdCount;
            result.skippedCount = skippedCount;
            result.success = true;
            result.message = 'Document checklist created.';
            resultsByOnboarding.put(onboardingId, result);
        }

        if (!requestsToInsert.isEmpty()) {
            insert requestsToInsert;
        }

        for (ChecklistResult result : resultsByOnboarding.values()) {
            publishDocumentGeneratedEvent(result.onboardingId, result.createdCount);
        }

        return resultsByOnboarding;
    }

    private static Map<String, KT_DocumentTemplate__c> getActiveTemplatesByKey() {
        Map<String, KT_DocumentTemplate__c> templatesByKey = new Map<String, KT_DocumentTemplate__c>();
        for (KT_DocumentTemplate__c template : [
            SELECT Id, Name, Template_Name__c, Is_Active__c
            FROM KT_DocumentTemplate__c
            WHERE Is_Active__c = true
        ]) {
            templatesByKey.put(String.valueOf(template.Id), template);
            templatesByKey.put(template.Name, template);
            if (!String.isBlank(template.Template_Name__c)) {
                templatesByKey.put(template.Template_Name__c, template);
            }
        }
        return templatesByKey;
    }

    private static OnboardingContext getOnboardingContext(Id onboardingId) {
        Map<Id, OnboardingContext> contextsById = getOnboardingContexts(new List<Id>{ onboardingId });
        if (!contextsById.containsKey(onboardingId)) {
            throw new ChecklistServiceException('Onboarding record not found: ' + onboardingId);
        }
        return contextsById.get(onboardingId);
    }

    private static Map<Id, OnboardingContext> getOnboardingContexts(List<Id> onboardingIds) {
        Map<String, Schema.SObjectField> onboardingFields =
            Schema.getGlobalDescribe().get('KT_Onboarding__c').getDescribe().fields.getMap();

        List<String> selectedFields = new List<String>{ 'Id' };
        String domainField = firstExistingField(onboardingFields, DOMAIN_FIELD_CANDIDATES);
        String personaField = firstExistingField(onboardingFields, PERSONA_FIELD_CANDIDATES);
        if (domainField != null) {
            selectedFields.add(domainField);
        }
        if (personaField != null && personaField != domainField) {
            selectedFields.add(personaField);
        }

        String query = 'SELECT ' + String.join(selectedFields, ',')
            + ' FROM KT_Onboarding__c WHERE Id IN :onboardingIds';
        Map<Id, OnboardingContext> contextsById = new Map<Id, OnboardingContext>();
        for (SObject onboardingRecord : Database.query(query)) {
            OnboardingContext context = new OnboardingContext();
            context.onboardingId = (Id) onboardingRecord.get('Id');
            context.domainCode = domainField == null ? null : asString(onboardingRecord.get(domainField));
            context.personaCode = personaField == null ? null : asString(onboardingRecord.get(personaField));
            contextsById.put(context.onboardingId, context);
        }
        return contextsById;
    }

    private static Map<Id, Set<Id>> getExistingTemplateIdsByOnboarding(List<Id> onboardingIds, Set<Id> templateIds) {
        Map<Id, Set<Id>> existingTemplateIdsByOnboarding = new Map<Id, Set<Id>>();
        for (Id onboardingId : onboardingIds) {
            existingTemplateIdsByOnboarding.put(onboardingId, new Set<Id>());
        }
        if (templateIds == null || templateIds.isEmpty()) {
            return existingTemplateIdsByOnboarding;
        }

        for (KT_Document_Request__c existingRequest : [
            SELECT KT_Onboarding__c, Document_Template__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c IN :onboardingIds
            AND Document_Template__c IN :templateIds
        ]) {
            existingTemplateIdsByOnboarding.get(existingRequest.KT_Onboarding__c)
                .add(existingRequest.Document_Template__c);
        }
        return existingTemplateIdsByOnboarding;
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

    @TestVisible
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

    private static String getConfiguredDirection(SObject config) {
        Schema.SObjectType configType = Schema.getGlobalDescribe().get('KT_Document_Template_Config__mdt');
        if (configType != null
            && configType.getDescribe().fields.getMap().containsKey('Document_Direction__c')) {
            Object direction = config.get('Document_Direction__c');
            if (direction != null && !String.isBlank(String.valueOf(direction))) {
                return String.valueOf(direction);
            }
        }
        return DEFAULT_DIRECTION;
    }

    private static void publishDocumentGeneratedEvent(Id onboardingId, Integer createdCount) {
        Schema.SObjectType eventType = Schema.getGlobalDescribe().get('KT_Document_Generated__e');
        if (eventType == null) {
            return;
        }

        SObject eventRecord = eventType.newSObject();
        Map<String, Schema.SObjectField> eventFields = eventType.getDescribe().fields.getMap();
        if (eventFields.containsKey('KT_Onboarding__c')) {
            eventRecord.put('KT_Onboarding__c', onboardingId);
        }
        if (eventFields.containsKey('OnboardingId__c')) {
            eventRecord.put('OnboardingId__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('Onboarding_Id__c')) {
            eventRecord.put('Onboarding_Id__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('Timestamp__c')) {
            eventRecord.put('Timestamp__c', System.now());
        }
        if (eventFields.containsKey('Generated_Count__c')) {
            eventRecord.put('Generated_Count__c', createdCount);
        }
        EventBus.publish(eventRecord);
    }
}
