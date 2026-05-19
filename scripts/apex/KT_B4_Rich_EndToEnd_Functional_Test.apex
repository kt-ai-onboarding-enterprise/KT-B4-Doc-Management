Map<String, Object> summary = new Map<String, Object>();
String stamp = String.valueOf(Datetime.now().getTime());
Id currentUserId = UserInfo.getUserId();

KT_Onboarding__c onboarding = new KT_Onboarding__c();
insert onboarding;
summary.put('onboardingId', onboarding.Id);

ContentVersion templateVersion = new ContentVersion(
    Title = 'B4 Rich Demo Template ' + stamp,
    PathOnClient = 'b4-rich-demo-template.docx',
    VersionData = Blob.valueOf('B4 rich demo merge template ' + stamp)
);
insert templateVersion;
Id templateDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :templateVersion.Id
    LIMIT 1
].ContentDocumentId;

KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
    Template_Name__c = 'B4 Rich HIPAA Employment Agreement ' + stamp,
    Domain__c = 'Healthcare',
    Persona__c = 'Clinical Staff',
    Language__c = 'English',
    Output_Format__c = 'PDF',
    Is_Active__c = true,
    Requires_Signature__c = true,
    Signature_Expiry_Days__c = 14,
    Signer_Roles__c = 'Onboardee;HR Admin;Compliance Officer',
    Regulatory_Framework__c = 'HIPAA;SOX',
    Template_Binary__c = templateDocumentId,
    Version__c = 1,
    Merge_Field_Map__c = JSON.serialize(new Map<String, Object>{
        'EmployeeName' => 'KT_Onboarding__c.Name',
        'DocumentType' => 'HIPAA Employment Agreement',
        'DemoStamp' => stamp,
        'RegulatoryFramework' => 'HIPAA;SOX'
    })
);
insert template;
summary.put('templateId', template.Id);

KT_Document_Request__c request = new KT_Document_Request__c(
    KT_Onboarding__c = onboarding.Id,
    Status__c = 'Not Started',
    Document_Direction__c = 'Inbound',
    Is_Required__c = true
);
insert request;
summary.put('documentRequestId', request.Id);

ContentVersion sourceVersion = new ContentVersion(
    Title = 'B4 Rich Demo Signed Source ' + stamp,
    PathOnClient = 'b4-rich-demo-source.pdf',
    VersionData = Blob.valueOf('B4 rich end to end source file ' + stamp)
);
insert sourceVersion;
Id sourceDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :sourceVersion.Id
    LIMIT 1
].ContentDocumentId;

KT_DocumentVault__c vault = new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'B4 Rich HIPAA/SOX Contract ' + stamp,
    Content_Document_Id__c = sourceDocumentId,
    Document_Type__c = 'Contract',
    Status__c = 'Draft',
    Document_Request__c = request.Id,
    OCR_Status__c = 'Review Required',
    Signature_Status__c = 'Pending',
    Version_Number__c = 3,
    Expiry_Date__c = Date.today().addDays(30),
    Regulatory_Tag__c = 'HIPAA;SOX;High Value Signature',
    Uploaded_By__c = currentUserId,
    Upload_Timestamp__c = System.now().addMinutes(-10)
);
insert vault;
summary.put('vaultId', vault.Id);

Database.SaveResult invalidTransition = Database.update(
    new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Fully Executed'),
    false
);
summary.put('invalidClmTransitionBlocked', !invalidTransition.isSuccess());
if (invalidTransition.isSuccess()) {
    throw new AuraHandledException('Rich E2E failed: invalid CLM transition was not blocked.');
}

update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Legal Review');
update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Counter-Sign');
update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Fully Executed');
summary.put('clmTaskCount', [SELECT COUNT() FROM Task WHERE WhatId = :onboarding.Id AND Subject LIKE 'CLM%']);

String extractedJson = JSON.serializePretty(new Map<String, Object>{
    'provider' => 'AWS Textract',
    'documentType' => 'Passport',
    'fields' => new Map<String, Object>{
        'FirstName' => new Map<String, Object>{ 'value' => 'Asha', 'confidence' => 0.94 },
        'LastName' => new Map<String, Object>{ 'value' => 'Raman', 'confidence' => 0.93 },
        'PassportNumber' => new Map<String, Object>{ 'value' => 'P-' + stamp.right(8), 'confidence' => 0.50 },
        'ExpiryDate' => new Map<String, Object>{ 'value' => String.valueOf(Date.today().addYears(5)), 'confidence' => 0.91 }
    },
    'reviewReason' => 'Passport number confidence below threshold'
});
KT_OCR_Job__c ocrJob = new KT_OCR_Job__c(
    KT_DocumentVault__c = vault.Id,
    KT_Onboarding__c = onboarding.Id,
    Status__c = 'Review Required',
    OCR_Provider__c = 'AWS Textract',
    Job_Id__c = 'aws-textract-rich-' + stamp,
    Document_Type_Detected__c = 'Passport',
    Confidence_Score__c = 0.50,
    Retry_Count__c = 2,
    Extracted_Fields__c = extractedJson
);
insert ocrJob;
summary.put('ocrJobId', ocrJob.Id);

