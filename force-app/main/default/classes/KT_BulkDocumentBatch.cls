public with sharing class KT_BulkDocumentBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public static final Integer BATCH_SIZE = 25;

    private final Id jobId;
    private final Id templateId;
    private final Set<Id> onboardingIds;
    private final String signatureConfigJson;

    public class BulkDocumentException extends Exception {}

    public KT_BulkDocumentBatch(Id jobId, Set<Id> onboardingIds, Id templateId, String signatureConfigJson) {
        this.jobId = jobId;
        this.onboardingIds = onboardingIds == null ? new Set<Id>() : new Set<Id>(onboardingIds);
        this.templateId = templateId;
        this.signatureConfigJson = signatureConfigJson;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (jobId == null) {
            throw new BulkDocumentException('jobId is required.');
        }
        if (templateId == null) {
            throw new BulkDocumentException('templateId is required.');
        }
        if (onboardingIds.isEmpty()) {
            throw new BulkDocumentException('At least one onboarding id is required.');
        }

        return Database.getQueryLocator([
            SELECT Id
            FROM KT_Onboarding__c
            WHERE Id IN :onboardingIds
            ORDER BY Id ASC
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        KT_DocumentTemplate__c template = [
            SELECT Id, Requires_Signature__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
        ];
        KT_ESignatureOrchestrator.SignatureConfig signatureConfig = deserializeSignatureConfig(signatureConfigJson);

        Integer successCount = 0;
        Integer failureCount = 0;
        List<String> failureDetails = new List<String>();
        for (SObject scopeRecord : scope) {
            KT_Onboarding__c onboarding = (KT_Onboarding__c) scopeRecord;
            try {
                KT_DocumentGeneratorService.KT_DocGenResult generationResult =
                    KT_DocumentGeneratorService.generateDocument(onboarding.Id, template.Id);

                if (template.Requires_Signature__c) {
                    if (signatureConfig == null || signatureConfig.signers == null || signatureConfig.signers.isEmpty()) {
                        throw new BulkDocumentException('Signature configuration is required for signature-enabled templates.');
                    }
                    KT_ESignatureOrchestrator.initiateSigningWorkflow(
                        generationResult.vaultEntryId,
                        cloneSignatureConfig(signatureConfig)
                    );
                }
                successCount++;
            } catch (Exception generationException) {
                failureCount++;
                failureDetails.add(buildFailureDetail(onboarding.Id, generationException));
            }
        }

        System.enqueueJob(
            new KT_BulkDocumentQueueable(
                jobId,
                scope.size(),
                successCount,
                failureCount,
                false,
                failureDetails.isEmpty() ? null : String.join(failureDetails, '\n')
            )
        );
    }

    public void finish(Database.BatchableContext context) {
        System.enqueueJob(new KT_BulkDocumentQueueable(jobId, 0, 0, 0, true, null));
    }

    private static String buildFailureDetail(Id onboardingId, Exception generationException) {
        String message = generationException == null ? 'Unknown error.' : generationException.getMessage();
        if (String.isBlank(message)) {
            message = 'Unknown error.';
        }
        return 'Onboarding ' + String.valueOf(onboardingId) + ': ' + message;
    }

    private static KT_ESignatureOrchestrator.SignatureConfig deserializeSignatureConfig(String rawJson) {
        if (String.isBlank(rawJson)) {
            return null;
        }
        return (KT_ESignatureOrchestrator.SignatureConfig) JSON.deserialize(
            rawJson,
            KT_ESignatureOrchestrator.SignatureConfig.class
        );
    }

    private static KT_ESignatureOrchestrator.SignatureConfig cloneSignatureConfig(
        KT_ESignatureOrchestrator.SignatureConfig signatureConfig
    ) {
        if (signatureConfig == null) {
            return null;
        }
        return (KT_ESignatureOrchestrator.SignatureConfig) JSON.deserialize(
            JSON.serialize(signatureConfig),
            KT_ESignatureOrchestrator.SignatureConfig.class
        );
    }
}
