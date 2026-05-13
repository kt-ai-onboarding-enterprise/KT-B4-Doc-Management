Map<String, Object> summary = new Map<String, Object>();
String stamp = String.valueOf(Datetime.now().getTime());

KT_Onboarding__c onboarding = new KT_Onboarding__c();
insert onboarding;
summary.put('onboardingId', onboarding.Id);
summary.put(
    'autoChecklistCount',
    [SELECT COUNT() FROM KT_Document_Request__c WHERE KT_Onboarding__c = :onboarding.Id]
);

KT_DocumentTemplate__c generationTemplate = new KT_DocumentTemplate__c(
    Template_Name__c = 'UAT Generation ' + stamp,
    Output_Format__c = 'PDF',
    Merge_Field_Map__c = 'Offer Letter for {{Id}}',
    Is_Active__c = true
);
insert generationTemplate;

KT_DocumentGeneratorService.KT_DocGenResult generationResult =
    KT_DocumentGeneratorService.generateDocument(onboarding.Id, generationTemplate.Id);
summary.put('generatedVaultId', generationResult.vaultEntryId);
summary.put('generatedContentDocumentId', generationResult.contentDocumentId);

KT_Document_Request__c uploadRequest = new KT_Document_Request__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Template__c = generationTemplate.Id,
    Status__c = 'Not Started',
    Document_Direction__c = 'Inbound',
    Is_Required__c = true
);
insert uploadRequest;

KT_DocumentUploadService.UploadResult uploadResult = KT_DocumentUploadService.uploadDocument(
    onboarding.Id,
    uploadRequest.Id,
    'uat-passport.pdf',
    EncodingUtil.base64Encode(Blob.valueOf('uat upload body')),
    'application/pdf'
);
summary.put('uploadSuccess', uploadResult.success);
summary.put('uploadVaultId', uploadResult.vaultEntryId);
summary.put('documentRequestRowCount', KT_DocumentChecklistService.getDocumentRequests(onboarding.Id).size());

ContentVersion historyVersionOne = new ContentVersion(
    Title = 'UAT Version History',
    PathOnClient = 'uat-history.pdf',
    VersionData = Blob.valueOf('history-v1')
);
insert historyVersionOne;
Id historyDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :historyVersionOne.Id
].ContentDocumentId;
insert new ContentVersion(
    Title = 'UAT Version History',
    PathOnClient = 'uat-history.pdf',
    ContentDocumentId = historyDocumentId,
    VersionData = Blob.valueOf('history-v2')
);
insert new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'UAT Version History',
    Content_Document_Id__c = historyDocumentId,
    Document_Type__c = 'Uploaded',
    Status__c = 'Draft',
    OCR_Status__c = 'Pending',
    Version_Number__c = 2,
    Signature_Status__c = 'Not Required'
);
summary.put(
    'versionHistoryCount',
    KT_DocumentVaultService.getVersionHistory(String.valueOf(historyDocumentId)).size()
);

ContentVersion sequentialVersion = new ContentVersion(
    Title = 'UAT Sequential Sign',
    PathOnClient = 'uat-sequential.pdf',
    VersionData = Blob.valueOf('sequential sign body')
);
insert sequentialVersion;
Id sequentialDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :sequentialVersion.Id
].ContentDocumentId;
KT_DocumentVault__c sequentialVault = new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'UAT Sequential Sign',
    Content_Document_Id__c = sequentialDocumentId,
    Document_Type__c = 'Generated',
    Status__c = 'Draft',
    OCR_Status__c = 'Not Required',
    Version_Number__c = 1,
    Signature_Status__c = 'Not Required'
);
insert sequentialVault;
KT_Document_Request__c sequentialRequest = new KT_Document_Request__c(
    KT_Onboarding__c = onboarding.Id,
    Status__c = 'Awaiting Signature',
    Document_Direction__c = 'Outbound',
    Is_Required__c = true,
    Document_Vault_Entry__c = sequentialVault.Id
);
insert sequentialRequest;

KT_ESignatureOrchestrator.SignatureConfig sequentialConfig =
    new KT_ESignatureOrchestrator.SignatureConfig();
sequentialConfig.signingProvider = 'KT Sign';
sequentialConfig.signingOrder = 'Sequential';
sequentialConfig.expiryDays = 7;
sequentialConfig.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();

