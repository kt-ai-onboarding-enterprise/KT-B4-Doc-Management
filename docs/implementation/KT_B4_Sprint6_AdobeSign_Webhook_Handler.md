# KT B4 Sprint 6 Adobe Sign Webhook Handler

- Tracker task: `B4-T044`
- Scope: Adobe Sign REST webhook endpoint for verification and agreement status events
- Validation: Salesforce deploy validation `0Afg500000830a0CAA`, Adobe Sign tests `15 / 15` passing

## Implemented

- Added `KT_AdobeSignWebhookHandler`.
- Added `KT_AdobeSignWebhookHandlerTest`.
- REST endpoint: `/services/apexrest/kt/v1/adobesign/webhook`.
- Supports Adobe Sign verification handshake by echoing the `X-AdobeSign-ClientId` header.
- Validates webhook calls using a package-safe verification token lookup.
- Supports payloads with top-level fields, nested `agreement`, nested `agreementInfo`, or nested `data`.
- Processes:
  - `AGREEMENT_ACTION_COMPLETED`
  - `AGREEMENT_RECALLED`
  - `AGREEMENT_EXPIRED`
  - `AGREEMENT_OUT_FOR_SIGNATURE`
- Completed events retrieve the final signed PDF through `KT_AdobeSignService.retrieveCompletedDocument`.
- Recalled, expired, and in-progress events are routed through `KT_AdobeSignService.webhookCallback`.
- Creates audit records for completed webhook evidence.

## Notes

- Subscriber orgs must configure the Adobe Sign verification token in a secure settings object. The handler looks for `KT_Integration_Security__c` or `KT_AdobeSign_Webhook_Security__c` with a supported token field name.
- Tests use `verificationTokenOverride`; no webhook secret or token is stored in source.
