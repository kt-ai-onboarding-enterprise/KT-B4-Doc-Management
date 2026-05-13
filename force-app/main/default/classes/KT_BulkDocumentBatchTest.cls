@IsTest
private class KT_BulkDocumentBatchTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static KT_DocumentTemplate__c createTemplate(Boolean requiresSignature, String mergeBody) {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = requiresSignature ? 'Bulk Signature Template' : 'Bulk Template',
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = mergeBody,
            Requires_Signature__c = requiresSignature,
            Is_Active__c = true,
            Version__c = 1,
            Language__c = 'English'
        );
        insert template;
        return template;
    }

    private static String buildSignatureConfigJson() {
        KT_ESignatureOrchestrator.SignatureConfig config = new KT_ESignatureOrchestrator.SignatureConfig();
        config.signingProvider = 'KT Sign';
        config.signingOrder = 'Sequential';
        config.expiryDays = 7;
        config.signers = new List<KT_ESignatureOrchestrator.SignerConfig>();

        KT_ESignatureOrchestrator.SignerConfig signer = new KT_ESignatureOrchestrator.SignerConfig();
        signer.signerName = 'Bulk Signer';
        signer.signerEmail = 'bulk.signer@example.com';
        signer.signerRole = 'Onboardee';
        signer.signingOrder = 1;
        config.signers.add(signer);
        return JSON.serialize(config);
    }

    @IsTest
    static void validateCohortFlagsUnresolvedMergeTokens() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate(false, 'Hello {{Id}} and {{Missing_Field__c}}');

        Test.startTest();
        List<KT_BulkDocumentJobService.CohortValidationRow> rows =
            KT_BulkDocumentJobService.validateCohort(new List<Id>{ onboarding.Id }, template.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(false, rows[0].valid);
        System.assert(rows[0].unresolvedTokens.contains('{{Missing_Field__c}}'));
    }

    @IsTest
    static void launchBulkJobProcessesDocumentsAndUpdatesJobStatus() {
        KT_Onboarding__c firstOnboarding = createOnboarding();
        KT_Onboarding__c secondOnboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate(false, 'Bulk doc for {{Id}}');

        Test.startTest();
        KT_BulkDocumentJobService.BulkJobLaunchResult launchResult =
            KT_BulkDocumentJobService.launchBulkJob(
                new List<Id>{ firstOnboarding.Id, secondOnboarding.Id },
                template.Id,
                'Spring Intake Docs',
                null
            );
        Test.stopTest();

        KT_BulkDocumentJobService.BulkJobStatusRow statusRow =
            KT_BulkDocumentJobService.getBulkJobStatus(launchResult.jobId);
        System.assertEquals('Complete', statusRow.status);
        System.assertEquals(2, statusRow.totalRecords);
        System.assertEquals(2, statusRow.processed);
        System.assertEquals(2, statusRow.successCount);
        System.assertEquals(0, statusRow.failureCount);
        System.assertEquals(true, statusRow.complete);
        System.assertEquals(2, [
            SELECT COUNT()
            FROM KT_DocumentVault__c
            WHERE KT_Onboarding__c IN :new List<Id>{ firstOnboarding.Id, secondOnboarding.Id }
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :launchResult.jobId
        ]);
    }

    @IsTest
    static void launchBulkJobDispatchesSignatureWorkflowWhenRequired() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate(true, 'Please sign {{Id}}');

        Test.startTest();
        KT_BulkDocumentJobService.BulkJobLaunchResult launchResult =
            KT_BulkDocumentJobService.launchBulkJob(
                new List<Id>{ onboarding.Id },
                template.Id,
                'Offer Pack',
                buildSignatureConfigJson()
            );
        Test.stopTest();

        KT_BulkDocumentJobService.BulkJobStatusRow statusRow =
            KT_BulkDocumentJobService.getBulkJobStatus(launchResult.jobId);
        System.assertEquals('Complete', statusRow.status);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signature_Request__c
            WHERE KT_Onboarding__c = :onboarding.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__r.KT_Onboarding__c = :onboarding.Id
        ]);
    }

    @IsTest
    static void launchBulkJobRejectsMissingInputs() {
        try {
            KT_BulkDocumentJobService.launchBulkJob(new List<Id>(), null, 'Bad Job', null);
            System.assert(false, 'Expected missing inputs to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }

    @IsTest
    static void launchBulkJobCapturesFailureSummaryAndRecentJobs() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate(true, 'Signature required for {{Id}}');

        Test.startTest();
        KT_BulkDocumentJobService.BulkJobLaunchResult launchResult =
            KT_BulkDocumentJobService.launchBulkJob(
                new List<Id>{ onboarding.Id },
                template.Id,
                'Broken Signature Job',
                null
            );
        Test.stopTest();

        KT_BulkDocumentJobService.BulkJobStatusRow statusRow =
            KT_BulkDocumentJobService.getBulkJobStatus(launchResult.jobId);
        System.assertEquals('Failed', statusRow.status);
        System.assertEquals(1, statusRow.failureCount);
        System.assertNotEquals(null, statusRow.failureSummary);
        System.assert(statusRow.failureSummary.contains(String.valueOf(onboarding.Id)));
        System.assert(statusRow.failureSummary.contains('Signature configuration is required'));
        System.assertEquals(true, statusRow.complete);
        System.assertNotEquals(null, statusRow.estimatedCompletionAt);

        List<KT_BulkDocumentJobService.BulkJobStatusRow> recentJobs =
            KT_BulkDocumentJobService.getRecentBulkJobs(5);
        System.assert(!recentJobs.isEmpty());
        System.assertEquals(launchResult.jobId, recentJobs[0].jobId);
    }

    @IsTest
    static void bulkJobStatusSupportsRunningJobsAndDefaultRecentQuery() {
        KT_DocumentTemplate__c template = createTemplate(false, 'Bulk doc for {{Id}}');
        KT_Bulk_Document_Job__c jobRecord = new KT_Bulk_Document_Job__c(
            Job_Name__c = 'Running Job',
            Template__c = template.Id,
            Total_Records__c = 10,
            Processed__c = 4,
            Success_Count__c = 3,
            Failure_Count__c = 1,
            Failure_Summary__c = 'Onboarding sample: Merge field missing.',
            Status__c = 'Running',
            Initiated_By__c = UserInfo.getUserId(),
            Started_At__c = System.now().addMinutes(-5),
            Apex_Job_Id__c = '707000000000001'
        );
        insert jobRecord;

        KT_BulkDocumentJobService.BulkJobStatusRow statusRow =
            KT_BulkDocumentJobService.getBulkJobStatus(jobRecord.Id);
        System.assertEquals(false, statusRow.complete);
        System.assertEquals(40, statusRow.progressPercent.intValue());
        System.assertNotEquals(null, statusRow.estimatedCompletionAt);
        System.assertEquals('Onboarding sample: Merge field missing.', statusRow.failureSummary);

        List<KT_BulkDocumentJobService.BulkJobStatusRow> recentJobs =
            KT_BulkDocumentJobService.getRecentBulkJobs(null);
        System.assert(!recentJobs.isEmpty());
        System.assertEquals(jobRecord.Id, recentJobs[0].jobId);
    }

    @IsTest
    static void bulkJobServiceRejectsOversizedAndMissingStatusInputs() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = createTemplate(false, 'Bulk doc for {{Id}}');
        List<Id> oversizedIds = new List<Id>();
        for (Integer index = 0; index < 10001; index++) {
            oversizedIds.add(onboarding.Id);
        }

        System.assertEquals(0, KT_BulkDocumentJobService.validateCohort(new List<Id>(), template.Id).size());

        try {
            KT_BulkDocumentJobService.validateCohort(new List<Id>{ onboarding.Id }, null);
            System.assert(false, 'Expected template validation to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_BulkDocumentJobService.validateCohort(oversizedIds, template.Id);
            System.assert(false, 'Expected oversized cohort validation to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_BulkDocumentJobService.getBulkJobStatus(null);
            System.assert(false, 'Expected missing job id to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_BulkDocumentJobService.launchBulkJob(oversizedIds, template.Id, 'Too Large', null);
            System.assert(false, 'Expected oversized launch to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
