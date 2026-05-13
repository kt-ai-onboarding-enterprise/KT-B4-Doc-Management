public with sharing class KT_BulkDocumentJobService {
    private static final Integer MAX_COHORT_SIZE = 10000;

    public class CohortValidationRow {
        @AuraEnabled public Id onboardingId;
        @AuraEnabled public Boolean valid;
        @AuraEnabled public List<String> unresolvedTokens;
        @AuraEnabled public String message;
    }

    public class BulkJobStatusRow {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String jobName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer processed;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public String apexJobId;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime completedAt;
        @AuraEnabled public Datetime estimatedCompletionAt;
        @AuraEnabled public Boolean complete;
        @AuraEnabled public String failureSummary;
    }

    public class BulkJobLaunchResult {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String apexJobId;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=false)
    public static List<CohortValidationRow> validateCohort(List<Id> onboardingIds, Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }
        if (onboardingIds == null || onboardingIds.isEmpty()) {
            return new List<CohortValidationRow>();
        }
        if (onboardingIds.size() > MAX_COHORT_SIZE) {
            throw new AuraHandledException('Bulk jobs support up to 10,000 onboarding records.');
        }

        List<CohortValidationRow> rows = new List<CohortValidationRow>();
        for (Id onboardingId : onboardingIds) {
            Map<String, String> previewData = KT_DocumentGeneratorService.getPreviewData(templateId, onboardingId);
            List<String> unresolvedTokens = new List<String>();
            for (String token : previewData.keySet()) {
                if (previewData.get(token) == token) {
                    unresolvedTokens.add(token);
                }
            }

            CohortValidationRow row = new CohortValidationRow();
            row.onboardingId = onboardingId;
            row.valid = unresolvedTokens.isEmpty();
            row.unresolvedTokens = unresolvedTokens;
            row.message = row.valid
                ? 'Merge validation passed.'
                : 'Missing merge data for ' + String.join(unresolvedTokens, ', ') + '.';
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static BulkJobStatusRow getBulkJobStatus(Id jobId) {
        if (jobId == null) {
            throw new AuraHandledException('jobId is required.');
        }

        KT_Bulk_Document_Job__c jobRecord = [
            SELECT Id, Job_Name__c, Status__c, Total_Records__c, Processed__c, Success_Count__c,
                   Failure_Count__c, Apex_Job_Id__c, Started_At__c, Completed_At__c, Failure_Summary__c
            FROM KT_Bulk_Document_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        return toStatusRow(jobRecord);
    }

    @AuraEnabled(cacheable=true)
    public static List<BulkJobStatusRow> getRecentBulkJobs(Integer maxResults) {
        Integer queryLimit = maxResults == null ? 10 : Math.max(1, Math.min(maxResults, 25));
        List<BulkJobStatusRow> rows = new List<BulkJobStatusRow>();
        for (KT_Bulk_Document_Job__c jobRecord : [
            SELECT Id, Job_Name__c, Status__c, Total_Records__c, Processed__c, Success_Count__c,
                   Failure_Count__c, Apex_Job_Id__c, Started_At__c, Completed_At__c, Failure_Summary__c
            FROM KT_Bulk_Document_Job__c
            ORDER BY Started_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :queryLimit
        ]) {
            rows.add(toStatusRow(jobRecord));
        }
        return rows;
    }

    @AuraEnabled
    public static BulkJobLaunchResult launchBulkJob(
        List<Id> onboardingIds,
        Id templateId,
        String jobName,
        String signatureConfigJson
    ) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }
        if (onboardingIds == null || onboardingIds.isEmpty()) {
            throw new AuraHandledException('At least one onboarding id is required.');
        }
        if (onboardingIds.size() > MAX_COHORT_SIZE) {
            throw new AuraHandledException('Bulk jobs support up to 10,000 onboarding records.');
        }

        KT_Bulk_Document_Job__c jobRecord = new KT_Bulk_Document_Job__c(
            Job_Name__c = String.isBlank(jobName) ? 'Bulk Document Job' : jobName,
            Template__c = templateId,
            Total_Records__c = onboardingIds.size(),
            Processed__c = 0,
            Success_Count__c = 0,
            Failure_Count__c = 0,
            Failure_Summary__c = null,
            Status__c = 'Queued',
            Initiated_By__c = UserInfo.getUserId(),
            Started_At__c = System.now()
        );
        insert jobRecord;

        String batchJobId = Database.executeBatch(
            new KT_BulkDocumentBatch(jobRecord.Id, new Set<Id>(onboardingIds), templateId, signatureConfigJson),
            KT_BulkDocumentBatch.BATCH_SIZE
        );

        update new KT_Bulk_Document_Job__c(
            Id = jobRecord.Id,
            Apex_Job_Id__c = batchJobId
        );

        BulkJobLaunchResult result = new BulkJobLaunchResult();
        result.jobId = jobRecord.Id;
        result.apexJobId = batchJobId;
        result.status = 'Queued';
        return result;
    }

    private static Integer toInteger(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static BulkJobStatusRow toStatusRow(KT_Bulk_Document_Job__c jobRecord) {
        BulkJobStatusRow row = new BulkJobStatusRow();
        row.jobId = jobRecord.Id;
        row.jobName = jobRecord.Job_Name__c;
        row.status = jobRecord.Status__c;
        row.totalRecords = toInteger(jobRecord.Total_Records__c);
        row.processed = toInteger(jobRecord.Processed__c);
        row.successCount = toInteger(jobRecord.Success_Count__c);
        row.failureCount = toInteger(jobRecord.Failure_Count__c);
        row.apexJobId = jobRecord.Apex_Job_Id__c;
        row.startedAt = jobRecord.Started_At__c;
        row.completedAt = jobRecord.Completed_At__c;
        row.progressPercent = row.totalRecords == 0
            ? 0
            : (Decimal.valueOf(row.processed) / Decimal.valueOf(row.totalRecords)) * 100;
        row.complete = jobRecord.Status__c == 'Complete'
            || jobRecord.Status__c == 'Partially Complete'
            || jobRecord.Status__c == 'Failed';
        row.failureSummary = jobRecord.Failure_Summary__c;
        row.estimatedCompletionAt = calculateEstimatedCompletion(jobRecord.Started_At__c, jobRecord.Completed_At__c, row.processed, row.totalRecords, row.complete);
        return row;
    }

    private static Datetime calculateEstimatedCompletion(
        Datetime startedAt,
        Datetime completedAt,
        Integer processed,
        Integer totalRecords,
        Boolean complete
    ) {
        if (complete) {
            return completedAt;
        }
        if (startedAt == null || processed == null || totalRecords == null || processed <= 0 || totalRecords <= processed) {
            return null;
        }

        Long elapsedMs = System.now().getTime() - startedAt.getTime();
        if (elapsedMs <= 0) {
            return null;
        }

        Decimal averageMsPerRecord = Decimal.valueOf(elapsedMs) / Decimal.valueOf(processed);
        Integer remainingRecords = totalRecords - processed;
        Long remainingMs = (averageMsPerRecord * remainingRecords).longValue();
        return System.now().addSeconds(Math.max(1, Integer.valueOf(remainingMs / 1000)));
    }
}
