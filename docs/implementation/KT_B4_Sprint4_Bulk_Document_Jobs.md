# KT B4 Sprint 4 - Bulk Document Job Service

## Design Coverage

`B4-T039 Build KT_BulkDocumentJobService.cls - validateCohort(), getBulkJobStatus() @AuraEnabled methods`

## Implementation

`KT_BulkDocumentJobService` supports B4 bulk document generation and monitoring.

The bulk job feature includes:

- `validateCohort()` checks selected onboarding records before launch.
- `launchBulkJob()` creates and starts a tracked batch job.
- `getBulkJobStatus()` returns progress and recent job state for UI and Agentforce use.
- `KT_BulkDocumentBatch` and `KT_BulkDocumentQueueable` perform the generation and post-processing work.
- `KT_Bulk_Document_Job__c` stores counts, status, failure summaries, and Apex job linkage.

## Deployment Evidence

Deploy ID: `0Afg5000008KGTqCAO`

Focused test command:

```powershell
sf.cmd force apex test run --tests KT_BulkDocumentBatchTest --resultformat human --codecoverage --synchronous
```

Result:

- 7 of 7 tests passed.
- Pass rate: 100%.
- `KT_BulkDocumentJobService` coverage: 95%.
- `KT_BulkDocumentBatch` coverage: 92%.
- `KT_BulkDocumentQueueable` coverage: 91%.
