# KT B4 Sprint 5 - Virus Scan Service

## Design Coverage

`B4-T038 Build KT_VirusScanService.cls - pre-upload virus scan via Named Credential; quarantine logic`

## Implementation

`KT_VirusScanService` provides the pre-upload malware scan service surface for B4 document uploads.

The service:

- Sends file content to the configured scanning endpoint through `KT_VirusScan_NC`.
- Returns clean, infected, or manual-review outcomes.
- Supports callable execution for automation and upload orchestration.

## Deployment Evidence

Deploy ID: `0Afg5000008KGTqCAO`

Focused test command:

```powershell
sf.cmd force apex test run --tests KT_VirusScanServiceTest --resultformat human --codecoverage --synchronous
```

Result:

- 3 of 3 tests passed.
- Pass rate: 100%.
- `KT_VirusScanService` coverage: 87%.
