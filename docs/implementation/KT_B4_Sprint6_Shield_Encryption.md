# KT B4 Sprint 6 Shield Platform Encryption

- Tracker task: `B4-T045`
- Status: Completed as package-safe configuration runbook
- Scope: Shield Platform Encryption guidance for B4 PII and evidence fields

## Fields to Encrypt

Apply Shield Platform Encryption in subscriber org setup to these B4 fields when the customer org is licensed for Shield:

| Object | Field | Reason |
| --- | --- | --- |
| `KT_Signer__c` | `IP_Address__c` | Signature evidence and network identifier |
| `KT_Signer__c` | `Geolocation__c` | Signature evidence location data |
| `KT_Signer__c` | `Device_User_Agent__c` | Device fingerprinting evidence |
| `KT_Signer__c` | `Session_Token__c` | Signing session token hash |
| `KT_Signature_Audit__c` | `IP_Address__c` | Immutable audit network identifier |
| `KT_Signature_Audit__c` | `Geolocation_Latitude__c` | Immutable audit location data |
| `KT_Signature_Audit__c` | `Geolocation_Longitude__c` | Immutable audit location data |
| `KT_Signature_Audit__c` | `Device_User_Agent__c` | Device fingerprinting evidence |
| `KT_Signature_Audit__c` | `Session_Token__c` | Signing session token hash |
| `KT_Signature_Audit__c` | `Hash_Value__c` | Legal tamper-evidence hash |
| `KT_OCR_Job__c` | `Extracted_JSON__c` | Raw OCR output can contain PII |
| `KT_OCR_Job__c` | `Extracted_Fields__c` | Mapped OCR values can contain PII |
| `KT_OCR_Job__c` | `Review_Notes__c` | HR notes can contain PII |
| `KT_DocumentVault__c` | `Content_Document_Id__c` | Document evidence pointer |
| `KT_DocumentVault__c` | `Document_Name__c` | May include identity document labels |
| `KT_DocumentVault__c` | `Regulatory_Tag__c` | Compliance classification metadata |

## Setup Steps

1. Confirm Shield Platform Encryption is licensed and enabled.
2. Go to **Setup > Platform Encryption > Encryption Policy**.
3. Generate or import tenant secret.
4. For regulated customers, use BYOK in **Key Management** and document key ownership.
5. Select the B4 fields listed above.
6. Save encryption policy.
7. Run B4 regression tests:
   - Document upload
   - OCR extraction and HR review
   - KT Sign
   - DocuSign callback
   - Adobe Sign callback
   - Audit export

## Validation Checklist

- OCR jobs still parse and store extracted evidence.
- Signature audit rows are created for KT Sign, DocuSign, and Adobe Sign.
- Audit export still produces a certified PDF.
- Reports and list views used by HR do not rely on unsupported encrypted-field filtering.
- BYOK rotation runbook is stored with customer security documentation.

## Package Notes

Encryption policy is subscriber-org configuration and is not safely deployed as package metadata for every customer. This runbook is the source-controlled implementation artifact for `B4-T045`.
