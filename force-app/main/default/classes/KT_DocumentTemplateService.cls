public with sharing class KT_DocumentTemplateService {
    private static final List<String> DOMAIN_FIELD_CANDIDATES = new List<String>{
        'Domain_Code__c', 'Domain__c', 'Primary_Domain__c'
    };
    private static final List<String> PERSONA_FIELD_CANDIDATES = new List<String>{
        'Persona_Code__c', 'Persona__c', 'Persona_Type__c'
    };

    public class TemplateServiceException extends Exception {}

    public class OnboardingTemplateContext {
        public String domainCode;
        public String personaCode;
    }

    @AuraEnabled(cacheable=true)
    public static List<KT_DocumentTemplate__c> getActiveTemplates(String domain, String persona) {
        List<KT_DocumentTemplate__c> templates = [
            SELECT Id, Name, Template_Name__c, Template_Binary__c, Output_Format__c, Domain__c, Persona__c,
                   Merge_Field_Map__c, Requires_Signature__c, Signer_Roles__c, Signature_Expiry_Days__c,
                   Is_Active__c, Regulatory_Framework__c, Version__c, Language__c
            FROM KT_DocumentTemplate__c
            WHERE Is_Active__c = true
            ORDER BY Template_Name__c ASC
        ];

        List<KT_DocumentTemplate__c> matches = new List<KT_DocumentTemplate__c>();
        for (KT_DocumentTemplate__c template : templates) {
            if (appliesTo(template.Domain__c, domain) && appliesTo(template.Persona__c, persona)) {
                matches.add(template);
            }
        }
        return matches;
    }

    @AuraEnabled(cacheable=true)
    public static KT_DocumentTemplate__c getTemplateById(Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }

        return [
            SELECT Id, Name, Template_Name__c, Template_Binary__c, Output_Format__c, Domain__c, Persona__c,
                   Merge_Field_Map__c, Requires_Signature__c, Signer_Roles__c, Signature_Expiry_Days__c,
                   Is_Active__c, Regulatory_Framework__c, Version__c, Language__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static KT_DocumentTemplate__c incrementVersion(Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }

        KT_DocumentTemplate__c template = [
            SELECT Id, Version__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
            FOR UPDATE
        ];
        Decimal currentVersion = template.Version__c == null ? 0 : template.Version__c;
        template.Version__c = currentVersion + 1;
        update template;
        return getTemplateById(template.Id);
    }

    @AuraEnabled
    public static KT_DocumentTemplate__c deactivateTemplate(Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }

        KT_DocumentTemplate__c template = [
            SELECT Id, Is_Active__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
            FOR UPDATE
        ];
        template.Is_Active__c = false;
        update template;
        return getTemplateById(template.Id);
    }

    @AuraEnabled(cacheable=true)
    public static List<KT_DocumentTemplate__c> resolveDIETemplates(Id onboardingId) {
        if (onboardingId == null) {
            throw new AuraHandledException('onboardingId is required.');
        }

        OnboardingTemplateContext context = getOnboardingContext(onboardingId);
        List<KT_Document_Template_Config__mdt> configs = [
            SELECT DeveloperName, Domain_Code__c, Persona_Code__c, Template_API_Name__c,
                   Is_Required__c, SLA_Days__c, Display_Order__c
            FROM KT_Document_Template_Config__mdt
            ORDER BY Display_Order__c ASC, DeveloperName ASC
        ];

        List<String> templateKeys = new List<String>();
        for (KT_Document_Template_Config__mdt config : configs) {
            if (appliesTo(config.Domain_Code__c, context.domainCode)
                && appliesTo(config.Persona_Code__c, context.personaCode)
                && !String.isBlank(config.Template_API_Name__c)) {
                templateKeys.add(config.Template_API_Name__c.trim());
            }
        }
        return resolveTemplatesByKeys(templateKeys);
    }

    @TestVisible
    private static List<KT_DocumentTemplate__c> resolveTemplatesByKeys(List<String> templateKeys) {
        if (templateKeys.isEmpty()) {
            return new List<KT_DocumentTemplate__c>();
        }

        Set<String> keySet = new Set<String>();
        Set<Id> idSet = new Set<Id>();
        for (String key : templateKeys) {
            if (String.isBlank(key)) {
                continue;
            }
            keySet.add(key);
            try {
                idSet.add((Id) key);
            } catch (Exception ignored) {
                // Non-Id keys are matched against Name and Template_Name__c below.
            }
        }

        List<KT_DocumentTemplate__c> candidates = [
            SELECT Id, Name, Template_Name__c, Template_Binary__c, Output_Format__c, Domain__c, Persona__c,
                   Merge_Field_Map__c, Requires_Signature__c, Signer_Roles__c, Signature_Expiry_Days__c,
                   Is_Active__c, Regulatory_Framework__c, Version__c, Language__c
            FROM KT_DocumentTemplate__c
            WHERE Is_Active__c = true
            AND (Id IN :idSet OR Name IN :keySet OR Template_Name__c IN :keySet)
        ];

        Map<String, KT_DocumentTemplate__c> byKey = new Map<String, KT_DocumentTemplate__c>();
        for (KT_DocumentTemplate__c template : candidates) {
            byKey.put(String.valueOf(template.Id), template);
            byKey.put(template.Name, template);
            if (!String.isBlank(template.Template_Name__c)) {
                byKey.put(template.Template_Name__c, template);
            }
        }

        List<KT_DocumentTemplate__c> ordered = new List<KT_DocumentTemplate__c>();
        Set<Id> addedIds = new Set<Id>();
        for (String key : templateKeys) {
            KT_DocumentTemplate__c template = byKey.get(key);
            if (template != null && !addedIds.contains(template.Id)) {
                ordered.add(template);
                addedIds.add(template.Id);
            }
        }
        return ordered;
    }

    private static OnboardingTemplateContext getOnboardingContext(Id onboardingId) {
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
            + ' FROM KT_Onboarding__c WHERE Id = :onboardingId LIMIT 1';
        SObject onboardingRecord = Database.query(query);

        OnboardingTemplateContext context = new OnboardingTemplateContext();
        context.domainCode = domainField == null ? null : asString(onboardingRecord.get(domainField));
        context.personaCode = personaField == null ? null : asString(onboardingRecord.get(personaField));
        return context;
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
        if (String.isBlank(configuredValues)) {
            return true;
        }
        if (configuredValues.trim().toLowerCase() == 'all') {
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
}
