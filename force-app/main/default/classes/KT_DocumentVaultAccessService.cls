public with sharing class KT_DocumentVaultAccessService {
    @TestVisible
    private static final String MANAGER_ROW_CAUSE = 'KT_Manager_Access__c';

    public static void syncManagerShares(List<KT_Onboarding__c> newRecords, Map<Id, KT_Onboarding__c> oldMap) {
        Set<Id> onboardingIds = new Set<Id>();
        for (KT_Onboarding__c onboarding : newRecords) {
            if (onboarding.Id == null) {
                continue;
            }

            KT_Onboarding__c oldRecord = oldMap == null ? null : oldMap.get(onboarding.Id);
            if (oldRecord == null || onboarding.Hiring_Manager__c != oldRecord.Hiring_Manager__c) {
                onboardingIds.add(onboarding.Id);
            }
        }

        syncManagerShares(onboardingIds);
    }

    public static void syncManagerShares(Set<Id> onboardingIds) {
        if (onboardingIds == null || onboardingIds.isEmpty()) {
            return;
        }

        Map<Id, KT_Onboarding__c> onboardingsById = new Map<Id, KT_Onboarding__c>([
            SELECT Id, OwnerId, Hiring_Manager__c
            FROM KT_Onboarding__c
            WHERE Id IN :onboardingIds
        ]);

        Map<Id, Id> desiredManagerByOnboarding = new Map<Id, Id>();
        for (KT_Onboarding__c onboarding : onboardingsById.values()) {
            if (onboarding.Hiring_Manager__c != null && onboarding.Hiring_Manager__c != onboarding.OwnerId) {
                desiredManagerByOnboarding.put(onboarding.Id, onboarding.Hiring_Manager__c);
            }
        }

        String managerRowCause = MANAGER_ROW_CAUSE;
        List<SObject> existingShares = Database.query(
            'SELECT Id, ParentId, UserOrGroupId ' +
            'FROM KT_Onboarding__Share ' +
            'WHERE ParentId IN :onboardingIds ' +
            'AND RowCause = :managerRowCause'
        );

        Set<String> existingDesiredKeys = new Set<String>();
        List<SObject> sharesToDelete = new List<SObject>();
        for (SObject shareRecord : existingShares) {
            Id parentId = (Id) shareRecord.get('ParentId');
            Id sharedToId = (Id) shareRecord.get('UserOrGroupId');
            Id desiredManagerId = desiredManagerByOnboarding.get(parentId);

            if (desiredManagerId == null || desiredManagerId != sharedToId) {
                sharesToDelete.add(shareRecord);
            } else {
                existingDesiredKeys.add(parentId + ':' + sharedToId);
            }
        }

        Schema.SObjectType shareType = Schema.getGlobalDescribe().get('KT_Onboarding__Share');
        List<SObject> sharesToInsert = new List<SObject>();
        for (Id onboardingId : desiredManagerByOnboarding.keySet()) {
            Id managerId = desiredManagerByOnboarding.get(onboardingId);
            String shareKey = onboardingId + ':' + managerId;
            if (existingDesiredKeys.contains(shareKey)) {
                continue;
            }

            SObject shareRecord = shareType.newSObject();
            shareRecord.put('ParentId', onboardingId);
            shareRecord.put('UserOrGroupId', managerId);
            shareRecord.put('AccessLevel', 'Read');
            shareRecord.put('RowCause', managerRowCause);
            sharesToInsert.add(shareRecord);
        }

        if (!sharesToDelete.isEmpty()) {
            Database.delete(sharesToDelete, false);
        }
        if (!sharesToInsert.isEmpty()) {
            Database.insert(sharesToInsert, false);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasCurrentUserVaultAccess(Id onboardingId) {
        if (onboardingId == null) {
            return false;
        }

        List<KT_Onboarding__c> visibleOnboardings = [
            SELECT Id
            FROM KT_Onboarding__c
            WHERE Id = :onboardingId
            LIMIT 1
        ];
        return !visibleOnboardings.isEmpty();
    }
}
