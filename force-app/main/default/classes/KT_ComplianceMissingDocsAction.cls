public with sharing class KT_ComplianceMissingDocsAction {
    public class Request {
        @InvocableVariable public Id onboardingId;
    }

    public class Result {
        @InvocableVariable public Integer missingCount;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Missing Compliance Documents' description='Finds required compliance document requests that are not complete.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : safeRequests(requests)) {
            List<KT_Document_Request__c> missing = request.onboardingId == null
                ? [
                    SELECT Id, Status__c, Document_Template__r.Template_Name__c, Document_Template__r.Regulatory_Framework__c
                    FROM KT_Document_Request__c
                    WHERE Is_Required__c = true
                    AND Status__c NOT IN ('Complete', 'Waived')
                    AND Document_Template__r.Regulatory_Framework__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 50
                ]
                : [
                    SELECT Id, Status__c, Document_Template__r.Template_Name__c, Document_Template__r.Regulatory_Framework__c
                    FROM KT_Document_Request__c
                    WHERE KT_Onboarding__c = :request.onboardingId
                    AND Is_Required__c = true
                    AND Status__c NOT IN ('Complete', 'Waived')
                    AND Document_Template__r.Regulatory_Framework__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 50
                ];
            Result result = new Result();
            result.missingCount = missing.size();
            result.summary = missing.isEmpty() ? 'No missing compliance documents found.' : summarize(missing);
            results.add(result);
        }
        return results;
    }

    private static List<Request> safeRequests(List<Request> requests) {
        return requests == null || requests.isEmpty() ? new List<Request>{ new Request() } : requests;
    }

    private static String summarize(List<KT_Document_Request__c> requests) {
        List<String> parts = new List<String>();
        for (KT_Document_Request__c request : requests) {
            parts.add(request.Document_Template__r.Template_Name__c + ' [' + request.Document_Template__r.Regulatory_Framework__c + ']');
        }
        return String.join(parts, '; ');
    }
}
