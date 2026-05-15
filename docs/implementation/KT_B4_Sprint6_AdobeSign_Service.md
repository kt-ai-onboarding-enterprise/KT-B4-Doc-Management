# KT B4 Sprint 6 Adobe Sign Service

- Tracker task: `B4-T043`
- Scope: Adobe Sign add-on agreement creation, sending, status refresh, completed document retrieval, and service-level webhook callback processing
- Validation: Salesforce deploy validation `0Afg500000839erCAA`, `KT_AdobeSignServiceTest`, `6 / 6` passing

## Implemented

- Added `KT_AdobeSignService`.
- Added `KT_AdobeSignServiceTest`.
- Uses Named Credential `KT_AdobeSign_NC`.
- Supports:
  - `createAgreement(signatureRequestId)`
  - `sendAgreement(signatureRequestId)`
  - `getAgreementStatus(signatureRequestId)`
  - `retrieveCompletedDocument(signatureRequestId)`
  - `webhookCallback(agreementId, status)`
- Maps existing `KT_Signature_Request__c` and `KT_Signer__c` records into an Adobe Sign agreement payload.
- Stores Adobe agreement id in `KT_Signature_Request__c.External_Envelope_Id__c`.
- On send, marks the signature request `In Progress`, signers `Invitation Sent`, and vault entry `Pending Signature`.
- On signed status or completed document retrieval, marks the signature request `Fully Signed`, signers `Signed`, vault `Signed`, and linked document request `Complete`.
- Retrieves completed signed documents into Salesforce Files and updates the vault `Content_Document_Id__c`.

## Notes

- The service remains package-safe and does not store any Adobe credentials in source.
- `KT_AdobeSign_NC` must be configured in the subscriber org before real callouts work.
- Full REST webhook exposure is tracked separately by `B4-T044`.
