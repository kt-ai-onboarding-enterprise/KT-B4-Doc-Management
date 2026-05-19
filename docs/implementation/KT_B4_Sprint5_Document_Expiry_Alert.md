# KT B4 Sprint 5 - Document Expiry Alert

## Design Coverage

`B4-T042 Build Scheduled Flow: KT_Document_Expiry_Alert (30/60/90-day expiry notifications)`

## Implementation

`KT_Document_Expiry_Alert` is a scheduled flow that runs the document expiry alert path for vault documents nearing expiration.

The flow delegates the alert behavior to `KT_DocumentFlowAutomationService`, which evaluates the 30, 60, and 90 day windows and creates follow-up tasks for compliance review.

## Deployment Evidence

Deploy ID: `0Afg5000008KMNxCAO`

Focused test command:

```powershell
sf.cmd force apex test run --tests KT_DocumentFlowAutomationServiceTest --resultformat human --codecoverage --synchronous
```

Result:

- 6 of 6 tests passed.
- Pass rate: 100%.
- `KT_DocumentFlowAutomationService` coverage: 83%.
