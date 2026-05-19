# KT B4 Sprint 9 - React/Vibes Document Preview Player

## Tracker Task

`B4-T049 React-based document preview player via Vibes 2.0 (Sprint 9 Beta)`

## Status

Deferred.

## Reason

The design names this as a Sprint 9 beta feature that depends on the React/Vibes 2.0 runtime. This local Salesforce DX project currently contains the production LWC preview component `ktDocumentPreview`, but it does not contain a Vibes 2.0 package/runtime scaffold, React bundle integration, or beta access artifacts.

To stay aligned with the design, this task should not be replaced with a different non-React implementation.

## Current Available Preview

The existing `ktDocumentPreview` LWC remains the active preview experience. It supports:

- Template id input or configured template id
- Merge field preview from `KT_DocumentGeneratorService.getPreviewData`
- Merge completion progress
- Generate document action
- Navigation to the generated vault entry

## Resume Criteria

Resume this task when one of the following is available:

- Vibes 2.0 beta runtime/package
- Approved React embedding pattern for Salesforce container use
- Design-approved substitute architecture for the preview player

