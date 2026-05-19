# KT B4 End-to-End Functional Test

- Date: 2026-05-18
- Org: `ckumarnc.305960ebf72a@agentforce.com`
- Script: `scripts/apex/KT_B4_EndToEnd_Functional_Test.apex`
- Status: Passed

## Command

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_EndToEnd_Functional_Test.apex
```

## Final Run Summary

The final run executed successfully and produced this evidence summary:

- Onboarding: `a05g5000006xrObAAI`
- Template: `a01g500000NCOnkAAH`
- Document request: `a03g500000Gw99pAAB`
- Vault document: `a02g5000007zZRSAA2`
- Invalid CLM transition blocked: `true`
- CLM task count: `3`
- OCR job: `a04g5000001HZ7FAAW`
- OCR complete platform event published: `true`
- HR Copilot OCR discrepancy count: `1`
- HR Copilot checklist gap count: `1`
- Bulk job: `a00g500000SlWNoAAN`
- HR Copilot bulk status: `Running`
- HR Copilot bulk progress: `40.0`
- Signature request: `a07g500000OrO5CAAV`
- AXL tile channel: `Teams`
- AXL tile signing URL generated: `true`
- HR Copilot signing pending count: `1`
- Trusted Agent Identity blocked final signature before verification: `true`
- Trusted Agent Identity status after verification: `Verified`
- KT Sign workflow completed: `true`
- Compliance expiring document count: `1`
- Compliance missing document count after completion: `0`
- Audit export vault: `a02g5000007zZRTAA2`
- Audit export content document: `069g5000004eX9TAAU`
- Audit export hash present: `true`
- Signature audit count: `5`

## Coverage

This functional smoke covers:

- Onboarding creation and automatic checklist generation.
- Document template and request setup.
- File creation and vault indexing.
- Contract lifecycle status guardrails and ordered CLM transitions.
- OCR review evidence and `KT_OCR_Job_Complete__e` publish.
- HR Copilot Agentforce actions for OCR, checklist gaps, bulk job status, and signing escalation.
- Bulk document job status fields as a functional user through `KT_Admin`.
- AXL signing tile generation for Teams.
- Trusted Agent Identity gate for HIPAA high-value signing.
- KT Sign workflow completion.
- Compliance Auditor actions for expiring and missing documents.
- Certified audit export generation.

## Notes

Before the final pass, `KT_Admin` was updated to include field permissions for `KT_Bulk_Document_Job__c` operational fields. Without those permissions, a functional user could not run the bulk job status branch even though the automated Apex tests passed in system context.

For fuller demo data, use `docs/uat/KT_B4_Rich_EndToEnd_Functional_Test.md`. That run populates more fields across template, request, vault, OCR, bulk, signing, provider evidence, compliance, and audit export records.