SObject ocrEvent = Schema.getGlobalDescribe().get('KT_OCR_Job_Complete__e').newSObject();
ocrEvent.put('OcrJobId__c', String.valueOf(ocrJob.Id));
ocrEvent.put('OnboardingId__c', String.valueOf(onboarding.Id));
ocrEvent.put('DocumentType__c', 'Passport');
ocrEvent.put('Status__c', 'Review Required');
ocrEvent.put('ConfidenceScore__c', 0.50);
Database.SaveResult eventResult = EventBus.publish(ocrEvent);
summary.put('ocrCompleteEventPublished', eventResult.isSuccess());

KT_Bulk_Document_Job__c bulkJob = new KT_Bulk_Document_Job__c(
    Job_Name__c = 'B4 Rich Cohort Generation ' + stamp,
    Template__c = template.Id,
    Status__c = 'Partially Complete',
    Total_Records__c = 25,
    Processed__c = 20,
    Success_Count__c = 18,
    Failure_Count__c = 2,
    Failure_Summary__c = '2 records missing required merge data: PassportNumber, WorkLocation.',
    Apex_Job_Id__c = '707-rich-' + stamp.right(8),
    Initiated_By__c = currentUserId,
    Started_At__c = System.now().addMinutes(-25),
    Completed_At__c = System.now().addMinutes(-3)
);
insert bulkJob;
summary.put('bulkJobId', bulkJob.Id);

KT_HRCopilotOcrDiscrepancyAction.Request ocrActionRequest = new KT_HRCopilotOcrDiscrepancyAction.Request();
ocrActionRequest.onboardingId = onboarding.Id;
summary.put(
    'agentforceOcrDiscrepancyCount',
    KT_HRCopilotOcrDiscrepancyAction.run(new List<KT_HRCopilotOcrDiscrepancyAction.Request>{ ocrActionRequest })[0].discrepancyCount
);

KT_HRCopilotGapAnalysisAction.Request gapActionRequest = new KT_HRCopilotGapAnalysisAction.Request();
gapActionRequest.onboardingId = onboarding.Id;
summary.put(
    'agentforceGapCount',
    KT_HRCopilotGapAnalysisAction.run(new List<KT_HRCopilotGapAnalysisAction.Request>{ gapActionRequest })[0].missingCount
);

KT_HRCopilotBulkJobStatusAction.Request bulkActionRequest = new KT_HRCopilotBulkJobStatusAction.Request();
bulkActionRequest.jobId = bulkJob.Id;
KT_HRCopilotBulkJobStatusAction.Result bulkActionResult =
    KT_HRCopilotBulkJobStatusAction.run(new List<KT_HRCopilotBulkJobStatusAction.Request>{ bulkActionRequest })[0];
summary.put('agentforceBulkStatus', bulkActionResult.status);
summary.put('agentforceBulkProgressPercent', bulkActionResult.progressPercent);

KT_ESignatureOrchestrator.SignatureConfig signatureConfig = new KT_ESignatureOrchestrator.SignatureConfig();
signatureConfig.signingProvider = 'KT Sign';
signatureConfig.signingOrder = 'Sequential';
signatureConfig.expiryDays = 14;
signatureConfig.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();

KT_ESignatureOrchestrator.SignerConfig signerOne = new KT_ESignatureOrchestrator.SignerConfig();
signerOne.signerName = 'Asha Raman';
signerOne.signerEmail = 'asha.raman.rich.' + stamp + '@example.com';
signerOne.signerRole = 'Onboardee';
signerOne.signingOrder = 1;
signatureConfig.signers.add(signerOne);

KT_ESignatureOrchestrator.SignerConfig signerTwo = new KT_ESignatureOrchestrator.SignerConfig();
signerTwo.signerName = 'Meera Compliance';
signerTwo.signerEmail = 'meera.compliance.rich.' + stamp + '@example.com';
signerTwo.signerRole = 'Compliance Officer';
signerTwo.signingOrder = 2;
signatureConfig.signers.add(signerTwo);

Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, signatureConfig);
summary.put('signatureRequestId', signatureRequestId);

