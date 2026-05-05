@IsTest
private class KT_DocumentTemplateServiceTest {
    private static KT_DocumentTemplate__c createTemplate(String name, String domains, String personas, Boolean active) {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = name,
            Output_Format__c = 'PDF',
            Domain__c = domains,
            Persona__c = personas,
            Merge_Field_Map__c = '{"{{Id}}":"Id"}',
            Requires_Signature__c = false,
            Is_Active__c = active,
            Version__c = 1,
            Language__c = 'English'
        );
        insert template;
        return template;
    }

    @IsTest
    static void getActiveTemplatesFiltersByDomainAndPersona() {
        createTemplate('Healthcare Employee', 'Healthcare,Manufacturing', 'NewEmployee', true);
        createTemplate('Universal', null, null, true);
        createTemplate('Inactive', 'Healthcare', 'NewEmployee', false);
        createTemplate('Finance Contractor', 'Finance', 'Contractor', true);

        Test.startTest();
        List<KT_DocumentTemplate__c> templates =
            KT_DocumentTemplateService.getActiveTemplates('Healthcare', 'NewEmployee');
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (KT_DocumentTemplate__c template : templates) {
            names.add(template.Template_Name__c);
            System.assertEquals(true, template.Is_Active__c);
        }
        System.assertEquals(true, names.contains('Healthcare Employee'));
        System.assertEquals(true, names.contains('Universal'));
        System.assertEquals(false, names.contains('Inactive'));
        System.assertEquals(false, names.contains('Finance Contractor'));
    }

    @IsTest
    static void getTemplateIncrementAndDeactivateWork() {
        KT_DocumentTemplate__c template = createTemplate('Versioned', 'ALL', 'ALL', true);

        Test.startTest();
        KT_DocumentTemplate__c fetched = KT_DocumentTemplateService.getTemplateById(template.Id);
        KT_DocumentTemplate__c incremented = KT_DocumentTemplateService.incrementVersion(template.Id);
        KT_DocumentTemplate__c deactivated = KT_DocumentTemplateService.deactivateTemplate(template.Id);
        Test.stopTest();

        System.assertEquals('Versioned', fetched.Template_Name__c);
        System.assertEquals(2, incremented.Version__c);
        System.assertEquals(false, deactivated.Is_Active__c);
    }

    @IsTest
    static void resolveDIETemplatesHandlesNoConfiguredMetadata() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        Test.startTest();
        List<KT_DocumentTemplate__c> templates = KT_DocumentTemplateService.resolveDIETemplates(onboarding.Id);
        Test.stopTest();

        System.assertEquals(0, templates.size());
    }

    @IsTest
    static void resolveTemplatesByKeysMatchesIdNameAndTemplateNameInOrder() {
        KT_DocumentTemplate__c first = createTemplate('Template Name Key', 'Healthcare', 'NewEmployee', true);
        KT_DocumentTemplate__c second = createTemplate('Second Template', 'Healthcare', 'NewEmployee', true);
        KT_DocumentTemplate__c inactive = createTemplate('Inactive Key', 'Healthcare', 'NewEmployee', false);

        Test.startTest();
        List<KT_DocumentTemplate__c> templates = KT_DocumentTemplateService.resolveTemplatesByKeys(
            new List<String>{
                '',
                first.Template_Name__c,
                String.valueOf(second.Id),
                inactive.Template_Name__c,
                first.Template_Name__c
            }
        );
        Test.stopTest();

        System.assertEquals(2, templates.size());
        System.assertEquals(first.Id, templates[0].Id);
        System.assertEquals(second.Id, templates[1].Id);
    }

    @IsTest
    static void appliesToHandlesAllBlankAndCommaSeparatedValues() {
        System.assertEquals(true, KT_DocumentTemplateService.appliesTo(null, 'Healthcare'));
        System.assertEquals(true, KT_DocumentTemplateService.appliesTo('ALL', null));
        System.assertEquals(true, KT_DocumentTemplateService.appliesTo('Finance, Healthcare', 'healthcare'));
        System.assertEquals(false, KT_DocumentTemplateService.appliesTo('Finance', 'Healthcare'));
        System.assertEquals(false, KT_DocumentTemplateService.appliesTo('Finance', null));
    }

    @IsTest
    static void rejectsMissingRequiredInputs() {
        try {
            KT_DocumentTemplateService.getTemplateById(null);
            System.assert(false, 'Expected missing template id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentTemplateService.resolveDIETemplates(null);
            System.assert(false, 'Expected missing onboarding id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
