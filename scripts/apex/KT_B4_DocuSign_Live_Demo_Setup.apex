String signerName = 'chethan';
String signerEmail = 'ckumarnc@gmail.com';
String stamp = String.valueOf(Datetime.now().getTime());

Map<String, Object> summary = new Map<String, Object>();

KT_Onboarding__c onboarding = new KT_Onboarding__c();
insert onboarding;
summary.put('onboardingId', onboarding.Id);

String pdfBody =
    '%PDF-1.4\n'
    + '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    + '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    + '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n'
    + '4 0 obj\n<< /Length 139 >>\nstream\nBT\n/F1 18 Tf\n72 720 Td\n(KT B4 DocuSign Live Demo) Tj\n0 -32 Td\n/F1 12 Tf\n(Please sign this demo onboarding document.) Tj\n0 -24 Td\n(Signature area below.) Tj\nET\nendstream\nendobj\n'
    + '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n'
    + 'xref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000241 00000 n \n0000000430 00000 n \n'
    + 'trailer\n<< /Root 1 0 R /Size 6 >>\nstartxref\n500\n%%EOF';

ContentVersion sourceVersion = new ContentVersion(
    Title = 'KT B4 DocuSign Live Demo ' + stamp,
    PathOnClient = 'kt-b4-docusign-live-demo.pdf',
    VersionData = Blob.valueOf(pdfBody)
);
insert sourceVersion;
Id contentDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :sourceVersion.Id
    LIMIT 1
].ContentDocumentId;
summary.put('sourceContentDocumentId', contentDocumentId);

KT_Document_Request__c documentRequest = new KT_Document_Request__c(
    KT_Onboarding__c = onboarding.Id,
    Status__c = 'Awaiting Signature',
    Document_Direction__c = 'Outbound',
    Is_Required__c = true
);
insert documentRequest;
summary.put('documentRequestId', documentRequest.Id);

KT_DocumentVault__c vault = new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'KT B4 DocuSign Live Demo ' + stamp,
    Content_Document_Id__c = contentDocumentId,
    Document_Type__c = 'Contract',
    Status__c = 'Draft',
    Document_Request__c = documentRequest.Id,
    OCR_Status__c = 'Not Required',
    Signature_Status__c = 'Pending',
    Version_Number__c = 1,
    Expiry_Date__c = Date.today().addDays(14),
    Regulatory_Tag__c = 'DocuSign Demo'
);
insert vault;
summary.put('vaultId', vault.Id);

KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
    KT_DocumentVault__c = vault.Id,
    KT_Onboarding__c = onboarding.Id,
    Signing_Provider__c = 'DocuSign',
    Status__c = 'Configured',
    Signing_Order__c = 'Sequential',
    Total_Signers__c = 1,
    Completed_Signers__c = 0,
    Expiry_Date__c = Date.today().addDays(14),
    Requires_Trusted_Agent_Identity__c = false,
    Trusted_Agent_Verification_Status__c = 'Not Required'
);
insert signatureRequest;
summary.put('signatureRequestId', signatureRequest.Id);

KT_Signer__c signer = new KT_Signer__c(
    KT_Signature_Request__c = signatureRequest.Id,
    Signer_Name__c = signerName,
    Signer_Email__c = signerEmail,
    Signer_Role__c = 'Onboardee',
    Signing_Order__c = 1,
    Status__c = 'Pending'
);
insert signer;
summary.put('signerId', signer.Id);

System.debug('KT_B4_DOCUSIGN_LIVE_DEMO_SETUP::' + JSON.serialize(summary));
