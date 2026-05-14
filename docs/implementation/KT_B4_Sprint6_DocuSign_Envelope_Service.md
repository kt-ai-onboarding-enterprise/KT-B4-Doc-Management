# KT B4 Sprint 6 DocuSign Envelope Service

- Tracker task: `B4-T041`
- Scope: DocuSign add-on envelope creation, sending, status refresh, and completed document retrieval
- Validation: Salesforce deploy validation `0Afg5000007zj4HCAQ`, `KT_DocuSignEnvelopeServiceTest`, `5 / 5` passing

## Implemented

- Added `KT_DocuSignEnvelopeService`.
- Added `KT_DocuSignEnvelopeServiceTest`.
- Uses Named Credential `KT_DocuSign_NC`.
- Supports:
  - `createEnvelope(signatureRequestId, accountId)`
  - `sendEnvelope(signatureRequestId, accountId)`
  - `getEnvelopeStatus(signatureRequestId, accountId)`
  - `retrieveCompletedDocument(signatureRequestId, accountId)`
- Maps existing `KT_Signature_Request__c` and `KT_Signer__c` records into a DocuSign envelope payload.
- Stores DocuSign `envelopeId` in `KT_Signature_Request__c.External_Envelope_Id__c`.
- On send, marks the signature request `In Progress`, signers `Invitation Sent`, and the vault entry `Pending Signature`.
- On completed status or completed document retrieval, marks the signature request `Fully Signed`, signers `Signed`, vault `Signed`, and linked document request `Complete`.
- Retrieves the combined completed document into Salesforce Files and updates the vault `Content_Document_Id__c`.

## Notes

- The service is ready for the B12 feature gate once `LicenseManager` exists in this repo. It does not hard-reference that missing class yet, so the B4 package remains deployable.
- The current named credential metadata is a placeholder. Subscriber org setup still needs the OAuth/JWT principal and DocuSign account endpoint configuration described in `KT_B4_NamedCredential_Setup.md`.
