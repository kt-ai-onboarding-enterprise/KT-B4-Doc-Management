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

The B4 app pages use upgraded professional LWC experiences with operational headers, progress indicators, search/filter controls, KPI cards, responsive layouts, and clearer upload/sign/review states.

## Record Pages and Related Tabs

The B4 object record pages are configured for demo inspection. Use the **Details** tab to review all business fields grouped by process area, and use the **Related** tab to follow the full document chain.

The desktop record pages also include the active B4 LWCs:

- `KT_Onboarding__c`: checklist/request list, document upload, vault portal, and vault operations.
- `KT_DocumentVault__c`: e-signature workflow configuration.
- `KT_OCR_Job__c`: OCR review and accepted-field apply workspace.
- `KT_Bulk_Document_Job__c`: bulk document monitor.

For a click-by-click single-record test, use `docs/uat/KT_B4_Single_Record_Functional_Test_Guide.md`.

Key related views:

- `KT_Onboarding__c`: document requests, vault entries, OCR jobs, signature requests, and files.
- `KT_DocumentTemplate__c`: document requests, bulk document jobs, and files.
- `KT_Document_Request__c`: generated or uploaded vault entries and files.
- `KT_DocumentVault__c`: linked document requests, OCR jobs, signature requests, activity history, and files.
- `KT_Signature_Request__c`: signers, signature audits, and files.
- `KT_Signer__c`: signature audit trail.

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

If the malware scanning provider reports an infected file, the upload flow should quarantine or reject the document instead of completing the checklist item. If the scan provider cannot return a definitive result, the file is held for manual review.

## Document Generation

Document generation uses `KT_DocumentTemplate__c` and template configuration metadata.

The baseline template library is loaded from `scripts/apex/KT_B4_TemplateLibrarySeed.apex`. It creates 205 active templates across healthcare, manufacturing, retail, finance, technology, government/public sector, construction, and generic onboarding.

If a template has an approved DOCX/PDF file in `Template_Binary__c`, generation uses that uploaded template body. If no binary template is attached, B4 now creates a document-specific default body from the selected template type. For example, Offer Letter templates generate offer-letter language, and HIPAA/compliance healthcare templates generate HIPAA confidentiality and privacy agreement language.

Fallback-generated PDFs are styled for demos with a branded header bar, centered document title, metadata panel, wrapped body content, and signature area.

Generated bodies merge from `KT_Onboarding__c`, including:

- Onboarding Number
- Candidate Name
- Role
- Department
- Start Date
- Work Location
- Hiring Manager
- Generated Date

The current preview experience is the `ktDocumentPreview` LWC. The React/Vibes 2.0 preview player is a deferred Sprint 9 beta item until the Vibes runtime is available.

Use this area to:

- Preview merge values.
- Generate the document.
- Store the generated file in the vault.
- Link the generated document back to the request.

Template records are ready for checklist selection after load. For production-approved legal language, attach the approved Salesforce File `ContentDocumentId` to `Template_Binary__c`; otherwise the fallback body is intended for functional testing and demo flows.

Admins maintain template fields with the `KT_Admin` permission set. HR users and compliance users can read template configuration through their B4 permission sets.

## Signing

B4 supports:

- Native KT Sign.
- DocuSign.
- Adobe Sign as an alternate provider when the customer chooses it.

Headless clients can create signature request and signer records through the `kt_dispatch_signing` MCP tool.

Slack or Teams delivery layers can request an interactive signing card from `KT_AXLSigningTileService`. The generated card opens the existing mobile signing flow with a one-time session token.

Signature workflows use:

- `KT_Signature_Request__c`
- `KT_Signer__c`
- `KT_Signature_Audit__c`

When all required signers complete, the system marks the signature request fully signed, updates the vault entry, and completes the linked document request.

For SOX or HIPAA tagged vault documents, Trusted Agent Identity must be verified before the final signature can complete the workflow. Admins can verify the trusted identity reference through `KT_ESignatureOrchestrator.verifyTrustedAgentIdentity`.

## DocuSign

DocuSign uses `KT_DocuSign_NC`.

DocuSign demo live UAT passed with envelope `487d214f-37b6-8394-8175-0b3a4b5212aa`. See `docs/uat/KT_B4_DocuSign_Live_Demo_UAT.md`.

