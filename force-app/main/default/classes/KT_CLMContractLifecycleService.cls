public with sharing class KT_CLMContractLifecycleService {
    private static final Set<String> CONTRACT_TERMINAL_STATUSES = new Set<String>{ 'Archived' };
    private static final Map<String, Set<String>> ALLOWED_PREVIOUS_STATUSES = new Map<String, Set<String>>{
        'Legal Review' => new Set<String>{ 'Draft' },
        'Counter-Sign' => new Set<String>{ 'Legal Review' },
        'Fully Executed' => new Set<String>{ 'Counter-Sign', 'Signed' },
        'Archived' => new Set<String>{ 'Fully Executed' }
    };
    private static final List<String> DOMAIN_FIELD_CANDIDATES = new List<String>{
        'Domain_Code__c', 'Domain__c', 'Primary_Domain__c'
    };

    public class LifecycleRequest {
        @InvocableVariable(required=true) public Id recordId;
    }

    public class LifecycleResult {
        @InvocableVariable public Id recordId;
        @InvocableVariable public Boolean processed;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Run KT CLM Contract Lifecycle'
        description='Creates CLM review, counter-signature, execution, and archive tasks for contract vault lifecycle transitions.'
    )
    public static List<LifecycleResult> runLifecycle(List<LifecycleRequest> requests) {
        List<LifecycleResult> results = new List<LifecycleResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> vaultIds = new Set<Id>();
        for (LifecycleRequest request : requests) {
            if (request != null && request.recordId != null) {
                vaultIds.add(request.recordId);
            }
        }

        Map<Id, KT_DocumentVault__c> vaultsById = new Map<Id, KT_DocumentVault__c>();
        if (!vaultIds.isEmpty()) {
            vaultsById = new Map<Id, KT_DocumentVault__c>([
                SELECT Id, KT_Onboarding__c, KT_Onboarding__r.OwnerId, KT_Onboarding__r.Hiring_Manager__c,
                       Document_Name__c, Document_Type__c, Status__c, Signature_Status__c
                FROM KT_DocumentVault__c
                WHERE Id IN :vaultIds
            ]);
        }

        List<Task> tasksToInsert = new List<Task>();
        for (LifecycleRequest request : requests) {
            LifecycleResult result = new LifecycleResult();
            result.recordId = request == null ? null : request.recordId;
            result.processed = false;
            result.message = 'No lifecycle action performed.';

            KT_DocumentVault__c vault = result.recordId == null ? null : vaultsById.get(result.recordId);
            if (vault == null) {
                result.message = 'Vault entry was not found.';
            } else if (vault.Document_Type__c != 'Contract') {
                result.message = 'Vault entry is not a contract.';
            } else {
                Task task = buildLifecycleTask(vault);
                if (task == null) {
                    result.message = 'Contract status does not require a lifecycle task.';
                } else {
                    tasksToInsert.add(task);
                    result.processed = true;
                    result.message = 'Contract lifecycle task queued.';
                }
            }
            results.add(result);
        }

        tasksToInsert = removeExistingTasks(tasksToInsert);
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
        return results;
    }

    public static void validateTransitions(List<KT_DocumentVault__c> newRecords, Map<Id, KT_DocumentVault__c> oldRecordsById) {
        if (newRecords == null || oldRecordsById == null) {
            return;
        }

        for (KT_DocumentVault__c newRecord : newRecords) {
            KT_DocumentVault__c oldRecord = oldRecordsById.get(newRecord.Id);
            if (oldRecord == null || newRecord.Document_Type__c != 'Contract' || newRecord.Status__c == oldRecord.Status__c) {
                continue;
            }

            if (CONTRACT_TERMINAL_STATUSES.contains(oldRecord.Status__c)) {
                newRecord.addError('Archived contracts cannot move to another CLM status.');
                continue;
            }

            if (!ALLOWED_PREVIOUS_STATUSES.containsKey(newRecord.Status__c)) {
                continue;
            }

            Set<String> allowedPrevious = ALLOWED_PREVIOUS_STATUSES.get(newRecord.Status__c);
            if (!allowedPrevious.contains(oldRecord.Status__c)) {
                newRecord.addError(
                    'Contract status must move through Draft, Legal Review, Counter-Sign, Fully Executed, and Archived in order.'
                );
            }
        }
    }

    public static void createTransitionTasks(List<KT_DocumentVault__c> newRecords, Map<Id, KT_DocumentVault__c> oldRecordsById) {
        if (newRecords == null || oldRecordsById == null) {
            return;
        }

        Set<Id> changedContractIds = new Set<Id>();
        for (KT_DocumentVault__c newRecord : newRecords) {
            KT_DocumentVault__c oldRecord = oldRecordsById.get(newRecord.Id);
            if (oldRecord != null
                && newRecord.Document_Type__c == 'Contract'
                && newRecord.Status__c != oldRecord.Status__c) {
                changedContractIds.add(newRecord.Id);
            }
        }

        if (changedContractIds.isEmpty()) {
            return;
        }

        List<LifecycleRequest> requests = new List<LifecycleRequest>();
        for (Id vaultId : changedContractIds) {
            LifecycleRequest request = new LifecycleRequest();
            request.recordId = vaultId;
            requests.add(request);
        }
        runLifecycle(requests);
    }

    private static Task buildLifecycleTask(KT_DocumentVault__c vault) {
        String documentName = String.isBlank(vault.Document_Name__c) ? 'Contract' : vault.Document_Name__c;
        Id ownerId = resolveTaskOwner(vault);
        Id whatId = vault.KT_Onboarding__c == null ? vault.Id : vault.KT_Onboarding__c;

        if (vault.Status__c == 'Legal Review') {
            return taskFor(
                whatId,
                ownerId,
                'CLM legal review: ' + documentName,
                'Review contract terms and move the vault entry to Counter-Sign only after legal review is complete.',
                'High'
            );
        }
        if (vault.Status__c == 'Counter-Sign') {
            return taskFor(
                whatId,
                ownerId,
                'CLM counter-signature required: ' + documentName,
                'Dispatch the counter-signature package for the contract and monitor signature completion.',
                'High'
            );
        }
        if (vault.Status__c == 'Fully Executed') {
            return taskFor(
                whatId,
                ownerId,
                'CLM fully executed: ' + documentName,
                'Confirm final contract evidence, version history, and audit readiness before archival.',
                'Normal'
            );
        }
        if (vault.Status__c == 'Archived') {
            return taskFor(
                whatId,
                ownerId,
                'CLM archived: ' + documentName,
                'Contract lifecycle is archived. Retain the vault entry and audit evidence per policy.',
                'Normal'
            );
        }
        return null;
    }

    private static Task taskFor(Id whatId, Id ownerId, String subject, String description, String priority) {
        return new Task(
            WhatId = whatId,
            OwnerId = ownerId == null ? UserInfo.getUserId() : ownerId,
            Subject = subject.left(255),
            Description = description,
            ActivityDate = Date.today(),
            Priority = priority,
            Status = 'Not Started'
        );
    }

    private static List<Task> removeExistingTasks(List<Task> candidateTasks) {
        if (candidateTasks == null || candidateTasks.isEmpty()) {
            return new List<Task>();
        }

        Set<Id> whatIds = new Set<Id>();
        Set<String> subjects = new Set<String>();
        for (Task candidate : candidateTasks) {
            if (candidate.WhatId != null && !String.isBlank(candidate.Subject)) {
                whatIds.add(candidate.WhatId);
                subjects.add(candidate.Subject);
            }
        }
        if (whatIds.isEmpty() || subjects.isEmpty()) {
            return candidateTasks;
        }

        Set<String> existingKeys = new Set<String>();
        for (Task existingTask : [
            SELECT WhatId, Subject
            FROM Task
            WHERE WhatId IN :whatIds
            AND Subject IN :subjects
            AND ActivityDate = :Date.today()
        ]) {
            existingKeys.add(taskKey(existingTask.WhatId, existingTask.Subject));
        }

        List<Task> tasksToInsert = new List<Task>();
        Set<String> queuedKeys = new Set<String>();
        for (Task candidate : candidateTasks) {
            String key = taskKey(candidate.WhatId, candidate.Subject);
            if (!existingKeys.contains(key) && !queuedKeys.contains(key)) {
                tasksToInsert.add(candidate);
                queuedKeys.add(key);
            }
        }
        return tasksToInsert;
    }

    private static String taskKey(Id whatId, String subject) {
        return String.valueOf(whatId) + '|' + subject;
    }

    private static Id resolveTaskOwner(KT_DocumentVault__c vault) {
        Id configuredApprover = resolveConfiguredApprover(vault);
        if (configuredApprover != null) {
            return configuredApprover;
        }
        if (vault.KT_Onboarding__r != null && vault.KT_Onboarding__r.Hiring_Manager__c != null) {
            return vault.KT_Onboarding__r.Hiring_Manager__c;
        }
        if (vault.KT_Onboarding__r != null && vault.KT_Onboarding__r.OwnerId != null) {
            return vault.KT_Onboarding__r.OwnerId;
        }
        return UserInfo.getUserId();
    }

    private static Id resolveConfiguredApprover(KT_DocumentVault__c vault) {
        String domainCode = resolveOnboardingDomain(vault.KT_Onboarding__c);
        List<KT_CLM_Approver_Config__mdt> configs = [
            SELECT Domain_Code__c, Owner_Queue_DeveloperName__c
            FROM KT_CLM_Approver_Config__mdt
            WHERE Is_Active__c = true
            ORDER BY Domain_Code__c ASC, DeveloperName ASC
        ];

        Set<String> queueDeveloperNames = new Set<String>();
        for (KT_CLM_Approver_Config__mdt config : configs) {
            if (appliesToDomain(config.Domain_Code__c, domainCode)
                && !String.isBlank(config.Owner_Queue_DeveloperName__c)) {
                queueDeveloperNames.add(config.Owner_Queue_DeveloperName__c.trim());
            }
        }
        if (queueDeveloperNames.isEmpty()) {
            return null;
        }

        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName IN :queueDeveloperNames
            AND Id IN (SELECT QueueId FROM QueueSobject WHERE SObjectType = 'Task')
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    private static String resolveOnboardingDomain(Id onboardingId) {
        if (onboardingId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> onboardingFields =
            Schema.getGlobalDescribe().get('KT_Onboarding__c').getDescribe().fields.getMap();
        String domainField = firstExistingField(onboardingFields, DOMAIN_FIELD_CANDIDATES);
        if (domainField == null) {
            return null;
        }

        String query = 'SELECT ' + domainField + ' FROM KT_Onboarding__c WHERE Id = :onboardingId LIMIT 1';
        SObject onboarding = Database.query(query);
        Object value = onboarding.get(domainField);
        return value == null ? null : String.valueOf(value);
    }

    private static String firstExistingField(Map<String, Schema.SObjectField> fieldMap, List<String> candidates) {
        for (String candidate : candidates) {
            if (fieldMap.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private static Boolean appliesToDomain(String configuredDomain, String actualDomain) {
        if (String.isBlank(configuredDomain) || configuredDomain.trim().toLowerCase() == 'all') {
            return true;
        }
        if (String.isBlank(actualDomain)) {
            return false;
        }
        String normalizedActual = actualDomain.trim().toLowerCase();
        for (String configuredValue : configuredDomain.split(',')) {
            String normalizedConfigured = configuredValue.trim().toLowerCase();
            if (normalizedConfigured == normalizedActual || normalizedConfigured == 'all') {
                return true;
            }
        }
        return false;
    }
}
