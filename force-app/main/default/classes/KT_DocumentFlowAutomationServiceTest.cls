@IsTest
private class KT_DocumentFlowAutomationServiceTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c();
        insert onboarding;
        return onboarding;
    }

    private static Id createContentDocument(String title) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(title + ' body')
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    @IsTest
    static void signatureExpiryActionEscalatesRequestAndCreatesTask() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Offer Letter',
            Content_Document_Id__c = createContentDocument('Offer Letter'),
            Document_Type__c = 'Generated',
            Status__c = 'Pending Signature',
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Pending'
        );
        insert vaultEntry;

        KT_Signature_Request__c request = new KT_Signature_Request__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'In Progress',
            Signing_Provider__c = 'KT Sign',
            Expiry_Date__c = Date.today().addDays(-1),
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Initiated_By__c = UserInfo.getUserId()
        );
        insert request;

        insert new KT_Signer__c(
            KT_Signature_Request__c = request.Id,
            Signer_Name__c = 'Signer One',
            Signer_Email__c = 'signer.one@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Invitation Sent'
        );

        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = request.Id;
        action.actionType = 'SIGNATURE_EXPIRY';

        Test.startTest();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> results =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(true, results[0].processed);
        System.assertEquals(1, emailInvocations);
        System.assertEquals('Expired', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :request.Id
        ].Status__c);
        System.assertEquals('Expired', [
            SELECT Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntry.Id
        ].Status__c);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :onboarding.Id
        ]);
    }

    @IsTest
    static void signatureReminderActionHonorsThrottleAndUpdatesTimestamp() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Policy Ack',
            Content_Document_Id__c = createContentDocument('Policy Ack'),
            Document_Type__c = 'Generated',
            Status__c = 'Pending Signature',
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Pending'
        );
        insert vaultEntry;

        KT_Signature_Request__c request = new KT_Signature_Request__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'In Progress',
            Signing_Provider__c = 'KT Sign',
            Expiry_Date__c = Date.today().addDays(5),
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 0,
            Initiated_By__c = UserInfo.getUserId()
        );
        insert request;

        KT_Signer__c signer = new KT_Signer__c(
            KT_Signature_Request__c = request.Id,
            Signer_Name__c = 'Signer Reminder',
            Signer_Email__c = 'signer.reminder@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Invitation Sent'
        );
        insert signer;

        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = signer.Id;
        action.actionType = 'SIGNATURE_REMINDER';

        Test.startTest();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> firstRun =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Integer emailInvocations = Limits.getEmailInvocations();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> secondRun =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Test.stopTest();

        System.assertEquals(true, firstRun[0].processed);
        System.assertEquals(1, emailInvocations);
        System.assertEquals(false, secondRun[0].processed);
        System.assertNotEquals(null, [
            SELECT Reminder_Sent_At__c
            FROM KT_Signer__c
            WHERE Id = :signer.Id
        ].Reminder_Sent_At__c);
    }

    @IsTest
    static void documentRequestReminderIncrementsCounterAndCreatesTask() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Not Started',
            Due_Date__c = Date.today().addDays(2),
            Reminder_Count__c = 0,
            Document_Direction__c = 'Inbound',
            Is_Required__c = true
        );
        insert request;

        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = request.Id;
        action.actionType = 'DOCUMENT_REQUEST_REMINDER';

        Test.startTest();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> results =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(true, results[0].processed);
        System.assertEquals(1, emailInvocations);
        System.assertEquals(1, [
            SELECT Reminder_Count__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ].Reminder_Count__c.intValue());
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :onboarding.Id
        ]);
    }

    @IsTest
    static void signatureStatusSyncCompletesParentWorkflowWhenLastSignerSigned() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_Document_Request__c documentRequest = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'Awaiting Signature',
            Document_Direction__c = 'Outbound',
            Is_Required__c = true
        );
        insert documentRequest;

        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Handbook Ack',
            Content_Document_Id__c = createContentDocument('Handbook Ack'),
            Document_Type__c = 'Generated',
            Status__c = 'Pending Signature',
            Document_Request__c = documentRequest.Id,
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Pending'
        );
        insert vaultEntry;

        KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
            KT_DocumentVault__c = vaultEntry.Id,
            KT_Onboarding__c = onboarding.Id,
            Status__c = 'In Progress',
            Signing_Provider__c = 'KT Sign',
            Expiry_Date__c = Date.today().addDays(5),
            Signing_Order__c = 'Sequential',
            Total_Signers__c = 1,
            Completed_Signers__c = 1,
            Initiated_By__c = UserInfo.getUserId()
        );
        insert signatureRequest;

        KT_Signer__c signer = new KT_Signer__c(
            KT_Signature_Request__c = signatureRequest.Id,
            Signer_Name__c = 'Final Signer',
            Signer_Email__c = 'final.signer@example.com',
            Signer_Role__c = 'Onboardee',
            Signing_Order__c = 1,
            Status__c = 'Signed'
        );
        insert signer;

        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = signer.Id;
        action.actionType = 'SIGNATURE_STATUS_SYNC';

        Test.startTest();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> results =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].processed);
        System.assertEquals('Fully Signed', [
            SELECT Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequest.Id
        ].Status__c);
        System.assertEquals('Signed', [
            SELECT Status__c, Signature_Status__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntry.Id
        ].Status__c);
        System.assertEquals('Complete', [
            SELECT Status__c
            FROM KT_Document_Request__c
            WHERE Id = :documentRequest.Id
        ].Status__c);
    }

    @IsTest
    static void documentExpiryAlertCreatesTaskForThirtyDayWindow() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Name__c = 'Passport',
            Content_Document_Id__c = createContentDocument('Passport'),
            Document_Type__c = 'Uploaded',
            Status__c = 'Verified',
            Expiry_Date__c = Date.today().addDays(30),
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = 'Not Required',
            Uploaded_By__c = UserInfo.getUserId()
        );
        insert vaultEntry;

        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = vaultEntry.Id;
        action.actionType = 'DOCUMENT_EXPIRY_ALERT';

        Test.startTest();
        List<KT_DocumentFlowAutomationService.ScheduledActionResult> results =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(true, results[0].processed);
        System.assertEquals(1, emailInvocations);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :onboarding.Id
        ]);
    }

    @IsTest
    static void unsupportedActionIsReturnedAsSkipped() {
        KT_DocumentFlowAutomationService.ScheduledActionRequest action =
            new KT_DocumentFlowAutomationService.ScheduledActionRequest();
        action.recordId = UserInfo.getUserId();
        action.actionType = 'UNSUPPORTED';

        List<KT_DocumentFlowAutomationService.ScheduledActionResult> results =
            KT_DocumentFlowAutomationService.runScheduledAction(
                new List<KT_DocumentFlowAutomationService.ScheduledActionRequest>{ action }
            );

        System.assertEquals(false, results[0].processed);
        System.assert(results[0].message.contains('Unsupported action type'));
    }
}
