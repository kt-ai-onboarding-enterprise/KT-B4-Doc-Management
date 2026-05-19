# KT B4 Sprint 6 - Agentforce B4 Actions

## Design Coverage

- `B4-T035 Publish KT_OCR_Job_Complete__e and wire to HR Copilot Agentforce action`
- `B4-T036 Configure Agentforce KT HR Copilot B4 actions`
- `B4-T037 Configure Agentforce KT Compliance Auditor B4 actions`

## Implementation

The repo now includes package-safe Apex invocable actions that can be registered as Agentforce actions for the KT HR Copilot and KT Compliance Auditor agents.

HR Copilot actions:

- `KT_HRCopilotOcrDiscrepancyAction` returns OCR jobs needing review or below confidence threshold.
- `KT_HRCopilotGapAnalysisAction` returns checklist gap counts through `KT_DocumentChecklistService`.
- `KT_HRCopilotBulkJobStatusAction` returns bulk generation progress through `KT_BulkDocumentJobService`.
- `KT_HRCopilotSigningEscalationAction` creates an escalation task for the next pending signer.

Compliance Auditor actions:

- `KT_ComplianceMissingDocsAction` returns required compliance document requests that are incomplete.
- `KT_ComplianceExpiringDocsAction` returns vault documents expiring within the requested window.
- `KT_ComplianceAuditReportAction` creates the certified audit package through `KT_AuditExportService`.

The design platform event `KT_OCR_Job_Complete__e` is present in source and remains the event signal for OCR completion. The new OCR discrepancy invocable gives the HR Copilot an action surface to summarize and route completed OCR jobs requiring human review.

## Security

Permission set access was added for the new action classes:

- `KT_Admin` can execute all HR Copilot and Compliance Auditor actions.
- `KT_HR_User` can execute the HR Copilot actions.
- `KT_Compliance_Officer` can execute the Compliance Auditor actions.

## Deployment Evidence

Deploy ID: `0Afg5000008KM6DCAW`

Focused test command:

```powershell
sf.cmd force apex test run --tests KT_AgentforceB4ActionsTest --resultformat human --codecoverage --synchronous
```

Result:

- 2 of 2 tests passed.
- Pass rate: 100%.
- Key coverage: HR Copilot action classes 81-96%; Compliance Auditor action classes 91-95%.
