Map<String, Object> summary = new Map<String, Object>();
String stamp = String.valueOf(Datetime.now().getTime());

KT_Onboarding__c onboarding = new KT_Onboarding__c();
insert onboarding;
summary.put('onboardingId', onboarding.Id);

ContentVersion sourceVersion = new ContentVersion(
    Title = 'Sprint 6 UAT Contract Source ' + stamp,
    PathOnClient = 'sprint6-uat-contract.pdf',
    VersionData = Blob.valueOf('sprint 6 uat contract source')
);
insert sourceVersion;
Id sourceDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :sourceVersion.Id
    LIMIT 1
].ContentDocumentId;

SObject documentRequest = Schema.getGlobalDescribe().get('KT_Document_Request__c').newSObject();
documentRequest.put('KT_Onboarding__c', onboarding.Id);
documentRequest.put('Status__c', 'Awaiting Signature');
documentRequest.put('Document_Direction__c', 'Outbound');
documentRequest.put('Is_Required__c', true);
insert documentRequest;

SObject contractVault = Schema.getGlobalDescribe().get('KT_DocumentVault__c').newSObject();
contractVault.put('KT_Onboarding__c', onboarding.Id);
contractVault.put('Document_Name__c', 'Sprint 6 UAT Contract');
contractVault.put('Content_Document_Id__c', sourceDocumentId);
contractVault.put('Document_Type__c', 'Contract');
contractVault.put('Status__c', 'Draft');
contractVault.put('Document_Request__c', documentRequest.get('Id'));
contractVault.put('OCR_Status__c', 'Processing');
contractVault.put('Version_Number__c', 1);
contractVault.put('Signature_Status__c', 'Pending');
contractVault.put('Regulatory_Tag__c', 'UAT');
insert contractVault;
Id contractVaultId = (Id) contractVault.get('Id');
summary.put('contractVaultId', contractVaultId);

SObject invalidUpdate = Schema.getGlobalDescribe().get('KT_DocumentVault__c').newSObject(contractVaultId);
invalidUpdate.put('Status__c', 'Fully Executed');
Database.SaveResult invalidTransition = Database.update(invalidUpdate, false);
summary.put('invalidClmTransitionBlocked', !invalidTransition.isSuccess());

SObject legalReviewUpdate = Schema.getGlobalDescribe().get('KT_DocumentVault__c').newSObject(contractVaultId);
legalReviewUpdate.put('Status__c', 'Legal Review');
update legalReviewUpdate;
SObject counterSignUpdate = Schema.getGlobalDescribe().get('KT_DocumentVault__c').newSObject(contractVaultId);
counterSignUpdate.put('Status__c', 'Counter-Sign');
update counterSignUpdate;
SObject fullyExecutedUpdate = Schema.getGlobalDescribe().get('KT_DocumentVault__c').newSObject(contractVaultId);
fullyExecutedUpdate.put('Status__c', 'Fully Executed');
update fullyExecutedUpdate;
summary.put(
    'clmTaskCount',
    [SELECT COUNT() FROM Task WHERE WhatId = :onboarding.Id AND Subject LIKE 'CLM%']
);

SObject ocrJob = Schema.getGlobalDescribe().get('KT_OCR_Job__c').newSObject();
ocrJob.put('KT_DocumentVault__c', contractVaultId);
ocrJob.put('KT_Onboarding__c', onboarding.Id);
ocrJob.put('Status__c', 'Review Required');
ocrJob.put('OCR_Provider__c', 'AWS Textract');
ocrJob.put('Job_Id__c', 'sprint6-uat-ocr-' + stamp);
ocrJob.put('Document_Type_Detected__c', 'Contract');
ocrJob.put('Confidence_Score__c', 0.91);
ocrJob.put('Retry_Count__c', 1);
ocrJob.put('Extracted_Fields__c', '{"ContractNumber":"UAT-' + stamp + '","Confidence":0.91}');
insert ocrJob;
summary.put('ocrJobId', ocrJob.get('Id'));

SObject docuSignRequest = Schema.getGlobalDescribe().get('KT_Signature_Request__c').newSObject();
docuSignRequest.put('KT_DocumentVault__c', contractVaultId);
docuSignRequest.put('KT_Onboarding__c', onboarding.Id);
docuSignRequest.put('Signing_Provider__c', 'DocuSign');
docuSignRequest.put('Status__c', 'In Progress');
docuSignRequest.put('Signing_Order__c', 'Sequential');
docuSignRequest.put('Total_Signers__c', 1);
docuSignRequest.put('Completed_Signers__c', 0);
docuSignRequest.put('Expiry_Date__c', Date.today().addDays(7));
docuSignRequest.put('External_Envelope_Id__c', 'uat-docusign-' + stamp);
insert docuSignRequest;

