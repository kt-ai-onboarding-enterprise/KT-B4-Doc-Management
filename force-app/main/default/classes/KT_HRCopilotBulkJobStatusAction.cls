public with sharing class KT_HRCopilotBulkJobStatusAction {
    public class Request {
        @InvocableVariable public Id jobId;
    }

    public class Result {
        @InvocableVariable public Id jobId;
        @InvocableVariable public String status;
        @InvocableVariable public Decimal progressPercent;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Bulk Job Status' description='Returns bulk document job progress for Agentforce.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            for (KT_BulkDocumentJobService.BulkJobStatusRow row : KT_BulkDocumentJobService.getRecentBulkJobs(5)) {
                results.add(fromRow(row));
            }
            return results;
        }
        for (Request request : requests) {
            results.add(fromRow(KT_BulkDocumentJobService.getBulkJobStatus(request.jobId)));
        }
        return results;
    }

    private static Result fromRow(KT_BulkDocumentJobService.BulkJobStatusRow row) {
        Result result = new Result();
        result.jobId = row.jobId;
        result.status = row.status;
        result.progressPercent = row.progressPercent;
        result.summary = row.jobName + ': ' + row.processed + '/' + row.totalRecords + ' processed, failures=' + row.failureCount;
        return result;
    }
}
