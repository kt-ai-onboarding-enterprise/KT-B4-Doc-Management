# KT B4 Document Operations User Manual

This manual explains how to test and use the B4 document management application from start to finish.

## App

Open the Salesforce app launcher and select **KT B4 Document Operations**.

The app is ordered for end-to-end testing:

1. Home
2. KT Onboarding
3. KT Document Templates
4. 01 Checklist Upload
5. 02 Generate Sign
6. 03 Vault Portal
7. 04 Signature Capture
8. 05 OCR Review
9. 06 Bulk Monitor
10. KT Document Requests
11. KT Document Vault
12. KT Signature Requests
13. KT Signers
14. KT Signature Audits
15. KT OCR Jobs
16. KT Bulk Document Jobs

## Basic End-to-End Flow

1. Create or open a `KT_Onboarding__c` record.
2. The checklist automation creates `KT_Document_Request__c` records from active template configuration.
3. Use **01 Checklist Upload** to view requested documents and upload inbound files.
4. Use **02 Generate Sign** to preview merge data, generate outbound documents, and configure signing.
5. Use **03 Vault Portal** to view vault entries, document status, signature status, OCR status, and versions.
6. Use **04 Signature Capture** when testing native KT Sign signer completion.
7. Use **05 OCR Review** to review extracted fields for OCR-enabled uploaded documents.
8. Use **06 Bulk Monitor** to monitor bulk document jobs.
9. For contracts, move vault status through `Draft`, `Legal Review`, `Counter-Sign`, `Fully Executed`, and `Archived`.
10. Generate audit exports when compliance evidence is needed.

## Document Checklist and Upload

Document checklist records are stored in `KT_Document_Request__c`.

Agent and headless clients can create checklist rows through the `kt_request_document` MCP tool in `mcp/kt-b4-document-tools`.

Use this area to:

- Confirm required documents were created.
- See due dates and status.
- Upload inbound documents.
- Waive document requests when allowed.
- Retrieve vault state through the `kt_get_document_vault` MCP tool when testing headless flows.

Uploaded files are virus-scanned, stored as Salesforce Files, and indexed in `KT_DocumentVault__c`.

Headless clients can upload files through the `kt_upload_document` MCP tool. It stores the file as a Salesforce File, creates the vault entry, and can complete the linked checklist request.

## Document Generation

Document generation uses `KT_DocumentTemplate__c` and template configuration metadata.

The baseline template library is loaded from `scripts/apex/KT_B4_TemplateLibrarySeed.apex`. It creates 205 active templates across healthcare, manufacturing, retail, finance, technology, government/public sector, construction, and generic onboarding.

Use this area to:

- Preview merge values.
- Generate the document.
- Store the generated file in the vault.
- Link the generated document back to the request.

Template records are ready for checklist selection after load. For real document generation, confirm `Template_Binary__c` contains the approved Salesforce File `ContentDocumentId` for the DOCX or PDF template.

Admins maintain template fields with the `KT_Admin` permission set. HR users and compliance users can read template configuration through their B4 permission sets.

## Signing

B4 supports:

- Native KT Sign.
- DocuSign.
- Adobe Sign.

Headless clients can create signature request and signer records through the `kt_dispatch_signing` MCP tool.

Signature workflows use:

- `KT_Signature_Request__c`
- `KT_Signer__c`
- `KT_Signature_Audit__c`

When all required signers complete, the system marks the signature request fully signed, updates the vault entry, and completes the linked document request.

## DocuSign

DocuSign uses `KT_DocuSign_NC`.

Supported actions:

- Create envelope.
- Send envelope.
- Refresh status.
- Retrieve completed signed document.
- Receive webhook events at `/services/apexrest/kt/v1/docusign/webhook`.

Webhook events update signature records and create audit rows.

## Adobe Sign

Adobe Sign uses `KT_AdobeSign_NC`.

Supported actions:

- Create agreement.
- Send agreement.
- Refresh agreement status.
- Retrieve completed signed document.
- Process service-level webhook callbacks.
- Receive REST webhook events at `/services/apexrest/kt/v1/adobesign/webhook`.

Adobe Sign writes the agreement id into `KT_Signature_Request__c.External_Envelope_Id__c`.

The Adobe Sign webhook supports the verification handshake and these event types:

- `AGREEMENT_ACTION_COMPLETED`
- `AGREEMENT_RECALLED`
- `AGREEMENT_EXPIRED`
- `AGREEMENT_OUT_FOR_SIGNATURE`

Completed events retrieve the signed PDF and update the vault, signer, signature request, and linked document request.

## OCR Review

OCR starts when an uploaded document requires OCR.

OCR jobs are stored in `KT_OCR_Job__c`.

Use OCR review to:

- Check extracted field values.
- Compare confidence scores.
- Accept high-confidence values.
- Apply accepted values back to Salesforce records.

## CLM Lifecycle

Contract documents are vault entries with `Document_Type__c = Contract`.

Required lifecycle order:

1. `Draft`
2. `Legal Review`
3. `Counter-Sign`
4. `Fully Executed`
5. `Archived`

The system blocks invalid stage jumps and creates lifecycle tasks.

## Audit Export

Audit export creates a certified PDF summary for an onboarding record.

The export includes:

- Vault document evidence.
- Salesforce File version history.
- Signature request and signer status.
- Signature audit hashes.
- OCR job evidence.

The generated PDF is stored back into the vault as a compliance record.

## Required Setup Notes

Named credentials must be configured by the org admin before real external integrations work:

- `KT_DocuSign_NC`
- `KT_AdobeSign_NC`
- `KT_AWS_Textract_NC`
- `KT_Azure_FormRecognizer_NC`
- `KT_VirusScan_NC`

Secrets and tokens must not be stored in source code or custom metadata.

## Test Evidence

Sprint 6 automated tests cover OCR, DocuSign, Adobe Sign, CLM lifecycle, and audit export behavior. The focused Sprint 6 suite passed 63 of 63 tests in run `707g500000OGnl2`.

Sprint 6 UAT is documented in `docs/uat/KT_B4_Sprint6_UAT.md`. The smoke script `scripts/apex/KT_B4_Sprint6_UAT_Smoke.apex` creates live org evidence for OCR review, CLM transitions, DocuSign/Adobe signature records, and audit export generation.

## Security Setup

For regulated customers, configure Shield Platform Encryption for B4 PII and evidence fields. Follow `docs/implementation/KT_B4_Sprint6_Shield_Encryption.md`.

For 10-year audit retention, configure Field Audit Trail for B4 lifecycle status fields. Follow `docs/implementation/KT_B4_Sprint6_Field_Audit_Trail.md`.
