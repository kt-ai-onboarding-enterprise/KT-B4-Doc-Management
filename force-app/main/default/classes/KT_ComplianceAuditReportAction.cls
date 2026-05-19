public with sharing class KT_ComplianceAuditReportAction {
    public class Request {
        @InvocableVariable(required=true) public Id onboardingId;
    }

    public class Result {
        @InvocableVariable public Id onboardingId;
        @InvocableVariable public Id vaultEntryId;
        @InvocableVariable public Id contentDocumentId;
        @InvocableVariable public String certificationHash;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(label='KT B4 Generate Compliance Audit Report' description='Generates the B4 certified audit export for Agentforce compliance review.')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            KT_AuditExportService.AuditExportResult exportResult = KT_AuditExportService.exportAuditPackage(request.onboardingId);
            Result result = new Result();
            result.onboardingId = request.onboardingId;
            result.vaultEntryId = exportResult.vaultEntryId;
            result.contentDocumentId = exportResult.contentDocumentId;
            result.certificationHash = exportResult.certificationHash;
            result.summary = exportResult.message;
            results.add(result);
        }
        return results;
    }
}
