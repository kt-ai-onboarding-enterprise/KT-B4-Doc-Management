public with sharing class KT_HRCopilotOcrDiscrepancyAction {
    public class Request {
        @InvocableVariable public Id onboardingId;
    }

    public class Result {
        @InvocableVariable public Integer discrepancyCount;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 OCR Discrepancy Detection' description='Finds OCR jobs needing HR review or manual correction.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : safeRequests(requests)) {
            List<KT_OCR_Job__c> jobs = request.onboardingId == null
                ? [
                    SELECT Id, Status__c, Document_Type_Detected__c, Confidence_Score__c, Review_Notes__c
                    FROM KT_OCR_Job__c
                    WHERE Status__c IN ('Review Required', 'Failed', 'Rejected')
                    OR Confidence_Score__c < 0.80
                    ORDER BY CreatedDate DESC
                    LIMIT 25
                ]
                : [
                    SELECT Id, Status__c, Document_Type_Detected__c, Confidence_Score__c, Review_Notes__c
                    FROM KT_OCR_Job__c
                    WHERE KT_Onboarding__c = :request.onboardingId
                    AND (Status__c IN ('Review Required', 'Failed', 'Rejected') OR Confidence_Score__c < 0.80)
                    ORDER BY CreatedDate DESC
                    LIMIT 25
                ];
            Result result = new Result();
            result.discrepancyCount = jobs.size();
            result.summary = jobs.isEmpty()
                ? 'No OCR discrepancies found.'
                : 'Found ' + jobs.size() + ' OCR jobs requiring review: ' + summarizeOcr(jobs);
            results.add(result);
        }
        return results;
    }

    private static List<Request> safeRequests(List<Request> requests) {
        return requests == null || requests.isEmpty() ? new List<Request>{ new Request() } : requests;
    }

    private static String summarizeOcr(List<KT_OCR_Job__c> jobs) {
        List<String> parts = new List<String>();
        for (KT_OCR_Job__c job : jobs) {
            parts.add(String.valueOf(job.Id) + ' ' + job.Status__c + ' ' + String.valueOf(job.Confidence_Score__c));
        }
        return String.join(parts, '; ');
    }
}
