public with sharing class KT_ComplianceExpiringDocsAction {
    public class Request {
        @InvocableVariable public Id onboardingId;
        @InvocableVariable public Integer daysAhead;
    }

    public class Result {
        @InvocableVariable public Integer expiringCount;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Expiring Compliance Documents' description='Finds vault documents expiring within a compliance review window.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : safeRequests(requests)) {
            Integer daysAhead = request.daysAhead == null ? 90 : Math.max(1, Math.min(request.daysAhead, 365));
            Date endDate = Date.today().addDays(daysAhead);
            List<KT_DocumentVault__c> expiring = request.onboardingId == null
                ? [
                    SELECT Id, Document_Name__c, Expiry_Date__c, Regulatory_Tag__c
                    FROM KT_DocumentVault__c
                    WHERE Expiry_Date__c != null
                    AND Expiry_Date__c <= :endDate
                    AND Status__c != 'Archived'
                    ORDER BY Expiry_Date__c ASC
                    LIMIT 50
                ]
                : [
                    SELECT Id, Document_Name__c, Expiry_Date__c, Regulatory_Tag__c
                    FROM KT_DocumentVault__c
                    WHERE KT_Onboarding__c = :request.onboardingId
                    AND Expiry_Date__c != null
                    AND Expiry_Date__c <= :endDate
                    AND Status__c != 'Archived'
                    ORDER BY Expiry_Date__c ASC
                    LIMIT 50
                ];
            Result result = new Result();
            result.expiringCount = expiring.size();
            result.summary = expiring.isEmpty() ? 'No expiring documents found.' : summarize(expiring);
            results.add(result);
        }
        return results;
    }

    private static List<Request> safeRequests(List<Request> requests) {
        return requests == null || requests.isEmpty() ? new List<Request>{ new Request() } : requests;
    }

    private static String summarize(List<KT_DocumentVault__c> vaultEntries) {
        List<String> parts = new List<String>();
        for (KT_DocumentVault__c vaultEntry : vaultEntries) {
            parts.add(vaultEntry.Document_Name__c + ' expires ' + String.valueOf(vaultEntry.Expiry_Date__c));
        }
        return String.join(parts, '; ');
    }
}
