@IsTest
private class KT_DocumentChecklistServiceTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static KT_DocumentTemplate__c createTemplate(String name, Boolean active) {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = name,
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = '{"{{Id}}":"Id"}',
            Requires_Signature__c = false,
            Is_Active__c = active,
            Version__c = 1,
            Language__c = 'English'
        );
        insert template;
        return template;
    }

    private static KT_Document_Template_Config__mdt config(String templateKey, String domain, String persona, Boolean required, Integer slaDays) {
        return new KT_Document_Template_Config__mdt(
            Domain_Code__c = domain,
            Persona_Code__c = persona,
            Template_API_Name__c = templateKey,
            Is_Required__c = required,
            SLA_Days__c = slaDays,
            Display_Order__c = 1
        );
    }

    @IsTest
    static void createRequestsFromConfigsCreatesMatchingChecklistItems() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate('Offer Letter', true);
        createTemplate('Inactive Template', false);

        Test.startTest();
        KT_DocumentChecklistService.ChecklistResult result =
            KT_DocumentChecklistService.createRequestsFromConfigs(
                onboarding.Id,
                new List<KT_Document_Template_Config__mdt>{
                    config('Offer Letter', 'ALL', 'ALL', true, 5),
                    config('Inactive Template', 'ALL', 'ALL', true, 5),
                    config('Missing Template', 'ALL', 'ALL', true, 5),
                    config('Offer Letter', 'ALL', 'ALL', true, 5),
                    config(null, 'ALL', 'ALL', true, 5)
                }
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(1, result.createdCount);
        System.assertEquals(4, result.skippedCount);

        KT_Document_Request__c request = [
            SELECT KT_Onboarding__c, Document_Template__c, Status__c, Is_Required__c,
                   Due_Date__c, Document_Direction__c, Reminder_Count__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboarding.Id
            LIMIT 1
        ];
        System.assertEquals(onboarding.Id, request.KT_Onboarding__c);
        System.assertEquals(template.Id, request.Document_Template__c);
        System.assertEquals('Not Started', request.Status__c);
        System.assertEquals(true, request.Is_Required__c);
        System.assertEquals(Date.today().addDays(5), request.Due_Date__c);
        System.assertEquals('Outbound', request.Document_Direction__c);
        System.assertEquals(0, request.Reminder_Count__c.intValue());
    }

    @IsTest
    static void createRequestsSkipsExistingAndNonMatchingConfigRows() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate('Existing Template', true);
        insert new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Outbound',
            Is_Required__c = true
        );

        Test.startTest();
        KT_DocumentChecklistService.ChecklistResult result =
            KT_DocumentChecklistService.createRequestsFromConfigs(
                onboarding.Id,
                new List<KT_Document_Template_Config__mdt>{
                    config('Existing Template', 'ALL', 'ALL', true, 5),
                    config('Existing Template', 'Finance', 'ALL', true, 5)
                }
            );
        Test.stopTest();

        System.assertEquals(0, result.createdCount);
        System.assertEquals(2, result.skippedCount);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboarding.Id
        ]);
    }

    @IsTest
    static void createChecklistForOnboardingHandlesNoMetadataRecords() {
        KT_Onboarding__c onboarding = createOnboarding();

        Test.startTest();
        List<KT_DocumentChecklistService.ChecklistResult> results =
            KT_DocumentChecklistService.createChecklistForOnboarding(new List<Id>{ onboarding.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0].createdCount);
        System.assertEquals(true, results[0].success);
    }

    @IsTest
    static void createRequestsFromConfigsBulkHandlesFiftyOnboardings() {
        List<KT_Onboarding__c> onboardings = new List<KT_Onboarding__c>();
        for (Integer index = 0; index < 50; index++) {
            onboardings.add(new KT_Onboarding__c());
        }
        insert onboardings;

        List<Id> onboardingIds = new List<Id>();
        for (KT_Onboarding__c onboarding : onboardings) {
            onboardingIds.add(onboarding.Id);
        }

        KT_DocumentTemplate__c template = createTemplate('Bulk Checklist Template', true);

        Test.startTest();
        Map<Id, KT_DocumentChecklistService.ChecklistResult> resultsByOnboarding =
            KT_DocumentChecklistService.createRequestsFromConfigsBulk(
                onboardingIds,
                new List<KT_Document_Template_Config__mdt>{
                    config('Bulk Checklist Template', 'ALL', 'ALL', true, 3)
                }
            );
        Test.stopTest();

        System.assertEquals(50, resultsByOnboarding.size());
        for (Id onboardingId : onboardingIds) {
            System.assertEquals(1, resultsByOnboarding.get(onboardingId).createdCount);
            System.assertEquals(0, resultsByOnboarding.get(onboardingId).skippedCount);
        }
        System.assertEquals(50, [
            SELECT COUNT()
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c IN :onboardingIds
            AND Document_Template__c = :template.Id
        ]);
    }

    @IsTest
    static void documentRequestListActionsReturnRowsAndUpdateStatus() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate('Portal Upload', true);
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true,
            Due_Date__c = Date.today().addDays(-1)
        );
        insert request;

        Test.startTest();
        List<KT_DocumentChecklistService.DocumentRequestRow> rows =
            KT_DocumentChecklistService.getDocumentRequests(onboarding.Id);
        KT_DocumentChecklistService.markUploadRequested(request.Id);
        KT_DocumentChecklistService.waiveDocumentRequest(request.Id, 'Manager approved waiver');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(template.Id, rows[0].templateId);
        System.assertEquals('Portal Upload', rows[0].templateName);
        System.assertEquals(true, rows[0].isOverdue);

        KT_Document_Request__c updated = [
            SELECT Status__c, Waiver_Reason__c, Completed_Date__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('Waived', updated.Status__c);
        System.assertEquals('Manager approved waiver', updated.Waiver_Reason__c);
        System.assertNotEquals(null, updated.Completed_Date__c);
    }

    @IsTest
    static void appliesToSupportsAllBlankCommaAndMissingRequestedValue() {
        System.assertEquals(true, KT_DocumentChecklistService.appliesTo(null, 'Healthcare'));
        System.assertEquals(true, KT_DocumentChecklistService.appliesTo('ALL', null));
        System.assertEquals(true, KT_DocumentChecklistService.appliesTo('Finance, Healthcare', 'HEALTHCARE'));
        System.assertEquals(false, KT_DocumentChecklistService.appliesTo('Finance', 'Healthcare'));
        System.assertEquals(false, KT_DocumentChecklistService.appliesTo('Finance', null));
    }

    @IsTest
    static void rejectsMissingRequiredInputAndEmptyInvocableInput() {
        Test.startTest();
        List<KT_DocumentChecklistService.ChecklistResult> emptyResults =
            KT_DocumentChecklistService.createChecklistForOnboarding(new List<Id>());
        Test.stopTest();
        System.assertEquals(0, emptyResults.size());

        try {
            KT_DocumentChecklistService.createChecklist(null);
            System.assert(false, 'Expected missing onboarding id to fail.');
        } catch (KT_DocumentChecklistService.ChecklistServiceException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentChecklistService.createRequestsFromConfigs(null, new List<KT_Document_Template_Config__mdt>());
            System.assert(false, 'Expected missing onboarding id to fail.');
        } catch (KT_DocumentChecklistService.ChecklistServiceException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