KT_AXLSigningTileService.TileResult firstTile = KT_AXLSigningTileService.buildSigningTile(signatureRequestId, 'Slack');
summary.put('firstAxlTileChannel', firstTile.channel);
summary.put('firstAxlTileHasUrl', !String.isBlank(firstTile.signingUrl));

KT_ESignatureOrchestrator.SignaturePayload firstPayload = new KT_ESignatureOrchestrator.SignaturePayload();
firstPayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('rich first signer signature ' + stamp));
firstPayload.ipAddress = '203.0.113.61';
firstPayload.deviceUserAgent = 'B4 Rich Demo Browser / first signer';
firstPayload.latitude = 37.7749;
firstPayload.longitude = -122.4194;
Boolean firstWorkflowComplete = KT_ESignatureOrchestrator.handleSignatureComplete(firstTile.signerId, firstPayload);
summary.put('firstSignerWorkflowComplete', firstWorkflowComplete);

KT_AXLSigningTileService.TileResult secondTile = KT_AXLSigningTileService.buildSigningTile(signatureRequestId, 'Teams');
summary.put('secondAxlTileChannel', secondTile.channel);
summary.put('secondAxlTileHasUrl', !String.isBlank(secondTile.signingUrl));

KT_HRCopilotSigningEscalationAction.Request escalationRequest = new KT_HRCopilotSigningEscalationAction.Request();
escalationRequest.signatureRequestId = signatureRequestId;
summary.put(
    'agentforceSigningPendingCount',
    KT_HRCopilotSigningEscalationAction.run(new List<KT_HRCopilotSigningEscalationAction.Request>{ escalationRequest })[0].pendingSignerCount
);

Boolean trustedGateBlocked = false;
try {
    KT_ESignatureOrchestrator.SignaturePayload blockedPayload = new KT_ESignatureOrchestrator.SignaturePayload();
    blockedPayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('blocked final rich signature'));
    blockedPayload.ipAddress = '203.0.113.62';
    blockedPayload.deviceUserAgent = 'B4 Rich Demo Browser / blocked final signer';
    blockedPayload.latitude = 40.7128;
    blockedPayload.longitude = -74.0060;
    KT_ESignatureOrchestrator.handleSignatureComplete(secondTile.signerId, blockedPayload);
} catch (Exception ex) {
    trustedGateBlocked = true;
}
summary.put('trustedIdentityGateBlockedFinalSignature', trustedGateBlocked);
if (!trustedGateBlocked) {
    throw new AuraHandledException('Rich E2E failed: trusted identity gate did not block final signature.');
}

KT_ESignatureOrchestrator.TrustedAgentIdentityResult trustedResult =
    KT_ESignatureOrchestrator.verifyTrustedAgentIdentity(signatureRequestId, 'PUSH-BIOMETRIC-RICH-' + stamp, true);
summary.put('trustedIdentityStatus', trustedResult.status);

KT_ESignatureOrchestrator.SignaturePayload finalPayload = new KT_ESignatureOrchestrator.SignaturePayload();
finalPayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('rich final signer signature ' + stamp));
finalPayload.ipAddress = '203.0.113.63';
finalPayload.deviceUserAgent = 'B4 Rich Demo Browser / final signer';
finalPayload.latitude = 40.7128;
finalPayload.longitude = -74.0060;
Boolean workflowComplete = KT_ESignatureOrchestrator.handleSignatureComplete(secondTile.signerId, finalPayload);
summary.put('ktSignWorkflowComplete', workflowComplete);

KT_Signature_Request__c docusignRequest = new KT_Signature_Request__c(
    KT_DocumentVault__c = vault.Id,
    KT_Onboarding__c = onboarding.Id,
    Signing_Provider__c = 'DocuSign',
    Signing_Order__c = 'Sequential',
    Status__c = 'In Progress',
    Total_Signers__c = 1,
    Completed_Signers__c = 0,
    Expiry_Date__c = Date.today().addDays(10),
    External_Envelope_Id__c = 'ds-rich-envelope-' + stamp,
    Requires_Trusted_Agent_Identity__c = false,
    Trusted_Agent_Verification_Status__c = 'Not Required'
);
insert docusignRequest;
KT_Signer__c docusignSigner = new KT_Signer__c(
    KT_Signature_Request__c = docusignRequest.Id,
    Signer_Name__c = 'DocuSign Demo Signer',
    Signer_Email__c = 'docusign.rich.' + stamp + '@example.com',
    Signer_Role__c = 'HR Admin',
    Signing_Order__c = 1,
    Status__c = 'Invitation Sent',
    IP_Address__c = '203.0.113.71',
    Device_User_Agent__c = 'DocuSign Rich Demo'
);
insert docusignSigner;
insert new KT_Signature_Audit__c(
    KT_Signature_Request__c = docusignRequest.Id,
    KT_Signer__c = docusignSigner.Id,
    Event_Type__c = 'Invitation Sent',
    Event_Timestamp__c = System.now(),
    IP_Address__c = '203.0.113.71',
    Device_User_Agent__c = 'DocuSign Rich Demo',
    Hash_Value__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf('docusign-rich-' + stamp)))
);
summary.put('docuSignSignatureRequestId', docusignRequest.Id);

