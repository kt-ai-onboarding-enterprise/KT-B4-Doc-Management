trigger KT_OnboardingDocumentAccessTrigger on KT_Onboarding__c (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        KT_DocumentVaultAccessService.syncManagerShares(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }
}
