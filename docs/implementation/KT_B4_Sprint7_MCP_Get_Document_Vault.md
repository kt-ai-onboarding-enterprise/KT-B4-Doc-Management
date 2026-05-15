# KT B4 Sprint 7 - MCP Get Document Vault Tool

## Tracker Task

`B4-T052 kt_get_document_vault MCP Tool`

## Status

Completed in the shared B4 MCP server.

## Tool

Location:

```text
mcp/kt-b4-document-tools
```

Tool name:

```text
kt_get_document_vault
```

The tool returns vault rows for an onboarding record and can include related signature requests, OCR jobs, and Salesforce File version history.

## Inputs

- `onboardingId` required
- `includeVersionHistory` optional
- `includeSignatureRequests` optional, defaults to true
- `includeOcrJobs` optional, defaults to true

## Output

The response includes `count` and `vaultEntries`. Each vault entry includes the base vault fields plus:

- `versionHistory`
- `signatureRequests`
- `ocrJobs`

## Local Check

```powershell
cd mcp/kt-b4-document-tools
npm run check
```

