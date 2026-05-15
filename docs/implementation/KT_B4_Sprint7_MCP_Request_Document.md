# KT B4 Sprint 7 - MCP Document Request Tool

## Tracker Task

`B4-T050 kt_request_document MCP Tool`

## Status

Completed as a standalone MCP stdio server.

## Tool

Location:

```text
mcp/kt-b4-document-tools
```

Tool name:

```text
kt_request_document
```

The tool creates a `KT_Document_Request__c` row for a supplied `KT_Onboarding__c` record.

## Runtime Configuration

Set these environment variables in the MCP host:

```text
SF_INSTANCE_URL=https://your-org.my.salesforce.com
SF_ACCESS_TOKEN=...
SF_API_VERSION=v66.0
```

`SF_ACCESS_TOKEN` must come from an approved OAuth/session flow. Do not store tokens in source files.

## Inputs

- `onboardingId` required
- `templateId` optional
- `templateName` optional, exact active `Template_Name__c` lookup when `templateId` is absent
- `documentDirection` optional: `Outbound`, `Inbound`, or `Both`
- `status` optional
- `isRequired` optional
- `dueDate` optional, `YYYY-MM-DD`
- `waiverReason` optional

## Validation

The server validates Salesforce Id shape, date shape, allowed enum values through the MCP schema, and required Salesforce connection environment variables.

## Local Check

```powershell
cd mcp/kt-b4-document-tools
npm run check
```

