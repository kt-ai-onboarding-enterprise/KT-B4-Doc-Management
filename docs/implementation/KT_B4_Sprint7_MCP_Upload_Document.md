# KT B4 Sprint 7 - MCP Upload Document Tool

## Tracker Task

`B4-T051 kt_upload_document MCP Tool`

## Status

Completed in the shared B4 MCP server.

## Tool

Location:

```text
mcp/kt-b4-document-tools
```

Tool name:

```text
kt_upload_document
```

The tool uploads a base64 payload to Salesforce Files, creates a `KT_DocumentVault__c` entry, and optionally updates a linked `KT_Document_Request__c` row to `Complete`.

## Required Inputs

- `onboardingId`
- `fileName`
- `contentBase64`

## Optional Inputs

- `documentRequestId`
- `documentType`
- `vaultStatus`
- `ocrStatus`
- `signatureStatus`
- `regulatoryTag`

## Output

- `contentVersionId`
- `contentDocumentId`
- `vaultEntryId`
- `documentRequestId` when supplied

## Local Check

```powershell
cd mcp/kt-b4-document-tools
npm run check
```