Supported actions:

- Create envelope.
- Send envelope.
- Refresh status.
- Retrieve completed signed document.
- Receive webhook events at `/services/apexrest/kt/v1/docusign/webhook`.

Webhook events update signature records and create audit rows.

## Adobe Sign

Adobe Sign uses `KT_AdobeSign_NC`.

Adobe Sign is paused for the current demo because DocuSign is the configured live external signing provider. Keep this section as implementation reference only unless a stakeholder asks to demonstrate Adobe Sign specifically.

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

OCR extraction uses `KT_OCR_FieldMapping__mdt` records to map AWS Textract and Azure Form Recognizer responses for passports, driver licenses, and professional certificates into Salesforce field values.

Use OCR review to:

- Check extracted field values.
- Compare confidence scores.
- Accept high-confidence values.
- Apply accepted values back to Salesforce records.

HR Copilot can use the OCR discrepancy Agentforce action to find OCR jobs that are failed, rejected, review-required, or below the confidence threshold.

## Agentforce Actions

KT HR Copilot actions are available for:

- OCR discrepancy detection.
- Checklist gap analysis.
- Bulk document job status.
- Signing escalation for the next pending signer.

KT Compliance Auditor actions are available for:

- Missing required compliance documents.
- Expiring vault documents.
- Certified audit report generation.

Admins receive all action access through `KT_Admin`. HR users receive HR Copilot action access through `KT_HR_User`. Compliance users receive auditor action access through `KT_Compliance_Officer`.

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

## Bulk Jobs

Bulk document generation uses `KT_Bulk_Document_Job__c` to track job status, total records, processed count, success count, failure count, and failure summary. Use **06 Bulk Monitor** or the HR Copilot bulk job action to review progress.

## Expiry Alerts

`KT_Document_Expiry_Alert` runs the 30, 60, and 90 day expiry alert process for vault documents. The automation creates follow-up tasks so compliance users can review expiring documents before they become invalid.

## Required Setup Notes

Named credentials must be configured by the org admin before real external integrations work:

- `KT_DocuSign_NC`
- `KT_AdobeSign_NC`
- `KT_AWS_Textract_NC`
- `KT_Azure_FormRecognizer_NC`
- `KT_VirusScan_NC`

Secrets and tokens must not be stored in source code or custom metadata.

Adobe Sign is paused for the current demo. For the remaining live OCR and malware scan provider setup, use `docs/implementation/KT_B4_OCR_VirusScan_Setup_Guide.md`.

## Test Evidence

Sprint 6 automated tests cover OCR, DocuSign, Adobe Sign, CLM lifecycle, and audit export behavior. The focused Sprint 6 suite passed 63 of 63 tests in run `707g500000OGnl2`.

Sprint 6 UAT is documented in `docs/uat/KT_B4_Sprint6_UAT.md`. The smoke script `scripts/apex/KT_B4_Sprint6_UAT_Smoke.apex` creates live org evidence for OCR review, CLM transitions, DocuSign/Adobe signature records, and audit export generation.

The full B4 end-to-end functional smoke is documented in `docs/uat/KT_B4_EndToEnd_Functional_Test.md`. The script `scripts/apex/KT_B4_EndToEnd_Functional_Test.apex` validates onboarding, checklist, vault, CLM, OCR event publishing, Agentforce actions, bulk status, AXL tile generation, Trusted Agent Identity, KT Sign completion, compliance actions, and audit export.

For demos, use the richer record set documented in `docs/uat/KT_B4_Rich_EndToEnd_Functional_Test.md`. It includes fuller template, vault, OCR, bulk, KT Sign, DocuSign evidence, Adobe Sign evidence, compliance, and audit export data.

Use `docs/uat/KT_B4_Demo_Readiness_Checklist.md` before a stakeholder demo. It identifies what is already ready in the org, confirms Adobe Sign is paused for the current demo, and lists which external provider credentials are still required for live OCR or virus scan calls.

## Security Setup

For regulated customers, configure Shield Platform Encryption for B4 PII and evidence fields. Follow `docs/implementation/KT_B4_Sprint6_Shield_Encryption.md`.

For 10-year audit retention, configure Field Audit Trail for B4 lifecycle status fields. Follow `docs/implementation/KT_B4_Sprint6_Field_Audit_Trail.md`.
