# KT B4 Sprint 6 - Template Library Load

## Tracker Task

`B4-T047 Populate Template Library - 200+ KT_DocumentTemplate__c Records`

## Status

Completed as a repeatable seed package and loaded into the development org.

The source-controlled loader creates 205 baseline `KT_DocumentTemplate__c` records across the tracker domains:

| Domain | Count |
| --- | ---: |
| Healthcare | 40 |
| Manufacturing | 30 |
| Retail | 25 |
| Finance | 30 |
| Technology | 25 |
| Government/Public Sector | 20 |
| Construction | 15 |
| Generic/All Domains | 20 |

## Loader

Run:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_TemplateLibrarySeed.apex
```

The script is rerunnable. It queries by `Template_Name__c`, updates matching records, and inserts missing records.

Development org execution on May 14, 2026 inserted 205 records and updated 0 records.

## Permission Set Access

The template field-level permissions were added to:

- `KT_Admin`
- `KT_HR_User`
- `KT_Compliance_Officer`

`KT_Admin` receives edit access to template configuration fields. HR and Compliance receive read access so the app can display template selection and evidence data without allowing template maintenance.

## Template Binary Handling

`Template_Binary__c` stores the Salesforce `ContentDocumentId` for the approved DOCX/PDF file.

Before production enablement:

1. Upload the approved template binaries to Salesforce Files.
2. Copy each `ContentDocumentId`.
3. Add the IDs to the `contentDocumentIds` map in `scripts/apex/KT_B4_TemplateLibrarySeed.apex`.
4. Rerun the seed script.

The metadata records can exist before binaries are available, but document generation should only use records where `Template_Binary__c` is populated with the approved file.

## Document Families

The seed includes offer letters, NDAs, compliance acknowledgments, onboarding checklists, training certificates, policy acknowledgments, safety certifications, credential verification, tax forms, equipment agreements, handbook acknowledgments, benefits enrollment, emergency contacts, background check consent, data privacy notices, role addenda, probation review, exit checklists, remote work agreements, and access requests.

## Field Coverage

Each generated record includes:

- `Template_Name__c`
- `Domain__c`
- `Persona__c`
- `Output_Format__c`
- `Requires_Signature__c`
- `Signer_Roles__c`
- `Signature_Expiry_Days__c`
- `Is_Active__c`
- `Regulatory_Framework__c`
- `Version__c`
- `Language__c`
- `Merge_Field_Map__c`
- `Template_Binary__c` when a `ContentDocumentId` is provided
