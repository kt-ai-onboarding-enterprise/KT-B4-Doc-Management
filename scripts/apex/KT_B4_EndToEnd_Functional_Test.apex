Map<String, Object> summary = new Map<String, Object>();
String stamp = String.valueOf(Datetime.now().getTime());

KT_Onboarding__c onboarding = new KT_Onboarding__c();
insert onboarding;
summary.put('onboardingId', onboarding.Id);

KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
    Template_Name__c = 'E2E Functional Template ' + stamp,
    Output_Format__c = 'PDF',
    Is_Active__c = true,
    Regulatory_Framework__c = 'HIPAA',
    Merge_Field_Map__c = '{"Employee":"Name"}'
);
insert template;
summary.put('templateId', template.Id);

Schema.SObjectType requestType = Schema.getGlobalDescribe().get('KT_Document_Request__c');
Map<String, Schema.SObjectField> requestFields = requestType.getDescribe().fields.getMap();
SObject request = requestType.newSObject();
request.put('KT_Onboarding__c', onboarding.Id);
request.put('Status__c', 'Not Started');
if (requestFields.containsKey('Document_Direction__c')) {
    request.put('Document_Direction__c', 'Inbound');
}
if (requestFields.containsKey('Is_Required__c')) {
    request.put('Is_Required__c', true);
}
if (requestFields.containsKey('Due_Date__c')) {
    request.put('Due_Date__c', Date.today().addDays(7));
}
if (requestFields.containsKey('Document_Template__c')) {
    request.put('Document_Template__c', template.Id);
}
insert request;
summary.put('documentRequestId', request.get('Id'));

ContentVersion sourceVersion = new ContentVersion(
    Title = 'B4 E2E Source ' + stamp,
    PathOnClient = 'b4-e2e-source.pdf',
    VersionData = Blob.valueOf('B4 end to end source ' + stamp)
);
insert sourceVersion;
Id contentDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :sourceVersion.Id
    LIMIT 1
].ContentDocumentId;

KT_DocumentVault__c vault = new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'B4 E2E HIPAA Contract',
    Content_Document_Id__c = contentDocumentId,
    Document_Type__c = 'Contract',
    Status__c = 'Draft',
    Document_Request__c = (Id) request.get('Id'),
    OCR_Status__c = 'Review Required',
    Signature_Status__c = 'Pending',
    Version_Number__c = 1,
    Expiry_Date__c = Date.today().addDays(30),
    Regulatory_Tag__c = 'HIPAA'
);
insert vault;
summary.put('vaultId', vault.Id);

KT_DocumentVault__c invalidStatus = new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Fully Executed');
Database.SaveResult invalidTransition = Database.update(invalidStatus, false);
summary.put('invalidClmTransitionBlocked', !invalidTransition.isSuccess());
if (invalidTransition.isSuccess()) {
    throw new AuraHandledException('E2E failed: invalid CLM transition was not blocked.');
}

update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Legal Review');
update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Counter-Sign');
update new KT_DocumentVault__c(Id = vault.Id, Status__c = 'Fully Executed');
summary.put('clmTaskCount', [SELECT COUNT() FROM Task WHERE WhatId = :onboarding.Id AND Subject LIKE 'CLM%']);

