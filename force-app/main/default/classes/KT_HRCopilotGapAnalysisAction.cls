public with sharing class KT_HRCopilotGapAnalysisAction {
    public class Request {
        @InvocableVariable(required=true) public Id onboardingId;
    }

    public class Result {
        @InvocableVariable public Id onboardingId;
        @InvocableVariable public Integer missingCount;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Document Gap Analysis' description='Summarizes incomplete onboarding document requests.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            List<KT_Document_Request__c> gaps = [
                SELECT Id, Status__c, Due_Date__c, Document_Template__r.Template_Name__c
                FROM KT_Document_Request__c
                WHERE KT_Onboarding__c = :request.onboardingId
                AND Status__c NOT IN ('Complete', 'Waived')
                ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC
                LIMIT 50
            ];
            Result result = new Result();
            result.onboardingId = request.onboardingId;
            result.missingCount = gaps.size();
            result.summary = gaps.isEmpty() ? 'No document gaps found.' : summarizeRequests(gaps);
            results.add(result);
        }
        return results;
    }

    private static String summarizeRequests(List<KT_Document_Request__c> requests) {
        List<String> parts = new List<String>();
        for (KT_Document_Request__c request : requests) {
            String name = request.Document_Template__r == null ? 'Document request' : request.Document_Template__r.Template_Name__c;
            parts.add(name + ' - ' + request.Status__c);
        }
        return String.join(parts, '; ');
    }
}
