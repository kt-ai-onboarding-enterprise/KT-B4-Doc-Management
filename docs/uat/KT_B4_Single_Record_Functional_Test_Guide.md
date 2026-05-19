# KT B4 Single Record Functional Test Guide

Use this guide to test the B4 document functionality from one onboarding record, using the deployed Lightning record pages and the KT B4 app tabs.

## Deployment Completed

- Deploy ID: `0Afg5000008LXVrCAO`
- Record pages assigned for desktop view:
  - `KT_Onboarding__c` -> `KT B4 Onboarding Record Page`
  - `KT_DocumentVault__c` -> `KT B4 Document Vault Record Page`
  - `KT_OCR_Job__c` -> `KT B4 OCR Job Record Page`
  - `KT_Bulk_Document_Job__c` -> `KT B4 Bulk Document Job Record Page`
- App tabs now also support URL parameters:
  - `c__onboardingId`
  - `c__documentRequestId`
  - `c__templateId`
  - `c__vaultId`
  - `c__ocrJobId`
  - `c__signerId`
  - `c__sessionToken`

## Recommended Single Record

Use the latest rich onboarding chain:

- Onboarding: `ONB-000109` / `a05g5000006yPHpAAM`
- Pending-signature vault: `a02g50000080A4PAAU`
- Completed DocuSign vault: `a02g5000007zuinAAA`
- Rich OCR onboarding: `ONB-000107` / `a05g5000006yCHNAA2`
- Rich OCR job: `a04g5000001HZIXAA4`
- Rich bulk job: `a00g500000SmHclAAF`

If you want one clean demo path, start with `ONB-000109`. Use `ONB-000107` only for OCR review because it already has a populated review-required OCR job.

## Open The App

1. Open Salesforce.
2. Go to the App Launcher.
3. Open **KT B4 Document Operations**.
4. Confirm the top navigation shows the process tabs:
   - `KT Onboardings`
   - `KT Document Templates`
   - `01 Checklist Upload`
   - `02 Generate Sign`
   - `03 Vault Portal`
   - `04 Signature Capture`
   - `05 OCR Review`
   - `06 Bulk Monitor`

## Test 1: Onboarding Record Page

1. Open the `KT Onboardings` tab.
2. Open `ONB-000109`.
3. Confirm the record page loads the B4 workspace.
4. In the left or sidebar area, confirm standard record information and related lists are visible.
5. In the main area, confirm these LWCs are present:
   - Document checklist/request list
   - Document upload
   - Vault portal
   - Document vault operations
6. In the checklist area:
   - Search for a document request.
   - Filter by status.
   - Confirm counts and progress indicators update.
7. In the upload area:
   - Select a small `.pdf`, `.png`, `.jpg`, or `.docx`.
   - Confirm unsupported files are blocked.
   - Upload a valid file.
   - Confirm success message appears.
8. In the vault areas:
   - Confirm uploaded/generated documents appear.
   - Use search and status filters.
   - Open/download a document if a file is linked.
   - Confirm status, signature status, OCR status, version, and document type are visible.

Expected result: the onboarding record page works as a single command center for checklist, upload, vault portal, and vault operations.

## Test 2: Document Vault Record Page And Signing

1. Open the pending-signature vault record: `a02g50000080A4PAAU`.
2. Confirm the B4 document vault record page opens.
3. Confirm the standard Details/Related section is visible.
4. Confirm the **E-Signature Config** LWC is visible.
5. Choose provider:
   - Use **KT Sign** for native Salesforce signing.
   - Use **DocuSign** for the already configured external demo path.
   - Keep **Adobe Sign** paused unless credentials are configured.
6. Add signer details:
   - Signer name
   - Signer email
   - Role
   - Signing order
7. Click create/initiate workflow.
8. Confirm a `KT_Signature_Request__c` record is created.
9. Confirm related `KT_Signer__c` records are created.
10. For DocuSign, confirm the envelope is sent and signing status can later be refreshed/retrieved.

Expected result: vault-level signing starts from the vault record page, and signature records are linked back to the vault.

## Test 3: Native Signature Capture

Use this only for **KT Sign** signer records that have a session token.

1. Open the signer record created by the KT Sign workflow.
2. Copy the signer record Id.
3. Copy the signer `Session Token` from Details.
4. Open the Signature Capture app page with URL parameters:
   - `/lightning/n/KT_B4_04_Signature_Capture?c__signerId=SIGNER_ID&c__sessionToken=SESSION_TOKEN`
5. Confirm signer name, email, and legal notice load.
6. Draw a signature.
7. Check the agreement checkbox.
8. Submit.
9. Return to the signer record and confirm:
   - Status changed to `Signed`
   - Signed date/time populated
   - Signature image id populated
   - Audit records are created

Expected result: native signature capture completes the signer and updates the workflow state.

## Test 4: OCR Review

Use the existing rich OCR job because OCR provider setup is currently paused.

1. Open `KT OCR Jobs`.
2. Open OCR job `a04g5000001HZIXAA4`.
3. Confirm the B4 OCR job record page opens.
4. Confirm the OCR Review LWC is visible.
5. Review:
   - OCR provider
   - detected document type
   - status
   - field count
   - confidence values
6. Select high-confidence fields.
7. Clear selections and select individual rows.
8. Click apply accepted fields.
9. Confirm success message.
10. Refresh the record and confirm status/review fields update.

Expected result: OCR extracted data can be reviewed, selected, and applied from the OCR job record page.

## Test 5: Bulk Monitor

1. Open `KT Bulk Document Jobs`.
2. Open bulk job `a00g500000SmHclAAF`.
3. Confirm the B4 bulk job record page opens.
4. Confirm the Bulk Document Monitor LWC is visible.
5. Review:
   - total records
   - processed count
   - success count
   - failure count
   - status
   - failure summary
6. Click refresh.

Expected result: bulk job progress and failure/success state are visible from the bulk job record page.

## App Page URL Testing

The app tabs can be tested directly with IDs:

- Checklist/upload:
  - `/lightning/n/KT_B4_01_Checklist_Upload?c__onboardingId=a05g5000006yPHpAAM`
- Generate/sign config:
  - `/lightning/n/KT_B4_02_Generate_Sign_Config?c__onboardingId=a05g5000006yPHpAAM&c__vaultId=a02g50000080A4PAAU`
- Vault portal:
  - `/lightning/n/KT_B4_03_Vault_Portal?c__onboardingId=a05g5000006yPHpAAM`
- OCR review:
  - `/lightning/n/KT_B4_05_OCR_Review?c__ocrJobId=a04g5000001HZIXAA4`
- Bulk monitor:
  - `/lightning/n/KT_B4_06_Bulk_Monitor?c__jobId=a00g500000SmHclAAF`

## Pass Checklist

Mark the single-record test passed only when:

- Onboarding page shows checklist, upload, vault portal, and vault operations.
- A valid file upload creates or updates a vault entry.
- Vault record page shows the e-signature configuration LWC.
- Signing workflow creates signature request and signer records.
- Native KT Sign capture works when signer token is supplied.
- DocuSign path remains usable for external-signing demo.
- OCR review page loads and can apply selected extracted fields.
- Bulk monitor page loads and shows job progress.
- Details and Related tabs show supporting fields, related records, and Files where configured.

