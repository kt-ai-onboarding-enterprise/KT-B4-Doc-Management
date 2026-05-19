# KT B4 Sprint 6 - OCR Field Mapping Metadata

## Design Coverage

`B4-T044 Populate KT_OCR_FieldMapping__mdt records for Passport, Driver's License, Professional License (both providers)`

## Implementation

The OCR field mapping custom metadata type is present in source as `KT_OCR_FieldMapping__mdt`.

The deployed metadata includes mappings for:

- Passport through AWS Textract and Azure Form Recognizer.
- Driver License through AWS Textract and Azure Form Recognizer.
- Professional Certificate through AWS Textract and Azure Form Recognizer.

`KT_OcrIngestionService` uses these mappings to translate provider JSON paths into target Salesforce fields and to store structured extracted data on `KT_OCR_Job__c.Extracted_Fields__c`.

## Deployment Evidence

Deploy ID: `0Afg5000008KMNxCAO`

Focused test command:

```powershell
sf.cmd force apex test run --tests KT_OcrIngestionServiceTest --resultformat human --codecoverage --synchronous
```

Result:

- 7 of 7 tests passed.
- Pass rate: 100%.
- `KT_OcrIngestionService` coverage: 79%.
