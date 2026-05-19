# KT B4 Demo Readiness Checklist

- Date: 2026-05-18
- Org: `ckumarnc.305960ebf72a@agentforce.com`
- App: `KT B4 Document Operations`

## Ready for Demo

| Area | Status | Evidence |
| --- | --- | --- |
| B4 app navigation | Ready | App tabs ordered from onboarding through bulk monitor and evidence objects |
| Record Details pages | Ready | Deploy `0Afg5000008KZhmCAG` added all-field layouts |
| Related tabs | Ready | Deploy `0Afg5000008LMvNCAW` added related child lists and Files related lists |
| Rich demo data | Ready | `docs/uat/KT_B4_Rich_EndToEnd_Functional_Test.md` |
| Full Apex regression | Ready | Test run `707g500000OrAfv`, 121/121 passed |
| DocuSign live demo | Ready | Envelope `487d214f-37b6-8394-8175-0b3a4b5212aa` completed and retrieved |
| User manual | Ready | `docs/user_manual/KT_B4_User_Manual.md` |

## External Setup Still Needed for Full Provider Demo

| Integration | Current State | Required Before Live Demo |
| --- | --- | --- |
| DocuSign | Configured and live-tested in demo org | Keep `KT_DocuSign_NC` authenticated; refresh OAuth if Salesforce shows pending/expired |
| Adobe Sign | Paused for current demo; alternate provider implementation exists | No action for current demo unless stakeholder specifically requests Adobe Sign |
| AWS Textract | Metadata/service implemented; placeholder auth | Configure `KT_AWS_Textract_NC` with approved AWS auth and region |
| Azure Form Recognizer | Metadata/service implemented; placeholder endpoint/auth | Replace endpoint with Azure Document Intelligence resource and configure auth |
| Virus Scan | Metadata/service implemented; placeholder endpoint/auth | Replace endpoint with approved malware scanning service and configure auth |

Setup guide: `docs/implementation/KT_B4_OCR_VirusScan_Setup_Guide.md`.

## Demo Route

1. Open **KT B4 Document Operations**.
2. Open the rich onboarding record from `docs/uat/KT_B4_Rich_EndToEnd_Functional_Test.md`.
3. Show **Details** fields on onboarding, request, vault, OCR, signature, signer, audit, and bulk job records.
4. Show **Related** child records and **Files** where documents are attached.
5. Open the DocuSign live demo vault/signature request from `docs/uat/KT_B4_DocuSign_Live_Demo_UAT.md`.
6. Show the completed signer, audit trail, vault signature status, and completed document file.
7. Explain that Adobe Sign is paused for this demo because DocuSign is the chosen live provider.
8. Explain that AWS/Azure OCR and virus scan live calls require customer-owned credentials before provider UAT.
