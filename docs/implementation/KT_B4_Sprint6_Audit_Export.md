# KT B4 Sprint 6 Audit Export

- Tracker task: `B4-T040`
- Scope: Certified audit-ready document export for an onboarding record
- Validation: Salesforce deploy validation `0Afg5000007zRCDCA2`, `KT_AuditExportServiceTest`, `3 / 3` passing

## Implemented

- Added `KT_AuditExportService`.
- Added `KT_AuditExportServiceTest`.
- Added Aura and invocable entry points so the export can be launched from Lightning, Flow, or future agent actions.
- Export package includes:
  - Document vault entries.
  - Salesforce File version history for linked documents.
  - Signature request and signer status evidence.
  - Signature audit events and hash values.
  - OCR job status, confidence, reviewer, and review timestamp.
- The service generates a simple PDF stream with a certification footer.
- The certification footer includes:
  - Export timestamp.
  - SHA-256 certification hash.
  - Generating user id.
- The generated PDF is stored as `ContentVersion`.
- A new `KT_DocumentVault__c` compliance record is created for the export with `Regulatory_Tag__c = Audit Export`.

## Notes

- The PDF is intentionally generated in Apex without external libraries or callouts, matching the lightweight PDF pattern already used by `KT_DocumentGeneratorService`.
- The export is an evidence summary package, not a binary merge of all source PDFs. Source document traceability is preserved through included `ContentDocumentId`, version history, signature audit, and OCR evidence.
