# KT B4 DocuSign Live Demo UAT

- Date: 2026-05-18
- Org: `ckumarnc.305960ebf72a@agentforce.com`
- DocuSign environment: Demo
- Status: Passed

## Configuration

`KT_DocuSign_NC` was authenticated against DocuSign demo using OAuth 2.0.

Base URL:

```text
https://demo.docusign.net/restapi
```

DocuSign API account id used for the live run:

```text
faf1d738-3e7e-4692-8804-09f403a398b2
```

## Live Run Scripts

The live test was split across transactions because Salesforce does not allow DML before callouts in the same transaction.

1. Create B4 records:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_DocuSign_Live_Demo_Setup.apex
```

2. Create the DocuSign envelope:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_DocuSign_Live_Demo_CreateEnvelope.apex
```

3. Send the DocuSign envelope:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_DocuSign_Live_Demo_SendEnvelope.apex
```

4. After signer completion, retrieve the completed PDF:

```powershell
sf.cmd force apex execute --apexcodefile scripts/apex/KT_B4_DocuSign_Live_Demo_RetrieveCompleted.apex
```

## Evidence

- Onboarding: `a05g5000006yPHpAAM`
- Source content document: `069g5000004ek8HAAQ`
- Document request: `a03g500000GxI1JAAV`
- Vault: `a02g5000007zuinAAA`
- Signature request: `a07g500000Orn99AAB`
- Signer: `a08g5000006fK90AAE`
- Signer email: `ckumarnc@gmail.com`
- DocuSign envelope: `487d214f-37b6-8394-8175-0b3a4b5212aa`
- Retrieved completed content document: `069g5000004ekWTAAY`

## Final State

- Signature request status: `Fully Signed`
- Signer status: `Signed`
- Vault status: `Signed`
- Vault signature status: `Fully Signed`
- Signature request completed document id: `069g5000004ekWTAAY`
- Vault content document id: `069g5000004ekWTAAY`

## Notes

Salesforce blocks callouts after DML in the same Apex transaction. The working UAT scripts intentionally separate setup, create, send, and retrieval into separate transactions. `scripts/apex/KT_B4_DocuSign_Live_Demo_Send.apex` is now a safe send-only helper for an already-created envelope.
