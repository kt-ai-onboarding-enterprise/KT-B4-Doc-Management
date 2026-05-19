# KT B4 OCR and Virus Scan Setup Guide

This guide covers the remaining live external setup after pausing Adobe Sign for the current demo.

## Current Demo Position

- DocuSign is the selected live e-sign provider.
- Adobe Sign is paused unless a stakeholder specifically requests it.
- OCR and virus scan services are implemented, tested, and deployed, but live provider callouts require customer-owned credentials.

## OCR Provider Choice

B4 supports two OCR providers through `KT_OCR_Provider_Config__mdt`:

| Provider | Named Credential | Current Config |
| --- | --- | --- |
| AWS Textract | `KT_AWS_Textract_NC` | Active by default |
| Azure Form Recognizer | `KT_Azure_FormRecognizer_NC` | Inactive by default |

Only one provider should be active for a clean demo. Keep AWS active unless the customer specifically wants Azure.

## AWS Textract Setup

1. Open Salesforce Setup.
2. Configure `KT_AWS_Textract_NC` with the approved AWS authentication method.
3. Confirm the endpoint matches the AWS region used by the customer, for example `https://textract.us-east-1.amazonaws.com`.
4. Keep `KT_OCR_Provider_Config__mdt.AWS_Textract` active.
5. Keep `Endpoint_Path__c = /`.
6. Run an OCR upload test with a demo passport, driver license, or professional certificate.
7. Confirm the OCR job moves to `Review Required` and the vault OCR status moves to `Review Required`.

## Azure Form Recognizer Setup

Use Azure only if AWS is not the selected OCR provider.

1. Open Salesforce Setup.
2. Configure `KT_Azure_FormRecognizer_NC` with the customer Azure Document Intelligence endpoint and authentication.
3. Update the named credential endpoint from the placeholder host to the real Azure resource host.
4. Set `KT_OCR_Provider_Config__mdt.Azure_Form_Recognizer.Is_Active__c = true`.
5. Set `KT_OCR_Provider_Config__mdt.AWS_Textract.Is_Active__c = false`.
6. Confirm `Endpoint_Path__c` matches the deployed Azure model route.
7. Run the same OCR upload/review test.

## Virus Scan Setup

`KT_VirusScanService` calls `KT_VirusScan_NC` at `/scan`.

The scanner endpoint must accept:

```json
{
  "fileName": "example.pdf",
  "contentType": "application/pdf",
  "base64Data": "..."
}
```

The expected response can be either:

```json
{ "status": "clean" }
```

or:

```json
{ "isClean": true }
```

For infected files, return:

```json
{ "status": "infected", "threatName": "Demo.Test.Threat" }
```

If the scanner is unavailable or returns a non-2xx response, B4 marks the scan outcome for manual review instead of silently approving the file.

## Demo Readiness Test

After configuring OCR and virus scan:

1. Upload a clean inbound file through **01 Checklist Upload**.
2. Confirm a Salesforce File is created and linked to the vault record.
3. Confirm the vault record appears in the onboarding **Related** tab and in the vault app tab.
4. Submit or trigger OCR for an OCR-required document.
5. Open **05 OCR Review** and confirm extracted values are visible.
6. Accept high-confidence fields.
7. Confirm the OCR job, vault OCR status, and audit/demo evidence are updated.

## If Provider Credentials Are Not Available

The rich UAT data and regression tests remain valid for demo purposes. Present OCR and virus scan as implemented provider-ready capabilities, then show the populated `KT_OCR_Job__c` demo record and the OCR review UI instead of making live external provider calls.
