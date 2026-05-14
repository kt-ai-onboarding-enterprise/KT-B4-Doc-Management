trigger KT_DocumentVaultLifecycleTrigger on KT_DocumentVault__c (before update, after update) {
    if (Trigger.isBefore) {
        KT_CLMContractLifecycleService.validateTransitions(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        KT_CLMContractLifecycleService.createTransitionTasks(Trigger.new, Trigger.oldMap);
    }
}
