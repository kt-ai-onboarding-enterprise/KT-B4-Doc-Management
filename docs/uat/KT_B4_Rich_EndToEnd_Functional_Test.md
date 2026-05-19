# KT B4 Rich End-to-End Functional Test

- Date: 2026-05-18
- Org: `ckumarnc.305960ebf72a@agentforce.com`
- Script: `scripts/apex/KT_B4_Rich_EndToEnd_Functional_Test.apex`
- Status: Passed

## Purpose

This run creates demo-grade B4 records with fuller field data than the minimal smoke test. It populates the accessible business fields on the main B4 records and then validates the end-to-end functions.

## Command

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_Rich_EndToEnd_Functional_Test.apex
```

## Rich Demo Record Set

- Onboarding: `a05g5000006yCHNAA2`
- Template: `a01g500000NCyWEAA1`
- Document request: `a03g500000GwuBtAAJ`
- Primary vault document: `a02g5000007znNxAAI`
- OCR job: `a04g5000001HZIXAA4`
- Bulk document job: `a00g500000SmHclAAF`
- KT Sign signature request: `a07g500000OrTewAAF`
- DocuSign evidence signature request: `a07g500000OrTexAAF`
- Adobe Sign evidence signature request: `a07g500000OrTeyAAF`
- Audit export vault: `a02g5000007znNyAAI`
- Audit export content document: `069g5000004eZpdAAE`

## Populated Data Highlights

- Template includes domain, persona, language, output format, active flag, signature flag, expiry days, signer roles, regulatory framework, template binary file id, version, and merge map JSON.
- Document request includes onboarding link, status, direction, and required flag.
- Vault includes onboarding, document name, content document id, document type, request link, OCR status, signature status, version, expiry date, regulatory tags, uploader, and upload timestamp.
- OCR job includes provider, provider job id, document type, low confidence score, retry count, and structured extracted JSON.
- Bulk job includes template, partial-complete status, total, processed, success, failure, failure summary, Apex job id, initiator, start, and completion timestamps.
- Signing includes two KT Sign signers, Slack and Teams AXL tile generation, Trusted Agent Identity verification, DocuSign evidence, Adobe Sign evidence, and signature audit rows.

## Functional Results

- Invalid CLM transition blocked: `true`
- CLM task count: `3`
- OCR complete platform event published: `true`
- HR Copilot OCR discrepancy count: `1`
- HR Copilot gap count: `1`
- HR Copilot bulk status: `Partially Complete`
- HR Copilot bulk progress: `80.0`
- First signer completed while workflow remained open: `false`
- Trusted Agent Identity blocked the final high-value signature before verification: `true`
- Trusted Agent Identity final status: `Verified`
- KT Sign workflow completed: `true`
- Compliance expiring document count: `1`
- Compliance missing document count after completion: `0`
- Signature request count: `3`
- Signer count: `4`
- Signature audit count: `10`
- Vault count after audit export: `2`
- Document request final status: `Complete`
- Audit export hash present: `true`

## Regression Suite

After the rich record run, the full local Apex test suite was executed:

```powershell
sf.cmd force apex test run --testlevel RunLocalTests --resultformat human --codecoverage --wait 30
```

Latest validation result:

- Test run id: `707g500000OtEiI`
- Tests run: `121`
- Pass rate: `100%`
- Failures: `0`
- Org-wide coverage: `86%`

This regression suite covers the provider/mock-only functions that should not be called live without real Named Credential secrets, including DocuSign, Adobe Sign, virus scan, AWS Textract, and Azure Form Recognizer paths.
