# KT B4 Sprint 7 - MCP Dispatch Signing Tool

## Tracker Task

`B4-T053 kt_dispatch_signing MCP Tool`

## Status

Completed in the shared B4 MCP server.

## Tool

Location:

```text
mcp/kt-b4-document-tools
```

Tool name:

```text
kt_dispatch_signing
```

The tool creates a `KT_Signature_Request__c`, child `KT_Signer__c` rows, and updates the vault entry to pending signature.

## Inputs

- `vaultEntryId` required
- `signers` required
- `onboardingId` optional, resolved from the vault when omitted
- `signingProvider` optional: `KT Sign`, `DocuSign`, or `Adobe Sign`
- `signingOrder` optional: `Sequential` or `Parallel`
- `expiryDays` optional
- `externalEnvelopeId` optional when the provider envelope/agreement already exists

## Notes

The MCP layer does not store provider credentials. Provider API creation/send remains handled by Salesforce services, Named Credentials, webhooks, and provider-specific admin setup.

## Local Check

```powershell
cd mcp/kt-b4-document-tools
npm run check
```