KT_Signature_Request__c adobeRequest = new KT_Signature_Request__c(
    KT_DocumentVault__c = vault.Id,
    KT_Onboarding__c = onboarding.Id,
    Signing_Provider__c = 'Adobe Sign',
    Signing_Order__c = 'Parallel',
    Status__c = 'Fully Signed',
    Total_Signers__c = 1,
    Completed_Signers__c = 1,
    Expiry_Date__c = Date.today().addDays(10),
    External_Envelope_Id__c = 'adobe-rich-agreement-' + stamp,
    Completed_Document_Id__c = sourceDocumentId,
    Requires_Trusted_Agent_Identity__c = false,
    Trusted_Agent_Verification_Status__c = 'Not Required'
);
insert adobeRequest;
KT_Signer__c adobeSigner = new KT_Signer__c(
    KT_Signature_Request__c = adobeRequest.Id,
    Signer_Name__c = 'Adobe Demo Signer',
    Signer_Email__c = 'adobe.rich.' + stamp + '@example.com',
    Signer_Role__c = 'Legal Counsel',
    Signing_Order__c = 1,
    Status__c = 'Signed',
    Signed_At__c = System.now(),
    IP_Address__c = '203.0.113.72',
    Device_User_Agent__c = 'Adobe Sign Rich Demo'
);
insert adobeSigner;
insert new KT_Signature_Audit__c(
    KT_Signature_Request__c = adobeRequest.Id,
    KT_Signer__c = adobeSigner.Id,
    Event_Type__c = 'Completed',
    Event_Timestamp__c = System.now(),
    IP_Address__c = '203.0.113.72',
    Device_User_Agent__c = 'Adobe Sign Rich Demo',
    Hash_Value__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf('adobe-rich-' + stamp)))
);
summary.put('adobeSignatureRequestId', adobeRequest.Id);

KT_ComplianceMissingDocsAction.Request missingDocsRequest = new KT_ComplianceMissingDocsAction.Request();
missingDocsRequest.onboardingId = onboarding.Id;
summary.put(
    'complianceMissingDocsCount',
    KT_ComplianceMissingDocsAction.run(new List<KT_ComplianceMissingDocsAction.Request>{ missingDocsRequest })[0].missingCount
);

KT_ComplianceExpiringDocsAction.Request expiringDocsRequest = new KT_ComplianceExpiringDocsAction.Request();
expiringDocsRequest.onboardingId = onboarding.Id;
expiringDocsRequest.daysAhead = 90;
summary.put(
    'complianceExpiringDocsCount',
    KT_ComplianceExpiringDocsAction.run(new List<KT_ComplianceExpiringDocsAction.Request>{ expiringDocsRequest })[0].expiringCount
);

KT_ComplianceAuditReportAction.Request auditActionRequest = new KT_ComplianceAuditReportAction.Request();
auditActionRequest.onboardingId = onboarding.Id;
KT_ComplianceAuditReportAction.Result auditActionResult =
    KT_ComplianceAuditReportAction.run(new List<KT_ComplianceAuditReportAction.Request>{ auditActionRequest })[0];
summary.put('auditExportVaultId', auditActionResult.vaultEntryId);
summary.put('auditExportContentDocumentId', auditActionResult.contentDocumentId);
summary.put('auditExportHashPresent', !String.isBlank(auditActionResult.certificationHash));

summary.put('signatureRequestCount', [SELECT COUNT() FROM KT_Signature_Request__c WHERE KT_Onboarding__c = :onboarding.Id]);
summary.put('signerCount', [SELECT COUNT() FROM KT_Signer__c WHERE KT_Signature_Request__r.KT_Onboarding__c = :onboarding.Id]);
summary.put('signatureAuditCount', [SELECT COUNT() FROM KT_Signature_Audit__c WHERE KT_Signature_Request__r.KT_Onboarding__c = :onboarding.Id]);
summary.put('vaultCount', [SELECT COUNT() FROM KT_DocumentVault__c WHERE KT_Onboarding__c = :onboarding.Id]);
summary.put('documentRequestFinalStatus', [SELECT Status__c FROM KT_Document_Request__c WHERE Id = :request.Id].Status__c);

System.debug('KT_B4_RICH_E2E_FUNCTIONAL_SUMMARY::' + JSON.serialize(summary));
