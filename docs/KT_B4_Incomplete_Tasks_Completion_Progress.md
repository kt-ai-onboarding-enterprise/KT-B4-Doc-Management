# KT B4 Incomplete Tasks Completion Progress

Started: 2026-08-29

Source files:
- `docs/KT_B4_Tracker_Design_Local_Audit.md`
- `docs/Design_docs/KT_B4_DocumentManagement_Tracker_Status_Update_For_Google_v2.csv`
- `docs/Design_docs/KT_B4_Document_Management_CLM_Design_v1.docx`
- `docs/implementation/*.md`
- `docs/uat/*.md`

Org status:
- `onbdev` alias resolves to org `00DdM00000uOtzHUAS`.
- Salesforce CLI access works when PowerShell sets `$env:NODE_OPTIONS='--use-system-ca'`.
- Without that setting, org operations can fail with certificate/TLS errors such as `UNABLE_TO_VERIFY_LEAF_SIGNATURE`.

## Task Progress

| Task | Status | Work / Decision | Validation |
| --- | --- | --- | --- |
| B4-T007 Named Credentials | Completed with org setup dependency | Local metadata and `onbdev` both contain `KT_DocuSign_NC`, `KT_AWS_Textract_NC`, `KT_Azure_FormRecognizer_NC`, `KT_AdobeSign_NC`, and `KT_VirusScan_NC`. Existing setup docs explain that subscriber admins must provide real endpoints, principals, tokens, and secrets. No secrets were hardcoded. | `sf data query` against `onbdev` returned all five Named Credential records. Secret/principal validation remains admin-side setup. |
| B4-T043 Adobe Sign Service | Completed with org setup dependency | `KT_AdobeSignService.cls` and `KT_AdobeSignServiceTest.cls` already implement create, send, status refresh, completed document retrieval, status mapping, audit/status updates, and mock callout coverage. No rewrite was needed. Real Adobe Sign use remains dependent on `KT_AdobeSign_NC` subscriber credentials. | Focused tests passed in `onbdev` test run `707dM00001gK946`; included mock Adobe Sign callouts. |
| B4-T044 Adobe Sign Webhook Handler | Completed with org setup dependency | `KT_AdobeSignWebhookHandler.cls` and test already implement REST verification, token validation, payload parsing, event routing, completed document retrieval, and simulated webhook tests. No rewrite was needed. Real webhook use requires Adobe Sign tenant configuration and verification token setup. | Focused tests passed in `onbdev` test run `707dM00001gK946`; included simulated Adobe Sign webhook payloads. |
| B4-T051 `kt_verify_document` MCP Tool | Completed locally | Added `kt_verify_document` to `mcp/kt-b4-document-tools/server.js`. It verifies B4 document evidence by request, vault entry, signature request, or onboarding id and reports request/vault/signature/signer/audit/file evidence without duplicating upload behavior. Existing MCP tools were preserved. | `npm --prefix mcp/kt-b4-document-tools run check` passed. MCP `tools/list` returns `kt_verify_document`. Live Salesforce API execution requires valid `SF_INSTANCE_URL`/`SF_ACCESS_TOKEN`. |
| B4-T055 `KT_AXLDocPayloadBuilder.cls` | Completed and deployed | Added B4-owned `KT_AXLDocPayloadBuilder.cls` and test. The class safely delegates to existing `KT_AXLSigningTileService` so the tracker-required class name exists without duplicating Slack/Teams payload logic or breaking the working AXL service. Added `KT_Admin` permission set class access. | Deployed to `onbdev` with deploy id `0AfdM00000fGgYLSA0`. Focused tests passed in run `707dM00001gK946`; `KT_AXLDocPayloadBuilder` coverage is 83%. |
| B4-T058 DocuSign AgentExchange MCP Upgrade | Blocked by external connector dependency | Existing custom DocuSign Named Credential integration remains active. No AgentExchange DocuSign MCP connector/tool/package is available in this repo/tool context, so the optional upgrade cannot be completed without external connector access and tenant setup. | Tool discovery did not expose a DocuSign AgentExchange MCP capability. No working DocuSign Apex integration was removed or downgraded. |

## Fresher-Friendly Verification Steps

1. Set Salesforce CLI to use the local system CA store in PowerShell:

   ```powershell
   $env:NODE_OPTIONS='--use-system-ca'
   ```

2. Re-authenticate the Salesforce org alias if the org still shows auth errors:

   ```powershell
   sf org login web --alias onbdev
   ```

3. Deploy only the changed B4 files:

   ```powershell
   sf project deploy start --target-org onbdev --source-dir force-app/main/default/classes/KT_AXLDocPayloadBuilder.cls --source-dir force-app/main/default/classes/KT_AXLDocPayloadBuilder.cls-meta.xml --source-dir force-app/main/default/classes/KT_AXLDocPayloadBuilderTest.cls --source-dir force-app/main/default/classes/KT_AXLDocPayloadBuilderTest.cls-meta.xml --source-dir force-app/main/default/permissionsets/KT_Admin.permissionset-meta.xml
   ```

   Result from this run: deployed successfully to `onbdev`, deploy id `0AfdM00000fGgYLSA0`.

4. Run focused Apex tests:

   ```powershell
   sf apex run test --target-org onbdev --class-names KT_AXLDocPayloadBuilderTest,KT_AXLSigningTileServiceTest,KT_AdobeSignServiceTest,KT_AdobeSignWebhookHandlerTest --result-format human --code-coverage --wait 20
   ```

   Result from this run: passed, 19/19 tests, test run id `707dM00001gK946`.

5. Validate the MCP server syntax:

   ```powershell
   npm --prefix mcp/kt-b4-document-tools run check
   ```

6. Validate MCP tool listing. The returned tool list should include `kt_verify_document` along with the existing B4 MCP tools.

   Local result from this run: passed. `tools/list` returned `kt_verify_document`.

7. For real MCP execution, set `SF_INSTANCE_URL` and `SF_ACCESS_TOKEN`, then call `kt_verify_document` with one of:
   - `documentRequestId`
   - `vaultEntryId`
   - `signatureRequestId`
   - `onboardingId`

8. For a complete B4 flow:
   - Create or open a `KT_Onboarding__c` record.
   - Create/request a document checklist row.
   - Upload or generate a document.
   - Confirm a `KT_DocumentVault__c` row exists and has `Content_Document_Id__c`.
   - Dispatch signing.
   - Build the AXL payload with `KT_AXLDocPayloadBuilder`.
   - Simulate or complete signing/webhook handling.
   - Run `kt_verify_document` and confirm `verified: true` for the required evidence.

## Remaining Blockers

- Real Named Credential secrets/endpoints must be configured by an org admin for live AWS Textract, Azure Form Recognizer, Virus Scan, Adobe Sign, and any refreshed DocuSign environments.
- DocuSign AgentExchange MCP remains blocked until the actual connector/tool/package is available.
- Broad B4 run `707dM00001gKces` executed 118 tests with 94% pass rate, but failed in pre-existing completed-task areas outside this incomplete-task scope:
  - `KT_CLMContractLifecycleServiceTest.lifecycleActionCreatesLegalReviewTask`
  - `KT_CLMContractLifecycleServiceTest.triggerAllowsOrderedContractLifecycle`
  - `KT_DocumentChecklistServiceTest.<compile>` with `Invalid type: KT_DocumentChecklistService.ChecklistResult`
- The broad B4 failures were not changed here because this work is restricted to the six incomplete tasks and must not modify completed working task code unless directly required.
