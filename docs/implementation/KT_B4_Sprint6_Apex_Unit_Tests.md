# KT B4 Sprint 6 - Apex Unit Tests

## Tracker Task

`B4-T048 Sprint 6 Apex Unit Tests - OCR, DocuSign, Adobe Sign`

## Status

Completed.

## Test Run

Command:

```powershell
sf.cmd force apex test run --testlevel RunSpecifiedTests --classnames KT_OcrIngestionServiceTest,KT_OcrUploadPipelineServiceTest,KT_OcrPollingBatchTest,KT_OcrCallbackHandlerTest,KT_DocuSignEnvelopeServiceTest,KT_DocuSignWebhookHandlerTest,KT_AdobeSignServiceTest,KT_AdobeSignWebhookHandlerTest,KT_CLMContractLifecycleServiceTest,KT_AuditExportServiceTest --resultformat human --codecoverage --wait 20
```

Result on May 14, 2026:

- Test run id: `707g500000OGnl2`
- Outcome: Passed
- Tests ran: 63
- Pass rate: 100%
- Fail rate: 0%
- Org-wide coverage after run: 52%

## Covered Areas

- OCR ingestion, upload pipeline, async polling, retry failure handling, and REST callbacks.
- DocuSign envelope creation, send, status refresh, completed document retrieval, and webhook events.
- Adobe Sign agreement creation, send, status refresh, completed document retrieval, and webhook verification/events.
- CLM lifecycle transition enforcement and legal review task creation.
- Audit export PDF/vault evidence generation.

## Fix Applied

`KT_OcrPollingBatchTest` now creates the `KT_HR_Queue` queue and `QueueSobject` in `@TestSetup`, keeping setup-object DML separate from onboarding/vault/OCR business records in each test method.

