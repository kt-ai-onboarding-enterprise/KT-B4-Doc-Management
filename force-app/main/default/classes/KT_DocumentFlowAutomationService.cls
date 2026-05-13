public with sharing class KT_DocumentFlowAutomationService {
    private static final Set<Integer> EXPIRY_ALERT_WINDOWS = new Set<Integer>{ 30, 60, 90 };
    private static final Integer DOCUMENT_REQUEST_REMINDER_WINDOW_DAYS = 3;
    private static final Integer DOCUMENT_REQUEST_REMINDER_MAX = 3;
    private static final Integer SIGNER_REMINDER_THROTTLE_DAYS = 2;
    private static final List<String> ONBOARDING_EMAIL_FIELD_CANDIDATES = new List<String>{
        'Onboardee_Email__c',
        'Primary_Email__c',
        'Personal_Email__c',
        'Email__c'
    };

    public class ScheduledActionRequest {
        @InvocableVariable(required=true) public Id recordId;
        @InvocableVariable(required=true) public String actionType;
    }

    public class ScheduledActionResult {
        @InvocableVariable public Id recordId;
        @InvocableVariable public String actionType;
        @InvocableVariable public Boolean processed;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Run KT B4 Scheduled Flow Action'
        description='Executes the scheduled B4 document automation action for the supplied record.'
    )
    public static List<ScheduledActionResult> runScheduledAction(List<ScheduledActionRequest> requests) {
        List<ScheduledActionResult> results = new List<ScheduledActionResult>();
        if (requests == null) {
            return results;
        }

        for (ScheduledActionRequest request : requests) {
            ScheduledActionResult result = new ScheduledActionResult();
            result.recordId = request == null ? null : request.recordId;
            result.actionType = request == null ? null : request.actionType;
            result.processed = false;
            result.message = 'No action performed.';

            if (request == null || request.recordId == null || String.isBlank(request.actionType)) {
                result.message = 'recordId and actionType are required.';
                results.add(result);
                continue;
            }

            String actionType = request.actionType.trim().toUpperCase();
            if (actionType == 'SIGNATURE_EXPIRY') {
                result = processSignatureExpiry(request.recordId, request.actionType);
            } else if (actionType == 'SIGNATURE_REMINDER') {
                result = processSignatureReminder(request.recordId, request.actionType);
            } else if (actionType == 'SIGNATURE_STATUS_SYNC') {
                result = processSignatureStatusSync(request.recordId, request.actionType);
            } else if (actionType == 'DOCUMENT_REQUEST_REMINDER') {
                result = processDocumentRequestReminder(request.recordId, request.actionType);
            } else if (actionType == 'DOCUMENT_EXPIRY_ALERT') {
                result = processDocumentExpiryAlert(request.recordId, request.actionType);
            } else {
                result.message = 'Unsupported action type: ' + request.actionType;
            }

            results.add(result);
        }
        return results;
    }

    private static ScheduledActionResult processSignatureExpiry(Id signatureRequestId, String actionType) {
        ScheduledActionResult result = baseResult(signatureRequestId, actionType);
        KT_Signature_Request__c request = [
            SELECT Id, Status__c, Expiry_Date__c, Initiated_By__c, Initiated_By__r.Email,
                   KT_Onboarding__c, KT_DocumentVault__r.Document_Name__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];

        if (request.Status__c != 'In Progress' || request.Expiry_Date__c == null || request.Expiry_Date__c > Date.today()) {
            result.message = 'Signature request does not meet expiry criteria.';
            return result;
        }

        KT_ESignatureOrchestrator.handleExpiryEscalation(signatureRequestId);
        createTask(
            request.KT_Onboarding__c,
            request.Initiated_By__c == null ? UserInfo.getUserId() : request.Initiated_By__c,
            'Expired signature request: ' + safeLabel(request.KT_DocumentVault__r == null ? null : request.KT_DocumentVault__r.Document_Name__c, 'Document'),
            'The signature request expired and was escalated by KT_ESignature_Expiry_Check.',
            'High'
        );
        sendEmail(
            request.Initiated_By__r == null ? null : request.Initiated_By__r.Email,
            'KT Sign expiry escalation',
            'The signature request for '
                + safeLabel(request.KT_DocumentVault__r == null ? null : request.KT_DocumentVault__r.Document_Name__c, 'the document')
                + ' has expired and was escalated on ' + String.valueOf(Date.today()) + '.'
        );

        result.processed = true;
        result.message = 'Signature expiry escalation processed.';
        return result;
    }

    private static ScheduledActionResult processSignatureReminder(Id signerId, String actionType) {
        ScheduledActionResult result = baseResult(signerId, actionType);
        KT_Signer__c signer = [
            SELECT Id, Status__c, Reminder_Sent_At__c, Signer_Email__c, Signer_Name__c,
                   KT_Signature_Request__c, KT_Signature_Request__r.Status__c,
                   KT_Signature_Request__r.Expiry_Date__c,
                   KT_Signature_Request__r.KT_DocumentVault__r.Document_Name__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
        ];

        if (signer.Status__c != 'Invitation Sent') {
            result.message = 'Signer is not pending reminder.';
            return result;
        }
        if (signer.KT_Signature_Request__r == null || signer.KT_Signature_Request__r.Status__c != 'In Progress') {
            result.message = 'Parent signature request is not active.';
            return result;
        }
        if (signer.Reminder_Sent_At__c != null
            && signer.Reminder_Sent_At__c > System.now().addDays(-SIGNER_REMINDER_THROTTLE_DAYS)) {
            result.message = 'Reminder throttle window not reached.';
            return result;
        }

        sendEmail(
            signer.Signer_Email__c,
            'Reminder: signature requested',
            'Please review and sign '
                + safeLabel(
                    signer.KT_Signature_Request__r.KT_DocumentVault__r == null
                        ? null
                        : signer.KT_Signature_Request__r.KT_DocumentVault__r.Document_Name__c,
                    'your document'
                )
                + '.'
        );
        update new KT_Signer__c(
            Id = signer.Id,
            Reminder_Sent_At__c = System.now()
        );

        result.processed = true;
        result.message = 'Signature reminder sent.';
        return result;
    }

    private static ScheduledActionResult processSignatureStatusSync(Id signerId, String actionType) {
        ScheduledActionResult result = baseResult(signerId, actionType);
        KT_Signer__c signer = [
            SELECT Id, Status__c, KT_Signature_Request__c, KT_Signature_Request__r.Status__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
        ];

        if (signer.Status__c != 'Signed') {
            result.message = 'Signer is not in Signed status.';
            return result;
        }
        if (signer.KT_Signature_Request__r == null || signer.KT_Signature_Request__r.Status__c == 'Fully Signed') {
            result.message = 'Signature request is already fully signed.';
            return result;
        }

        Integer activeCount = [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signer.KT_Signature_Request__c
            AND Status__c IN ('Pending', 'Invitation Sent', 'Viewed')
        ];
        if (activeCount > 0) {
            result.message = 'Additional signers are still pending.';
            return result;
        }

        Integer signedCount = [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signer.KT_Signature_Request__c
            AND Status__c = 'Signed'
        ];
        if (signedCount == 0) {
            result.message = 'No completed signer records were found.';
            return result;
        }

        KT_ESignatureOrchestrator.completeWorkflow(signer.KT_Signature_Request__c);
        result.processed = true;
        result.message = 'Signature workflow status synced.';
        return result;
    }

    private static ScheduledActionResult processDocumentRequestReminder(Id requestId, String actionType) {
        ScheduledActionResult result = baseResult(requestId, actionType);
        KT_Document_Request__c request = [
            SELECT Id, Status__c, Due_Date__c, Reminder_Count__c, KT_Onboarding__c,
                   KT_Onboarding__r.OwnerId, KT_Onboarding__r.Owner.Email,
                   Document_Template__r.Template_Name__c
            FROM KT_Document_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        if (request.Status__c != 'Not Started') {
            result.message = 'Document request is not in a reminder status.';
            return result;
        }
        if (request.Due_Date__c == null || request.Due_Date__c > Date.today().addDays(DOCUMENT_REQUEST_REMINDER_WINDOW_DAYS)) {
            result.message = 'Document request is outside the reminder window.';
            return result;
        }
        Integer reminderCount = request.Reminder_Count__c == null ? 0 : request.Reminder_Count__c.intValue();
        if (reminderCount >= DOCUMENT_REQUEST_REMINDER_MAX) {
            result.message = 'Reminder cap reached.';
            return result;
        }

        String recipientEmail = resolveReminderEmail(request.KT_Onboarding__c, request.KT_Onboarding__r == null ? null : request.KT_Onboarding__r.Owner.Email);
        sendEmail(
            recipientEmail,
            'Reminder: onboarding document required',
            'Please upload the required onboarding document: '
                + safeLabel(
                    request.Document_Template__r == null ? null : request.Document_Template__r.Template_Name__c,
                    'Requested document'
                )
                + '.'
        );
        createTask(
            request.KT_Onboarding__c,
            request.KT_Onboarding__r == null ? UserInfo.getUserId() : request.KT_Onboarding__r.OwnerId,
            'Document reminder: ' + safeLabel(request.Document_Template__r == null ? null : request.Document_Template__r.Template_Name__c, 'Requested document'),
            'KT_DocumentRequest_Reminder issued a reminder for an outstanding onboarding document request.',
            'Normal'
        );
        update new KT_Document_Request__c(
            Id = request.Id,
            Reminder_Count__c = reminderCount + 1
        );

        result.processed = true;
        result.message = 'Document request reminder sent.';
        return result;
    }

    private static ScheduledActionResult processDocumentExpiryAlert(Id vaultEntryId, String actionType) {
        ScheduledActionResult result = baseResult(vaultEntryId, actionType);
        KT_DocumentVault__c vaultEntry = [
            SELECT Id, KT_Onboarding__c, KT_Onboarding__r.OwnerId, KT_Onboarding__r.Owner.Email,
                   Document_Name__c, Expiry_Date__c, Status__c, Uploaded_By__r.Email
            FROM KT_DocumentVault__c
            WHERE Id = :vaultEntryId
            LIMIT 1
        ];

        if (vaultEntry.Status__c == 'Archived' || vaultEntry.Expiry_Date__c == null) {
            result.message = 'Vault entry is not eligible for expiry alerts.';
            return result;
        }

        Integer daysRemaining = Date.today().daysBetween(vaultEntry.Expiry_Date__c);
        if (!EXPIRY_ALERT_WINDOWS.contains(daysRemaining)) {
            result.message = 'Vault entry is outside the 30/60/90-day alert windows.';
            return result;
        }

        String recipientEmail = vaultEntry.Uploaded_By__r == null || String.isBlank(vaultEntry.Uploaded_By__r.Email)
            ? (vaultEntry.KT_Onboarding__r == null ? null : vaultEntry.KT_Onboarding__r.Owner.Email)
            : vaultEntry.Uploaded_By__r.Email;
        sendEmail(
            recipientEmail,
            'Document expiry alert: ' + safeLabel(vaultEntry.Document_Name__c, 'Document'),
            safeLabel(vaultEntry.Document_Name__c, 'Document')
                + ' is due to expire in ' + String.valueOf(daysRemaining) + ' days on '
                + String.valueOf(vaultEntry.Expiry_Date__c) + '.'
        );
        createTask(
            vaultEntry.KT_Onboarding__c,
            vaultEntry.KT_Onboarding__r == null ? UserInfo.getUserId() : vaultEntry.KT_Onboarding__r.OwnerId,
            'Document expiry alert: ' + safeLabel(vaultEntry.Document_Name__c, 'Document'),
            'KT_Document_Expiry_Alert generated a ' + String.valueOf(daysRemaining) + '-day expiry reminder.',
            'High'
        );

        result.processed = true;
        result.message = 'Document expiry alert created.';
        return result;
    }

    private static ScheduledActionResult baseResult(Id recordId, String actionType) {
        ScheduledActionResult result = new ScheduledActionResult();
        result.recordId = recordId;
        result.actionType = actionType;
        result.processed = false;
        result.message = 'No action performed.';
        return result;
    }

    private static void createTask(Id whatId, Id ownerId, String subject, String description, String priority) {
        if (whatId == null) {
            return;
        }
        insert new Task(
            WhatId = whatId,
            OwnerId = ownerId == null ? UserInfo.getUserId() : ownerId,
            Subject = subject.left(255),
            Description = description,
            ActivityDate = Date.today(),
            Priority = priority,
            Status = 'Not Started'
        );
    }

    private static void sendEmail(String recipient, String subject, String body) {
        if (String.isBlank(recipient)) {
            return;
        }

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ recipient });
        message.setSubject(subject);
        message.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ message }, false);
    }

    private static String resolveReminderEmail(Id onboardingId, String fallbackEmail) {
        if (onboardingId == null) {
            return fallbackEmail;
        }

        Schema.DescribeSObjectResult describeResult = KT_Onboarding__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldsByName = describeResult.fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id', 'Owner.Email' };
        for (String candidate : ONBOARDING_EMAIL_FIELD_CANDIDATES) {
            if (fieldsByName.containsKey(candidate)) {
                selectedFields.add(candidate);
            }
        }

        String query = 'SELECT ' + String.join(selectedFields, ',')
            + ' FROM KT_Onboarding__c WHERE Id = :onboardingId LIMIT 1';
        SObject onboarding = Database.query(query);

        for (String candidate : ONBOARDING_EMAIL_FIELD_CANDIDATES) {
            if (!fieldsByName.containsKey(candidate)) {
                continue;
            }
            Object value = onboarding.get(candidate);
            if (value != null && !String.isBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }

        SObject owner = onboarding.getSObject('Owner');
        if (owner != null && owner.get('Email') != null && !String.isBlank(String.valueOf(owner.get('Email')))) {
            return String.valueOf(owner.get('Email'));
        }
        if (!String.isBlank(fallbackEmail)) {
            return fallbackEmail;
        }

        List<User> currentUsers = [
            SELECT Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return currentUsers.isEmpty() ? null : currentUsers[0].Email;
    }

    private static String safeLabel(String value, String fallbackValue) {
        return String.isBlank(value) ? fallbackValue : value;
    }
}