SObject docuSigner = Schema.getGlobalDescribe().get('KT_Signer__c').newSObject();
docuSigner.put('KT_Signature_Request__c', docuSignRequest.get('Id'));
docuSigner.put('Signer_Name__c', 'Sprint 6 DocuSign UAT Signer');
docuSigner.put('Signer_Email__c', 'sprint6.docusign.' + stamp + '@example.com');
docuSigner.put('Signer_Role__c', 'Onboardee');
docuSigner.put('Signing_Order__c', 1);
docuSigner.put('Status__c', 'Invitation Sent');
insert docuSigner;

SObject docuAudit = Schema.getGlobalDescribe().get('KT_Signature_Audit__c').newSObject();
docuAudit.put('KT_Signature_Request__c', docuSignRequest.get('Id'));
docuAudit.put('KT_Signer__c', docuSigner.get('Id'));
docuAudit.put('Event_Type__c', 'Invitation Sent');
docuAudit.put('Event_Timestamp__c', System.now());
docuAudit.put('IP_Address__c', '203.0.113.21');
docuAudit.put('Device_User_Agent__c', 'Sprint 6 UAT');
docuAudit.put('Hash_Value__c', EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf('docusign-' + stamp))));
insert docuAudit;
summary.put('docuSignSignatureRequestId', docuSignRequest.get('Id'));

SObject adobeRequest = Schema.getGlobalDescribe().get('KT_Signature_Request__c').newSObject();
adobeRequest.put('KT_DocumentVault__c', contractVaultId);
adobeRequest.put('KT_Onboarding__c', onboarding.Id);
adobeRequest.put('Signing_Provider__c', 'Adobe Sign');
adobeRequest.put('Status__c', 'Fully Signed');
adobeRequest.put('Signing_Order__c', 'Sequential');
adobeRequest.put('Total_Signers__c', 1);
adobeRequest.put('Completed_Signers__c', 1);
adobeRequest.put('Expiry_Date__c', Date.today().addDays(7));
adobeRequest.put('External_Envelope_Id__c', 'uat-adobe-' + stamp);
adobeRequest.put('Completed_Document_Id__c', sourceDocumentId);
insert adobeRequest;

SObject adobeSigner = Schema.getGlobalDescribe().get('KT_Signer__c').newSObject();
adobeSigner.put('KT_Signature_Request__c', adobeRequest.get('Id'));
adobeSigner.put('Signer_Name__c', 'Sprint 6 Adobe UAT Signer');
adobeSigner.put('Signer_Email__c', 'sprint6.adobe.' + stamp + '@example.com');
adobeSigner.put('Signer_Role__c', 'Onboardee');
adobeSigner.put('Signing_Order__c', 1);
adobeSigner.put('Status__c', 'Signed');
adobeSigner.put('Signed_At__c', System.now());
insert adobeSigner;

SObject adobeAudit = Schema.getGlobalDescribe().get('KT_Signature_Audit__c').newSObject();
adobeAudit.put('KT_Signature_Request__c', adobeRequest.get('Id'));
adobeAudit.put('KT_Signer__c', adobeSigner.get('Id'));
adobeAudit.put('Event_Type__c', 'Completed');
adobeAudit.put('Event_Timestamp__c', System.now());
adobeAudit.put('IP_Address__c', '203.0.113.22');
adobeAudit.put('Device_User_Agent__c', 'Sprint 6 UAT');
adobeAudit.put('Hash_Value__c', EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf('adobe-' + stamp))));
insert adobeAudit;
summary.put('adobeSignatureRequestId', adobeRequest.get('Id'));

KT_AuditExportService.AuditExportResult auditResult =
    KT_AuditExportService.exportAuditPackage(onboarding.Id);
summary.put('auditExportVaultId', auditResult.vaultEntryId);
summary.put('auditExportContentDocumentId', auditResult.contentDocumentId);
summary.put('auditExportDocumentCount', auditResult.documentCount);
summary.put('auditExportSignatureAuditCount', auditResult.signatureAuditCount);
summary.put('auditExportOcrJobCount', auditResult.ocrJobCount);

System.debug('SPRINT6_UAT_SUMMARY::' + JSON.serialize(summary));
