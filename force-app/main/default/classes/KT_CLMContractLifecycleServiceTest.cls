@IsTest
private class KT_CLMContractLifecycleServiceTest {
    private static KT_DocumentVault__c createContractVault() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Employment Contract',
            Document_Type__c = 'Contract',
            Status__c = 'Draft',
            OCR_Status__c = 'Not Required',
            Signature_Status__c = 'Not Required',
            Version_Number__c = 1
        );
        insert vault;
        return vault;
    }

    @IsTest
    static void lifecycleActionCreatesLegalReviewTask() {
        KT_DocumentVault__c vault = createContractVault();
        vault.Status__c = 'Legal Review';
        update vault;

        KT_CLMContractLifecycleService.LifecycleRequest request =
            new KT_CLMContractLifecycleService.LifecycleRequest();
        request.recordId = vault.Id;

        Test.startTest();
        List<KT_CLMContractLifecycleService.LifecycleResult> results =
            KT_CLMContractLifecycleService.runLifecycle(
                new List<KT_CLMContractLifecycleService.LifecycleRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].processed);
        System.assert([
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :vault.KT_Onboarding__c
            AND Subject LIKE 'CLM legal review:%'
        ] >= 1);
    }

    @IsTest
    static void triggerBlocksCounterSignBeforeLegalReview() {
        KT_DocumentVault__c vault = createContractVault();
        vault.Status__c = 'Counter-Sign';

        Database.SaveResult result = Database.update(vault, false);

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('Draft, Legal Review, Counter-Sign'));
    }

    @IsTest
    static void triggerAllowsOrderedContractLifecycle() {
        KT_DocumentVault__c vault = createContractVault();

        vault.Status__c = 'Legal Review';
        update vault;
        vault.Status__c = 'Counter-Sign';
        update vault;
        vault.Status__c = 'Fully Executed';
        update vault;
        vault.Status__c = 'Archived';
        update vault;

        System.assertEquals('Archived', [
            SELECT Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vault.Id
        ].Status__c);
        System.assertEquals(4, [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :vault.KT_Onboarding__c
            AND Subject LIKE 'CLM%'
        ]);
    }

    @IsTest
    static void lifecycleActionSkipsNonContractVault() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;

        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Passport',
            Document_Type__c = 'Uploaded',
            Status__c = 'Draft',
            OCR_Status__c = 'Not Required',
            Signature_Status__c = 'Not Required',
            Version_Number__c = 1
        );
        insert vault;

        KT_CLMContractLifecycleService.LifecycleRequest request =
            new KT_CLMContractLifecycleService.LifecycleRequest();
        request.recordId = vault.Id;

        List<KT_CLMContractLifecycleService.LifecycleResult> results =
            KT_CLMContractLifecycleService.runLifecycle(
                new List<KT_CLMContractLifecycleService.LifecycleRequest>{ request }
            );

        System.assertEquals(false, results[0].processed);
        System.assert(results[0].message.contains('not a contract'));
    }
}
