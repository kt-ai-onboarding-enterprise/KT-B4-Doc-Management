# KT B4 Sprint 6 UAT

- Date: 2026-05-14
- Org: `ckumarnc.305960ebf72a@agentforce.com`
- Scope: OCR, CLM lifecycle, DocuSign, Adobe Sign, and audit export

## Status

Completed for automatable org smoke and automated regression coverage.

Live outbound calls to DocuSign, Adobe Sign, AWS Textract, and Azure Form Recognizer still require admin-owned Named Credential secrets in the target org before real provider UAT can be signed off.

## Automated Regression Evidence

- Test run id: `707g500000OGnl2`
- Result: `63 / 63` focused Sprint 6 tests passed
- Covered areas:
  - OCR ingestion, upload pipeline, polling, retries, and callbacks
  - DocuSign service and webhook handling
  - Adobe Sign service and webhook handling
  - CLM contract lifecycle
  - Audit export

## Live Org Smoke Script

Run:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_Sprint6_UAT_Smoke.apex
```

The smoke script creates:

- One onboarding record
- One contract vault entry linked to a Salesforce File
- One invalid CLM transition check
- Ordered CLM transitions through legal review, counter-sign, and fully executed
- One OCR review-required job
- One DocuSign signature request with signer and audit evidence
- One Adobe Sign signed request with signer and audit evidence
- One certified audit export PDF stored in the vault

Execution result on May 14, 2026:

- Onboarding id: `a05g5000006kwFFAAY`
- Contract vault id: `a02g5000007rsnpAAA`
- Invalid CLM transition blocked: `true`
- CLM task count: `3`
- OCR job id: `a04g5000001GDWzAAO`
- DocuSign signature request id: `a07g500000OH6zhAAD`
- Adobe Sign signature request id: `a07g500000OH6ziAAD`
- Audit export vault id: `a02g5000007rsnqAAA`
- Audit export content document id: `069g5000004Vll8AAC`
- Audit export evidence counts: 1 document, 2 signature audit events, 1 OCR job

## Scenario Matrix

| Scenario | Evidence | Status |
| --- | --- | --- |
| OCR job evidence and review state | `KT_Ocr*Test` classes plus UAT smoke `KT_OCR_Job__c` row | Pass |
| OCR callback security and provider parsing | `KT_OcrCallbackHandlerTest` | Pass |
| CLM invalid status jump blocked | UAT smoke `invalidClmTransitionBlocked = true` | Pass |
| CLM ordered transition tasks | UAT smoke task count plus `KT_CLMContractLifecycleServiceTest` | Pass |
| DocuSign create/send/status/document retrieval logic | `KT_DocuSignEnvelopeServiceTest` with HTTP mocks | Pass |
| DocuSign webhook event handling | `KT_DocuSignWebhookHandlerTest` | Pass |
| Adobe Sign create/send/status/document retrieval logic | `KT_AdobeSignServiceTest` with HTTP mocks | Pass |
| Adobe Sign webhook verification and events | `KT_AdobeSignWebhookHandlerTest` | Pass |
| Audit export evidence PDF | UAT smoke audit export plus `KT_AuditExportServiceTest` | Pass |

## Manual Provider UAT

After Named Credentials are configured with real credentials:

1. Create or open an onboarding record.
2. Generate or upload a document into the vault.
3. Create a DocuSign signature request and send the envelope.
4. Confirm the DocuSign webhook updates signer, signature request, vault, and audit records.
5. Create an Adobe Sign signature request and send the agreement.
6. Confirm Adobe Sign verification and event callbacks update signer, signature request, vault, and audit records.
7. Generate the audit export and confirm it includes vault, signature, OCR, and audit evidence.
