# KT B4 Named Credential Setup

B4 callouts must use Named Credentials only. The package includes endpoint metadata without secrets; subscriber admins must attach the correct External Credential, principal, and authentication parameters after installation.

## Named Credentials

| Named Credential | Intended Auth | Notes |
| --- | --- | --- |
| `KT_DocuSign_NC` | OAuth 2.0 JWT | Configure DocuSign OAuth/JWT principal and update endpoint for demo or production account. |
| `KT_AWS_Textract_NC` | AWS Signature Version 4 | Configure AWS region/service `textract` and a named principal or STS principal. |
| `KT_Azure_FormRecognizer_NC` | API Key or Azure AD OAuth | Replace placeholder resource host with the subscriber Azure AI Document Intelligence endpoint. |
| `KT_VirusScan_NC` | API Key | Replace placeholder endpoint with the subscriber-approved malware scanning service. |
| `KT_AdobeSign_NC` | OAuth 2.0 Authorization Code | Paused for the current demo; configure only when Adobe Sign is selected as the customer signing provider. |

## Package-Safe Rules

- Do not store tokens, API keys, client secrets, AWS keys, or certificates in Apex, Custom Metadata, Static Resources, or this repository.
- Apex must call integrations with `callout:<NamedCredentialName>` endpoints only.
- Subscriber-specific tokens and principals must be populated in Setup or through the Salesforce Named Credentials Connect API after package installation.
