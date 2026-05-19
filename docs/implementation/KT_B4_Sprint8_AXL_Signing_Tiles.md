# KT B4 Sprint 8 - AXL Signing Tiles

## Tracker Task

`B4-T048 AXL signing tiles - Slack/Teams interactive signing card with mobile signing flow`

## Status

Completed as the package-safe tile generation layer.

## Design Alignment

The design calls for signing-pending state to render as an interactive Slack or Teams card that opens the mobile signing flow.

## Implementation

Added `KT_AXLSigningTileService`.

The service:

- Finds the next pending or invited signer for a signature request.
- Issues a KT Sign session token using `KT_ESignatureService.issueSessionToken`.
- Builds a mobile signing URL for the existing `KT_B4_04_Signature_Capture` page.
- Returns Slack block-kit style JSON or Microsoft Teams Adaptive Card JSON.

Methods:

```apex
KT_AXLSigningTileService.buildSigningTile(signatureRequestId, channel)
KT_AXLSigningTileService.buildSigningTiles(requests)
```

`channel` supports `Slack` and `Teams`.

## Connector Boundary

This task does not require Slack or Teams secrets in source. The service returns the card payload for downstream Slack/Teams delivery by an approved connector, automation, or middleware.

## Verification

Focused tests:

```powershell
sf.cmd force apex test run --testlevel RunSpecifiedTests --classnames KT_AXLSigningTileServiceTest --resultformat human --codecoverage --wait 10
```

Result:

- Test run id: `707g500000Oqn60`
- Tests ran: 2
- Pass rate: 100%
- `KT_AXLSigningTileService` coverage: 93%
