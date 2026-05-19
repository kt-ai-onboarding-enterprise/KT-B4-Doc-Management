public with sharing class KT_HRCopilotSigningEscalationAction {
    public class Request {
        @InvocableVariable(required=true) public Id signatureRequestId;
    }

    public class Result {
        @InvocableVariable public Id signatureRequestId;
        @InvocableVariable public Integer pendingSignerCount;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Signing Escalation' description='Creates an HR task for pending signer escalation.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            KT_Signature_Request__c signatureRequest = [
                SELECT Id, KT_Onboarding__c, KT_DocumentVault__r.Document_Name__c, Initiated_By__c
                FROM KT_Signature_Request__c
                WHERE Id = :request.signatureRequestId
                LIMIT 1
            ];
            Integer pendingCount = [
                SELECT COUNT()
                FROM KT_Signer__c
                WHERE KT_Signature_Request__c = :request.signatureRequestId
                AND Status__c IN ('Pending', 'Invitation Sent', 'Viewed')
            ];
            if (pendingCount > 0) {
                insert new Task(
                    WhatId = signatureRequest.KT_Onboarding__c,
                    OwnerId = signatureRequest.Initiated_By__c == null ? UserInfo.getUserId() : signatureRequest.Initiated_By__c,
                    Subject = ('Signing escalation: ' + safe(signatureRequest.KT_DocumentVault__r == null ? null : signatureRequest.KT_DocumentVault__r.Document_Name__c)).left(255),
                    Description = 'Agentforce detected pending signers and created this escalation task.',
                    ActivityDate = Date.today(),
                    Priority = 'High',
                    Status = 'Not Started'
                );
            }
            Result result = new Result();
            result.signatureRequestId = request.signatureRequestId;
            result.pendingSignerCount = pendingCount;
            result.summary = pendingCount == 0 ? 'No pending signers found.' : 'Escalation task created for ' + pendingCount + ' pending signer(s).';
            results.add(result);
        }
        return results;
    }

    private static String safe(String value) {
        return String.isBlank(value) ? 'Document' : value;
    }
}