KT_ESignatureOrchestrator.SignerConfig firstSignerConfig =
    new KT_ESignatureOrchestrator.SignerConfig();
firstSignerConfig.signerName = 'UAT First Signer';
firstSignerConfig.signerEmail = 'uat.first.' + stamp + '@example.com';
firstSignerConfig.signerRole = 'Onboardee';
firstSignerConfig.signingOrder = 1;
sequentialConfig.signers.add(firstSignerConfig);

KT_ESignatureOrchestrator.SignerConfig secondSignerConfig =
    new KT_ESignatureOrchestrator.SignerConfig();
secondSignerConfig.signerName = 'UAT Second Signer';
secondSignerConfig.signerEmail = 'uat.second.' + stamp + '@example.com';
secondSignerConfig.signerRole = 'HR Admin';
secondSignerConfig.signingOrder = 2;
sequentialConfig.signers.add(secondSignerConfig);

Id sequentialSignatureRequestId =
    KT_ESignatureOrchestrator.initiateSigningWorkflow(sequentialVault.Id, sequentialConfig);
List<KT_Signer__c> sequentialSigners = [
    SELECT Id, Status__c, Signing_Order__c
    FROM KT_Signer__c
    WHERE KT_Signature_Request__c = :sequentialSignatureRequestId
    ORDER BY Signing_Order__c ASC
];

KT_ESignatureOrchestrator.SignaturePayload firstSignaturePayload =
    new KT_ESignatureOrchestrator.SignaturePayload();
firstSignaturePayload.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('signature-one'));
firstSignaturePayload.ipAddress = '203.0.113.10';
firstSignaturePayload.deviceUserAgent = 'UAT Desktop Browser';
firstSignaturePayload.sessionToken = 'uat-token-1';
KT_ESignatureOrchestrator.handleSignatureComplete(sequentialSigners[0].Id, firstSignaturePayload);

sequentialSigners = [
    SELECT Id, Status__c, Signing_Order__c
    FROM KT_Signer__c
    WHERE KT_Signature_Request__c = :sequentialSignatureRequestId
    ORDER BY Signing_Order__c ASC
];
summary.put('secondSignerStatusAfterFirstSignature', sequentialSigners[1].Status__c);

KT_ESignatureOrchestrator.SignatureCompletionRequest secondCompletionRequest =
    new KT_ESignatureOrchestrator.SignatureCompletionRequest();
secondCompletionRequest.signerId = sequentialSigners[1].Id;
secondCompletionRequest.signatureBase64 = EncodingUtil.base64Encode(Blob.valueOf('signature-two'));
secondCompletionRequest.ipAddress = '203.0.113.11';
secondCompletionRequest.deviceUserAgent = 'UAT Mobile Browser';
KT_ESignatureOrchestrator.handleSignatureComplete(
    new List<KT_ESignatureOrchestrator.SignatureCompletionRequest>{ secondCompletionRequest }
);

KT_Signature_Request__c completedSequentialRequest = [
    SELECT Status__c, Completed_Signers__c, Total_Signers__c
    FROM KT_Signature_Request__c
    WHERE Id = :sequentialSignatureRequestId
];
KT_Document_Request__c completedDocumentRequest = [
    SELECT Status__c, Completed_Date__c
    FROM KT_Document_Request__c
    WHERE Id = :sequentialRequest.Id
];
summary.put('sequentialSignatureRequestStatus', completedSequentialRequest.Status__c);
summary.put('sequentialCompletedSigners', completedSequentialRequest.Completed_Signers__c);
summary.put('sequentialTotalSigners', completedSequentialRequest.Total_Signers__c);
summary.put('sequentialDocumentRequestStatus', completedDocumentRequest.Status__c);

ContentVersion delegationVersion = new ContentVersion(
    Title = 'UAT Delegation Sign',
    PathOnClient = 'uat-delegation.pdf',
    VersionData = Blob.valueOf('delegation sign body')
);
insert delegationVersion;
Id delegationDocumentId = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :delegationVersion.Id
].ContentDocumentId;
KT_DocumentVault__c delegationVault = new KT_DocumentVault__c(
    KT_Onboarding__c = onboarding.Id,
    Document_Name__c = 'UAT Delegation Sign',
    Content_Document_Id__c = delegationDocumentId,
    Document_Type__c = 'Generated',
    Status__c = 'Draft',
    OCR_Status__c = 'Not Required',
    Version_Number__c = 1,
    Signature_Status__c = 'Not Required'
);
insert delegationVault;

