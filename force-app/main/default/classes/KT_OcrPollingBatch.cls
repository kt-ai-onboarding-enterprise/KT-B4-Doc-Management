public with sharing class KT_OcrPollingBatch implements Queueable, Database.AllowsCallouts {
    private static final String PROVIDER_AWS = 'AWS Textract';
    private static final String PROVIDER_AZURE = 'Azure Form Recognizer';
    @TestVisible private static Boolean enableChainedPolling = true;

    private final Id ocrJobId;

    public KT_OcrPollingBatch(Id ocrJobId) {
        this.ocrJobId = ocrJobId;
    }

    public void execute(QueueableContext context) {
        if (ocrJobId == null) {
            return;
        }

        KT_OCR_Job__c job = [
            SELECT Id, KT_DocumentVault__c, KT_Onboarding__c, OCR_Provider__c, Job_Id__c, Status__c,
                   Retry_Count__c, Review_Notes__c, KT_DocumentVault__r.Document_Name__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJobId
            LIMIT 1
            FOR UPDATE
        ];
        if (String.isBlank(job.Job_Id__c)) {
            failJob(job, currentRetryCount(job), 'OCR polling cannot start because the provider job id is missing.', false);
            return;
        }

        ProviderConfigRecord config = String.isBlank(job.OCR_Provider__c)
            ? getActiveProviderConfig()
            : getProviderConfig(job.OCR_Provider__c);
        Integer nextRetryCount = currentRetryCount(job) + 1;
        PollResult pollResult = config.providerName == PROVIDER_AWS
            ? pollTextract(job, config)
            : pollAzure(job, config);

        if (pollResult.isComplete && pollResult.isSuccess) {
            update new KT_OCR_Job__c(
                Id = job.Id,
                Retry_Count__c = nextRetryCount,
                Status__c = 'Processing',
                Review_Notes__c = 'OCR polling completed on attempt ' + nextRetryCount + '. Parsing provider response.'
            );
            KT_OcrIngestionService.parseAndMap(job.Id, pollResult.rawJson);
            return;
        }

        if (pollResult.isComplete) {
            failJob(job, nextRetryCount, pollResult.message, true);
            return;
        }

        Integer maxRetries = config.maxRetries == null ? 12 : config.maxRetries;
        if (nextRetryCount >= maxRetries) {
            failJob(
                job,
                nextRetryCount,
                'OCR polling reached the maximum retry count (' + maxRetries + '). Manual review is required.',
                true
            );
            return;
        }

        update new KT_OCR_Job__c(
            Id = job.Id,
            Retry_Count__c = nextRetryCount,
            Status__c = 'Processing',
            Review_Notes__c = 'OCR polling attempt ' + nextRetryCount + ' is still waiting on the provider.'
        );

        if (enableChainedPolling) {
            System.enqueueJob(new KT_OcrPollingBatch(job.Id));
        }
    }

    private static PollResult pollTextract(KT_OCR_Job__c job, ProviderConfigRecord config) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildBaseEndpoint(config));
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-amz-json-1.1');
        request.setHeader('X-Amz-Target', 'Textract.GetDocumentAnalysis');
        request.setTimeout(120000);
        request.setBody(JSON.serialize(new Map<String, Object>{ 'JobId' => job.Job_Id__c }));

        HttpResponse response = new Http().send(request);
        ensureSuccessStatus(response);

        Map<String, Object> payload = deserializeMap(response.getBody());
        String jobStatus = stringValue(payload.get('JobStatus'));
        if (jobStatus == 'SUCCEEDED' || jobStatus == 'PARTIAL_SUCCESS') {
            return new PollResult(true, true, response.getBody(), null);
        }
        if (jobStatus == 'FAILED') {
            return new PollResult(true, false, null, 'AWS Textract reported a failed OCR job.');
        }
        return new PollResult(false, false, null, null);
    }

    private static PollResult pollAzure(KT_OCR_Job__c job, ProviderConfigRecord config) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildAzurePollingEndpoint(config, job.Job_Id__c));
        request.setMethod('GET');
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        ensureSuccessStatus(response);

        Map<String, Object> payload = deserializeMap(response.getBody());
        String status = stringValue(payload.get('status'));
        if (status != null) {
            status = status.toLowerCase();
        }

        if (status == 'succeeded') {
            return new PollResult(true, true, response.getBody(), null);
        }
        if (status == 'failed') {
            return new PollResult(true, false, null, 'Azure Form Recognizer reported a failed OCR job.');
        }
        return new PollResult(false, false, null, null);
    }

    private static void failJob(KT_OCR_Job__c job, Integer retryCount, String message, Boolean createManualReviewTask) {
        update new KT_OCR_Job__c(
            Id = job.Id,
            Retry_Count__c = retryCount,
            Status__c = 'Failed',
            Review_Notes__c = truncate(message, 255)
        );
        if (job.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = job.KT_DocumentVault__c,
                OCR_Status__c = 'Failed'
            );
        }
        if (createManualReviewTask) {
            createManualReviewTask(job, message);
        }
    }

    private static void createManualReviewTask(KT_OCR_Job__c job, String message) {
        insert new Task(
            OwnerId = resolveTaskOwnerId(),
            WhatId = job.Id,
            Subject = ('OCR manual review required: ' + safeLabel(job.KT_DocumentVault__r == null ? null : job.KT_DocumentVault__r.Document_Name__c, 'Document')).left(255),
            Description = message,
            ActivityDate = Date.today(),
            Priority = 'High',
            Status = 'Not Started'
        );
    }

    private static Id resolveTaskOwnerId() {
        List<Group> queues = [
            SELECT Id, Name, DeveloperName
            FROM Group
            WHERE Type = 'Queue'
            AND Id IN (SELECT QueueId FROM QueueSobject WHERE SObjectType = 'Task')
            ORDER BY Name
        ];
        for (Group queue : queues) {
            String combined = (queue.Name + ' ' + queue.DeveloperName).toLowerCase();
            if (combined.contains('hr') || combined.contains('human')) {
                return queue.Id;
            }
        }
        return queues.isEmpty() ? UserInfo.getUserId() : queues[0].Id;
    }

    private static ProviderConfigRecord getActiveProviderConfig() {
        List<KT_OCR_Provider_Config__mdt> configs = [
            SELECT Provider_Name__c, Named_Credential__c, Endpoint_Path__c, Max_Retries__c
            FROM KT_OCR_Provider_Config__mdt
            WHERE Is_Active__c = true
            LIMIT 2
        ];
        if (configs.isEmpty()) {
            throw new KT_OcrIngestionService.OcrIngestionException('No active OCR provider configuration was found.');
        }
        if (configs.size() > 1) {
            throw new KT_OcrIngestionService.OcrIngestionException('Multiple active OCR provider configurations were found.');
        }
        return toProviderConfig(configs[0]);
    }

    private static ProviderConfigRecord getProviderConfig(String providerName) {
        List<KT_OCR_Provider_Config__mdt> configs = [
            SELECT Provider_Name__c, Named_Credential__c, Endpoint_Path__c, Max_Retries__c
            FROM KT_OCR_Provider_Config__mdt
            WHERE Provider_Name__c = :providerName
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            throw new KT_OcrIngestionService.OcrIngestionException('OCR provider configuration not found for ' + providerName + '.');
        }
        return toProviderConfig(configs[0]);
    }

    private static ProviderConfigRecord toProviderConfig(KT_OCR_Provider_Config__mdt config) {
        ProviderConfigRecord record = new ProviderConfigRecord();
        record.providerName = config.Provider_Name__c;
        record.namedCredential = config.Named_Credential__c;
        record.endpointPath = config.Endpoint_Path__c;
        record.maxRetries = config.Max_Retries__c == null ? null : Integer.valueOf(config.Max_Retries__c);
        return record;
    }

    private static String buildBaseEndpoint(ProviderConfigRecord config) {
        if (String.isBlank(config.namedCredential)) {
            throw new KT_OcrIngestionService.OcrIngestionException('OCR provider configuration is missing a Named Credential.');
        }
        String path = String.isBlank(config.endpointPath) ? '' : config.endpointPath.trim();
        if (String.isBlank(path) || path == '/') {
            return 'callout:' + config.namedCredential;
        }
        if (!path.startsWith('/')) {
            path = '/' + path;
        }
        return 'callout:' + config.namedCredential + path;
    }

    private static String buildAzurePollingEndpoint(ProviderConfigRecord config, String operationLocation) {
        String relativePath = operationLocation;
        if (operationLocation != null && operationLocation.startsWith('http')) {
            Matcher matcher = Pattern.compile('https?://[^/]+(.*)').matcher(operationLocation);
            if (matcher.matches()) {
                relativePath = matcher.group(1);
            }
        }
        if (String.isBlank(relativePath)) {
            throw new KT_OcrIngestionService.OcrIngestionException('Azure polling endpoint could not be resolved.');
        }
        if (!relativePath.startsWith('/')) {
            relativePath = '/' + relativePath;
        }
        return 'callout:' + config.namedCredential + relativePath;
    }

    private static void ensureSuccessStatus(HttpResponse response) {
        Integer statusCode = response == null ? 0 : response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new KT_OcrIngestionService.OcrIngestionException('OCR polling returned HTTP ' + statusCode + '.');
        }
    }

    private static Integer currentRetryCount(KT_OCR_Job__c job) {
        return job == null || job.Retry_Count__c == null ? 0 : job.Retry_Count__c.intValue();
    }

    private static Map<String, Object> deserializeMap(String rawJson) {
        Object parsed = JSON.deserializeUntyped(rawJson);
        return parsed instanceof Map<String, Object>
            ? (Map<String, Object>) parsed
            : new Map<String, Object>{ 'payload' => parsed };
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String safeLabel(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private class ProviderConfigRecord {
        String providerName;
        String namedCredential;
        String endpointPath;
        Integer maxRetries;
    }

    private class PollResult {
        Boolean isComplete;
        Boolean isSuccess;
        String rawJson;
        String message;

        PollResult(Boolean isComplete, Boolean isSuccess, String rawJson, String message) {
            this.isComplete = isComplete;
            this.isSuccess = isSuccess;
            this.rawJson = rawJson;
            this.message = message;
        }
    }
}
