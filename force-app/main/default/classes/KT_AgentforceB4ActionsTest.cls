@IsTest
private class KT_AgentforceB4ActionsTest {
    private static Id createContentDocument(String title) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(title)
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    private static KT_DocumentTemplate__c createComplianceTemplate() {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Agentforce Compliance Template',
            Output_Format__c = 'PDF',
            Is_Active__c = true,
            Regulatory_Framework__c = 'HIPAA'
        );
        insert template;
        return template;
    }

    @IsTest
    static void hrCopilotActionsReturnSummaries() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        KT_DocumentTemplate__c template = createComplianceTemplate();
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true,
            Due_Date__c = Date.today()
        );
        insert request;

        KT_DocumentVault__c vault = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Agentforce Contract',
            Content_Document_Id__c = createContentDocument('agentforce-contract'),
            Document_Type__c = 'Contract',
            Status__c = 'Pending Signature',
            OCR_Status__c = 'Review Required',
            Signature_Status__c = 'Pending',
            Version_Number__c = 1,
            Expiry_Date__c = Date.today().addDays(30),
            Regulatory_Tag__c = 'HIPAA'
        );
        insert vault;

        insert new KT_OCR_Job__c(
            KT_DocumentVault__c = vault.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Review Required',
            OCR_Provider__c = 'AWS Textract',
            Job_Id__c = 'agentforce-ocr',
            Confidence_Score__c = 0.50
        );

        KT_Bulk_Document_Job__c bulkJob = new KT_Bulk_Document_Job__c(
            Job_Name__c = 'Agentforce Bulk',
            Status__c = 'Running',
            Total_Records__c = 10,
            Processed__c = 4,
            Success_Count__c = 4,
            Failure_Count__c = 0,
            Started_At__c = System.now()
        );
        insert bulkJob;

        KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
            KT_DocumentVault__c = vault.Id,
            KT_Onboarding__c = onboarding.Id,
            Signing_Provider__c = 'KT Sign',
            Status__c = 'In Progress',
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(7)
        );
        insert signatureRequest;
        insert new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Agentforce Signer',
            Signer_Email__c = 'agentforce.signer@example.com',
            Status__c = 'Invitation Sent',
            Signing_Order__c = 1
        );

        KT_HRCopilotOcrDiscrepancyAction.Request ocrRequest = new KT_HRCopilotOcrDiscrepancyAction.Request();
        ocrRequest.onboardingId = onboarding.Id;
        System.assertEquals(1, KT_HRCopilotOcrDiscrepancyAction.run(new List<KT_HRCopilotOcrDiscrepancyAction.Request>{ ocrRequest })[0].discrepancyCount);

        KT_HRCopilotGapAnalysisAction.Request gapRequest = new KT_HRCopilotGapAnalysisAction.Request();
        gapRequest.onboardingId = onboarding.Id;
        System.assertEquals(1, KT_HRCopilotGapAnalysisAction.run(new List<KT_HRCopilotGapAnalysisAction.Request>{ gapRequest })[0].missingCount);

        KT_HRCopilotBulkJobStatusAction.Request bulkRequest = new KT_HRCopilotBulkJobStatusAction.Request();
        bulkRequest.jobId = bulkJob.Id;
        System.assertEquals('Running', KT_HRCopilotBulkJobStatusAction.run(new List<KT_HRCopilotBulkJobStatusAction.Request>{ bulkRequest })[0].status);

        KT_HRCopilotSigningEscalationAction.Request escalationRequest = new KT_HRCopilotSigningEscalationAction.Request();
        escalationRequest.signatureRequestId = signatureRequest.Id;
        System.assertEquals(1, KT_HRCopilotSigningEscalationAction.run(new List<KT_HRCopilotSigningEscalationAction.Request>{ escalationRequest })[0].pendingSignerCount);
    }

    @IsTest
    static void complianceActionsReturnEvidenceAndExport() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        KT_DocumentTemplate__c template = createComplianceTemplate();
        insert new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Expiring License',
            Content_Document_Id__c = createContentDocument('expiring-license'),
            Document_Type__c = 'Certificate',
            Status__c = 'Verified',
            OCR_Status__c = 'Not Required',
            Signature_Status__c = 'Not Required',
            Version_Number__c = 1,
            Expiry_Date__c = Date.today().addDays(20),
            Regulatory_Tag__c = 'HIPAA'
        );

        KT_ComplianceMissingDocsAction.Request missingRequest = new KT_ComplianceMissingDocsAction.Request();
        missingRequest.onboardingId = onboarding.Id;
        System.assertEquals(1, KT_ComplianceMissingDocsAction.run(new List<KT_ComplianceMissingDocsAction.Request>{ missingRequest })[0].missingCount);

        KT_ComplianceExpiringDocsAction.Request expiringRequest = new KT_ComplianceExpiringDocsAction.Request();
        expiringRequest.onboardingId = onboarding.Id;
        expiringRequest.daysAhead = 90;
        System.assertEquals(1, KT_ComplianceExpiringDocsAction.run(new List<KT_ComplianceExpiringDocsAction.Request>{ expiringRequest })[0].expiringCount);

        KT_ComplianceAuditReportAction.Request auditRequest = new KT_ComplianceAuditReportAction.Request();
        auditRequest.onboardingId = onboarding.Id;
        KT_ComplianceAuditReportAction.Result auditResult =
            KT_ComplianceAuditReportAction.run(new List<KT_ComplianceAuditReportAction.Request>{ auditRequest })[0];
        System.assertNotEquals(null, auditResult.vaultEntryId);
        System.assertNotEquals(null, auditResult.certificationHash);
    }
}