KT_OCR_Job__c ocrJob = new KT_OCR_Job__c(
    KT_DocumentVault__c = vault.Id,
    KT_Onboarding__c = onboarding.Id,
    Status__c = 'Review Required',
    OCR_Provider__c = 'AWS Textract',
    Job_Id__c = 'b4-e2e-ocr-' + stamp,
    Document_Type_Detected__c = 'Passport',
    Confidence_Score__c = 0.50,
    Retry_Count__c = 0,
    Extracted_Fields__c = '{"PassportNumber":"E2E-' + stamp + '"}'
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

Schema.SObjectType bulkType = Schema.getGlobalDescribe().get('KT_Bulk_Document_Job__c');
Map<String, Schema.SObjectField> bulkFields = bulkType.getDescribe().fields.getMap();
Boolean bulkRuntimeFieldsAvailable = bulkFields.containsKey('status__c')
    && bulkFields.containsKey('total_records__c')
    && bulkFields.containsKey('processed__c')
    && bulkFields.containsKey('success_count__c')
    && bulkFields.containsKey('failure_count__c')
    && bulkFields.containsKey('started_at__c');
SObject bulkJob;
if (bulkRuntimeFieldsAvailable) {
    bulkJob = bulkType.newSObject();
    bulkJob.put('Job_Name__c', 'B4 E2E Bulk ' + stamp);
    bulkJob.put('Status__c', 'Running');
    bulkJob.put('Total_Records__c', 10);
    bulkJob.put('Processed__c', 4);
    bulkJob.put('Success_Count__c', 4);
    bulkJob.put('Failure_Count__c', 0);
    bulkJob.put('Started_At__c', System.now());
    if (bulkFields.containsKey('template__c')) {
        bulkJob.put('Template__c', template.Id);
    }
    insert bulkJob;
    summary.put('bulkJobId', bulkJob.get('Id'));
} else {
    summary.put('bulkRuntimeSkipped', true);
    summary.put('bulkRuntimeFieldCount', bulkFields.size());
}

KT_HRCopilotOcrDiscrepancyAction.Request ocrActionRequest = new KT_HRCopilotOcrDiscrepancyAction.Request();
ocrActionRequest.onboardingId = onboarding.Id;
Integer ocrDiscrepancyCount = KT_HRCopilotOcrDiscrepancyAction.run(
    new List<KT_HRCopilotOcrDiscrepancyAction.Request>{ ocrActionRequest }
)[0].discrepancyCount;
summary.put('agentforceOcrDiscrepancyCount', ocrDiscrepancyCount);

KT_HRCopilotGapAnalysisAction.Request gapActionRequest = new KT_HRCopilotGapAnalysisAction.Request();
gapActionRequest.onboardingId = onboarding.Id;
Integer gapCount = KT_HRCopilotGapAnalysisAction.run(
    new List<KT_HRCopilotGapAnalysisAction.Request>{ gapActionRequest }
)[0].missingCount;
summary.put('agentforceGapCount', gapCount);

if (bulkRuntimeFieldsAvailable) {
    KT_HRCopilotBulkJobStatusAction.Request bulkActionRequest = new KT_HRCopilotBulkJobStatusAction.Request();
    bulkActionRequest.jobId = (Id) bulkJob.get('Id');
    KT_HRCopilotBulkJobStatusAction.Result bulkActionResult = KT_HRCopilotBulkJobStatusAction.run(
        new List<KT_HRCopilotBulkJobStatusAction.Request>{ bulkActionRequest }
    )[0];
    summary.put('agentforceBulkStatus', bulkActionResult.status);
    summary.put('agentforceBulkProgressPercent', bulkActionResult.progressPercent);
}

KT_ESignatureOrchestrator.SignatureConfig signatureConfig = new KT_ESignatureOrchestrator.SignatureConfig();
signatureConfig.signingProvider = 'KT Sign';
signatureConfig.signingOrder = 'Sequential';
signatureConfig.expiryDays = 7;
signatureConfig.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();
KT_ESignatureOrchestrator.SignerConfig signerConfig = new KT_ESignatureOrchestrator.SignerConfig();
signerConfig.signerName = 'B4 E2E Signer';
signerConfig.signerEmail = 'b4.e2e.' + stamp + '@example.com';
signerConfig.signerRole = 'Onboardee';
signerConfig.signingOrder = 1;
signatureConfig.signers.add(signerConfig);

Id signatureRequestId = KT_ESignatureOrchestrator.initiateSigningWorkflow(vault.Id, signatureConfig);
summary.put('signatureRequestId', signatureRequestId);

KT_AXLSigningTileService.TileResult axlTile = KT_AXLSigningTileService.buildSigningTile(signatureRequestId, 'Teams');
summary.put('axlTileChannel', axlTile.channel);
summary.put('axlTileHasSigningUrl', !String.isBlank(axlTile.signingUrl));

KT_HRCopilotSigningEscalationAction.Request escalationRequest = new KT_HRCopilotSigningEscalationAction.Request();
escalationRequest.signatureRequestId = signatureRequestId;
summary.put(
    'agentforceSigningPendingCount',
    KT_HRCopilotSigningEscalationAction.run(
        new List<KT_HRCopilotSigningEscalationAction.Request>{ escalationRequest }
    )[0].pendingSignerCount
);

Boolean trustedGateBlocked = false;
try {
    KT_ESignatureOrchestrator.SignaturePayload blockedPayload = new KT_ESignatureOrchestrator.SignaturePayload();
    blockedPayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('blocked signature'));
    blockedPayload.ipAddress = '203.0.113.50';
    blockedPayload.deviceUserAgent = 'B4 E2E blocked';
    KT_ESignatureOrchestrator.handleSignatureComplete(axlTile.signerId, blockedPayload);
} catch (Exception ex) {
    trustedGateBlocked = true;
}
summary.put('trustedIdentityGateBlockedFinalSignature', trustedGateBlocked);
if (!trustedGateBlocked) {
    throw new AuraHandledException('E2E failed: trusted identity gate did not block final signature.');
}

KT_ESignatureOrchestrator.TrustedAgentIdentityResult trustedResult =
    KT_ESignatureOrchestrator.verifyTrustedAgentIdentity(signatureRequestId, 'E2E-TRUST-' + stamp, true);
summary.put('trustedIdentityStatus', trustedResult.status);

KT_ESignatureOrchestrator.SignaturePayload completePayload = new KT_ESignatureOrchestrator.SignaturePayload();
completePayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('completed signature'));
completePayload.ipAddress = '203.0.113.51';
completePayload.deviceUserAgent = 'B4 E2E complete';
Boolean workflowComplete = KT_ESignatureOrchestrator.handleSignatureComplete(axlTile.signerId, completePayload);
summary.put('ktSignWorkflowComplete', workflowComplete);

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
KT_ComplianceAuditReportAction.Result auditActionResult = KT_ComplianceAuditReportAction.run(
    new List<KT_ComplianceAuditReportAction.Request>{ auditActionRequest }
)[0];
summary.put('auditExportVaultId', auditActionResult.vaultEntryId);
summary.put('auditExportContentDocumentId', auditActionResult.contentDocumentId);
summary.put('auditExportHashPresent', !String.isBlank(auditActionResult.certificationHash));

summary.put('signatureAuditCount', [
    SELECT COUNT()
    FROM KT_Signature_Audit__c
    WHERE KT_Signature_Request__c = :signatureRequestId
]);

System.debug('KT_B4_E2E_FUNCTIONAL_SUMMARY::' + JSON.serialize(summary));
