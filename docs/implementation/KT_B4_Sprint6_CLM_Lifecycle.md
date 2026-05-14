# KT B4 Sprint 6 CLM Lifecycle

- Tracker task: `B4-T039`
- Scope: Contract lifecycle states on `KT_DocumentVault__c`
- Validation: Salesforce deploy validation `0Afg5000007yvsDCAQ`, `KT_CLMContractLifecycleServiceTest`, `4 / 4` passing

## Implemented

- Added `Contract` to `KT_DocumentVault__c.Document_Type__c`.
- Added CLM statuses to `KT_DocumentVault__c.Status__c`: `Legal Review`, `Counter-Sign`, and `Fully Executed`.
- Added `KT_CLM_Contract_Lifecycle` record-triggered Flow for contract vault update automation.
- Added `KT_DocumentVaultLifecycleTrigger` and `KT_CLMContractLifecycleService` to enforce ordered transitions:
  - `Draft` -> `Legal Review`
  - `Legal Review` -> `Counter-Sign`
  - `Counter-Sign` or `Signed` -> `Fully Executed`
  - `Fully Executed` -> `Archived`
- Added same-day task de-duplication so the Flow and trigger can safely route through the same lifecycle service.
- Added `KT_CLM_Approver_Config__mdt` for domain-based task ownership with an `ALL` default route to `KT_HR_Queue`.

## Notes

- The current repo only defines `Hiring_Manager__c` on `KT_Onboarding__c`. The CLM service already detects future domain fields named `Domain_Code__c`, `Domain__c`, or `Primary_Domain__c` and will use matching CMT routes when those fields exist.
- If a configured task queue does not exist in a subscriber org, task ownership falls back to the onboarding hiring manager, onboarding owner, then current user.
