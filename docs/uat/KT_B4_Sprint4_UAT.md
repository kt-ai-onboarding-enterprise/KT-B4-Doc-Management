# KT B4 Sprint 4 UAT

- Date: 2026-05-06
- Org: `Onboardingv2`
- Scope: B4 Sprint 4 document generation, signature, vault, upload, and bulk send flows

## Summary

Sprint 4 UAT passed for the automatable B4 service and data workflows.

During live-org UAT, the original 50-record bulk cohort exposed a governor-limit defect in `KT_DocumentChecklistService.createChecklistForOnboarding`. That service was bulkified, redeployed, and the same 50-record cohort was rerun successfully.

## Automated Regression Evidence

- Apex test run id: `707g500000N1lwG`
- Result: `53 / 53` tests passed
- Org-wide coverage from the run: `90%`

Key coverage points from the run:

- `KT_DocumentGeneratorService`: `90%`
- `KT_DocumentTemplateService`: `90%`
- `KT_DocumentChecklistService`: `87%`
- `KT_ESignatureOrchestrator`: `94%`
- `KT_ESignatureService`: `93%`
- `KT_VirusScanService`: `87%`
- `KT_BulkDocumentBatch`: `92%`
- `KT_BulkDocumentJobService`: `95%`

## Live UAT Smoke

### 50-record bulk cohort

- Existing active template used: `a01g500000LJoJZAA1` (`Offer letter`)
- Bulk job id: `a00g500000QFUJlAAP`
- Apex job id: `707g500000N1eBj`
- Final status: `Complete`
- Processed: `50 / 50`
- Successes: `50`
- Failures: `0`
- Estimated completion timestamp returned by monitor service: `2026-05-06T07:02:58.000Z`

### Bulk checklist creation fix validated

The live insert of 50 onboarding records now completes with the onboarding-triggered checklist flow active and stays within limits. The service now queries onboarding context, active templates, and existing request rows once per cohort instead of once per onboarding record.

## Scenario Matrix

| Scenario | Evidence | Status |
| --- | --- | --- |
| Document checklist auto-creation from DIE | `KT_DocumentChecklistServiceTest.createRequestsFromConfigsBulkHandlesFiftyOnboardings` plus live 50-record insert smoke | Pass |
| HR document generation | `KT_DocumentGeneratorServiceTest.generatesDocumentAndCompletesMatchingRequest` | Pass |
| KT Sign signing flow | `KT_ESignatureOrchestratorTest.completeSignatureAuraWrapperValidatesToken` | Pass |
| Multi-party sequential signing | `KT_ESignatureOrchestratorTest.sequentialWorkflowDispatchesAndCompletes` | Pass |
| Delegation | `KT_ESignatureOrchestratorTest.delegationCreatesDelegateAndExpiryEscalatesPendingSigner` | Pass |
| Expiry escalation | `KT_DocumentFlowAutomationServiceTest.signatureExpiryActionEscalatesRequestAndCreatesTask` | Pass |
| Bulk send 50-record cohort | Live org smoke for job `a00g500000QFUJlAAP` | Pass |
| Vault version history | `KT_DocumentVaultServiceTest.getVaultEntriesAndVersionHistoryReturnRows` | Pass |
| Portal upload and checklist view backend | `KT_DocumentUploadServiceTest.uploadDocumentCreatesContentVaultAndRequestLink` and `KT_DocumentChecklistServiceTest.documentRequestListActionsReturnRowsAndUpdateStatus` | Pass |

## Manual Follow-up

The following UX checks still benefit from a human browser pass in the org:

- Signature pad behavior on actual mobile and desktop browsers
- `ktDocumentPreview` and `KT_Document_Generation_Wizard` screen rendering
- `ktBulkDocumentMonitor` visual progress rendering on an App Page
- Portal-facing upload/checklist presentation in the Experience/portal shell

## Files Changed During UAT Hardening

- [KT_DocumentChecklistService.cls](/abs/c:/Users/KT-User/OneDrive/Desktop/Onboarding%20Version%202/OnboardingV2/force-app/main/default/classes/KT_DocumentChecklistService.cls)
- [KT_DocumentChecklistServiceTest.cls](/abs/c:/Users/KT-User/OneDrive/Desktop/Onboarding%20Version%202/OnboardingV2/force-app/main/default/classes/KT_DocumentChecklistServiceTest.cls)
- [KT_B4_Sprint4_UAT.md](/abs/c:/Users/KT-User/OneDrive/Desktop/Onboarding%20Version%202/OnboardingV2/docs/uat/KT_B4_Sprint4_UAT.md)