KT_ESignatureOrchestrator.SignatureConfig delegationConfig =
    new KT_ESignatureOrchestrator.SignatureConfig();
delegationConfig.signingProvider = 'KT Sign';
delegationConfig.signingOrder = 'Parallel';
delegationConfig.expiryDays = 7;
delegationConfig.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();

KT_ESignatureOrchestrator.SignerConfig delegationSignerOne =
    new KT_ESignatureOrchestrator.SignerConfig();
delegationSignerOne.signerName = 'Delegating Signer';
delegationSignerOne.signerEmail = 'delegate.original.' + stamp + '@example.com';
delegationSignerOne.signerRole = 'Onboardee';
delegationSignerOne.signingOrder = 1;
delegationConfig.signers.add(delegationSignerOne);

KT_ESignatureOrchestrator.SignerConfig delegationSignerTwo =
    new KT_ESignatureOrchestrator.SignerConfig();
delegationSignerTwo.signerName = 'Parallel Signer';
delegationSignerTwo.signerEmail = 'delegate.parallel.' + stamp + '@example.com';
delegationSignerTwo.signerRole = 'HR Admin';
delegationSignerTwo.signingOrder = 2;
delegationConfig.signers.add(delegationSignerTwo);

Id delegationSignatureRequestId =
    KT_ESignatureOrchestrator.initiateSigningWorkflow(delegationVault.Id, delegationConfig);
KT_Signer__c originalDelegationSigner = [
    SELECT Id
    FROM KT_Signer__c
    WHERE KT_Signature_Request__c = :delegationSignatureRequestId
    ORDER BY Signing_Order__c ASC
    LIMIT 1
];
Id delegateSignerId = KT_ESignatureOrchestrator.handleDelegation(
    originalDelegationSigner.Id,
    'delegate.replacement.' + stamp + '@example.com',
    'Out of office'
);
KT_ESignatureOrchestrator.handleExpiryEscalation(delegationSignatureRequestId);

KT_Signer__c delegatedOriginal = [
    SELECT Status__c, Delegated_To__c
    FROM KT_Signer__c
    WHERE Id = :originalDelegationSigner.Id
];
KT_Signer__c delegateSigner = [
    SELECT Status__c
    FROM KT_Signer__c
    WHERE Id = :delegateSignerId
];
KT_Signature_Request__c expiredDelegationRequest = [
    SELECT Status__c
    FROM KT_Signature_Request__c
    WHERE Id = :delegationSignatureRequestId
];
summary.put('delegatedOriginalStatus', delegatedOriginal.Status__c);
summary.put('delegatedTo', delegatedOriginal.Delegated_To__c);
summary.put('delegateSignerStatusAfterExpiry', delegateSigner.Status__c);
summary.put('delegationRequestStatusAfterExpiry', expiredDelegationRequest.Status__c);

List<KT_Onboarding__c> bulkOnboardings = new List<KT_Onboarding__c>();
for (Integer index = 0; index < 50; index++) {
    bulkOnboardings.add(new KT_Onboarding__c());
}
insert bulkOnboardings;

KT_DocumentTemplate__c bulkTemplate = new KT_DocumentTemplate__c(
    Template_Name__c = 'UAT Bulk ' + stamp,
    Output_Format__c = 'PDF',
    Merge_Field_Map__c = 'Bulk packet for {{Id}}',
    Is_Active__c = true
);
insert bulkTemplate;

List<Id> bulkOnboardingIds = new List<Id>();
for (KT_Onboarding__c bulkOnboarding : bulkOnboardings) {
    bulkOnboardingIds.add(bulkOnboarding.Id);
}

KT_BulkDocumentJobService.BulkJobLaunchResult bulkLaunchResult =
    KT_BulkDocumentJobService.launchBulkJob(
        bulkOnboardingIds,
        bulkTemplate.Id,
        'UAT 50 Record Bulk ' + stamp,
        null
    );
summary.put('bulkJobId', bulkLaunchResult.jobId);
summary.put('bulkApexJobId', bulkLaunchResult.apexJobId);
summary.put('bulkRecordCount', bulkOnboardingIds.size());

System.debug('UAT_SUMMARY::' + JSON.serialize(summary));
