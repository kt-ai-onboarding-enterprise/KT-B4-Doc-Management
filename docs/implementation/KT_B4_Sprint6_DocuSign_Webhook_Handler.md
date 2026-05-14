# KT B4 Sprint 6 DocuSign Webhook Handler

- Tracker task: `B4-T042`
- Scope: DocuSign Connect-style webhook endpoint for envelope status events
- Validation: Salesforce deploy validation `0Afg5000007zymPCAQ`, DocuSign tests `14 / 14` passing

## Implemented

- Added `KT_DocuSignWebhookHandler`.
- Added `KT_DocuSignWebhookHandlerTest`.
- REST endpoint: `/services/apexrest/kt/v1/docusign/webhook`.
- Validates HMAC-SHA256 signatures from headers:
  - `X-DocuSign-Signature-1`
  - `X-DocuSign-Signature`
  - `X-KT-Signature`
  - `X-Hub-Signature-256`
- Correlates inbound events by `KT_Signature_Request__c.External_Envelope_Id__c`.
- Supports JSON payloads with top-level fields or nested `data` fields.
- Processes statuses:
  - `sent` -> signature request `In Progress`, signers `Invitation Sent`
  - `delivered/viewed` -> signers `Viewed`
  - `completed` -> retrieves completed document through `KT_DocuSignEnvelopeService`
  - `declined` -> signature request `Cancelled`, signers `Declined`
  - `voided/cancelled` -> signature request `Cancelled`
  - `expired` -> signature request and vault signature state `Expired`
- Creates `KT_Signature_Audit__c` rows for webhook-driven events.

## Notes

- Subscriber orgs must configure the DocuSign webhook shared secret in a package-safe secret/settings object. The handler currently looks for `KT_Integration_Security__c` or `KT_DocuSign_Webhook_Security__c` with a supported secret field name.
- Tests use `webhookSecretOverride` so no secret is stored in source.
