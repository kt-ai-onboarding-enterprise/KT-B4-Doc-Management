public with sharing class KT_BulkDocumentQueueable implements Queueable {
    private static final Integer MAX_FAILURE_SUMMARY_LENGTH = 131072;

    private final Id jobId;
    private final Integer processedDelta;
    private final Integer successDelta;
    private final Integer failureDelta;
    private final Boolean finalizeJob;
    private final String failureDetails;

    public KT_BulkDocumentQueueable(
        Id jobId,
        Integer processedDelta,
        Integer successDelta,
        Integer failureDelta,
        Boolean finalizeJob,
        String failureDetails
    ) {
        this.jobId = jobId;
        this.processedDelta = processedDelta == null ? 0 : processedDelta;
        this.successDelta = successDelta == null ? 0 : successDelta;
        this.failureDelta = failureDelta == null ? 0 : failureDelta;
        this.finalizeJob = finalizeJob;
        this.failureDetails = String.isBlank(failureDetails) ? null : failureDetails;
    }

    public void execute(QueueableContext context) {
        KT_Bulk_Document_Job__c jobRecord = [
            SELECT Id, Job_Name__c, Status__c, Processed__c, Success_Count__c, Failure_Count__c,
                   Total_Records__c, Started_At__c, Completed_At__c, Initiated_By__c, Failure_Summary__c
            FROM KT_Bulk_Document_Job__c
            WHERE Id = :jobId
            LIMIT 1
            FOR UPDATE
        ];

        jobRecord.Processed__c = numberValue(jobRecord.Processed__c) + processedDelta;
        jobRecord.Success_Count__c = numberValue(jobRecord.Success_Count__c) + successDelta;
        jobRecord.Failure_Count__c = numberValue(jobRecord.Failure_Count__c) + failureDelta;
        jobRecord.Failure_Summary__c = appendFailureSummary(jobRecord.Failure_Summary__c, failureDetails);

        if (jobRecord.Started_At__c == null) {
            jobRecord.Started_At__c = System.now();
        }
        if (!finalizeJob) {
            jobRecord.Status__c = 'Running';
        } else {
            jobRecord.Completed_At__c = System.now();
            jobRecord.Status__c = resolveFinalStatus(jobRecord.Success_Count__c, jobRecord.Failure_Count__c);
        }
        update jobRecord;

        if (finalizeJob) {
            createCompletionTask(jobRecord);
        }
    }

    private static String appendFailureSummary(String existingSummary, String summaryDelta) {
        if (String.isBlank(summaryDelta)) {
            return existingSummary;
        }

        String combined = String.isBlank(existingSummary)
            ? summaryDelta
            : existingSummary + '\n' + summaryDelta;
        if (combined.length() <= MAX_FAILURE_SUMMARY_LENGTH) {
            return combined;
        }
        return combined.left(MAX_FAILURE_SUMMARY_LENGTH);
    }

    private static Integer numberValue(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static String resolveFinalStatus(Decimal successCount, Decimal failureCount) {
        Integer successes = numberValue(successCount);
        Integer failures = numberValue(failureCount);
        if (failures == 0) {
            return 'Complete';
        }
        if (successes == 0) {
            return 'Failed';
        }
        return 'Partially Complete';
    }

    private static void createCompletionTask(KT_Bulk_Document_Job__c jobRecord) {
        if (jobRecord == null || jobRecord.Initiated_By__c == null) {
            return;
        }

        insert new Task(
            OwnerId = jobRecord.Initiated_By__c,
            WhatId = jobRecord.Id,
            Subject = ('Bulk document job complete: ' + jobRecord.Job_Name__c).left(255),
            Description =
                'KT bulk processing finished with status ' + jobRecord.Status__c
                + '. Successes: ' + String.valueOf(jobRecord.Success_Count__c)
                + '. Failures: ' + String.valueOf(jobRecord.Failure_Count__c) + '.',
            ActivityDate = Date.today(),
            Priority = jobRecord.Status__c == 'Complete' ? 'Normal' : 'High',
            Status = 'Not Started'
        );
    }
}
