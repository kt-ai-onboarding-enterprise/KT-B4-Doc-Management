@RestResource(urlMapping='/kt/v1/ocr/callback')
global with sharing class KT_OcrCallbackHandler {
    private static final String PROVIDER_AWS = 'AWS Textract';
    private static final String PROVIDER_AZURE = 'Azure Form Recognizer';
    private static final Set<String> SUCCESS_STATUSES = new Set<String>{ 'SUCCEEDED', 'PARTIAL_SUCCESS', 'succeeded' };
    private static final Set<String> FAILURE_STATUSES = new Set<String>{ 'FAILED', 'failed', 'error' };
    @TestVisible private static Map<String, String> callbackSecretOverrides = new Map<String, String>();

    global class CallbackException extends Exception {}

    private class CallbackContext {
        String rawBody;
        Map<String, Object> outerPayload;
        Map<String, Object> effectivePayload;
        String providerName;
        String providerJobId;
        String status;
    }

    @HttpPost
    global static void handleCallback() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response == null ? new RestResponse() : RestContext.response;
        RestContext.response = response;

        try {
            CallbackContext context = buildContext(request);
            validateSignature(request, context);
            KT_OCR_Job__c job = findOcrJob(context);
            if (job == null) {
                writeResponse(response, 404, 'No matching OCR job was found for the callback payload.');
                return;
            }

            if (SUCCESS_STATUSES.contains(context.status)) {
                if (hasInlineExtractionPayload(context)) {
                    KT_OcrIngestionService.parseAndMap(job.Id, JSON.serialize(context.effectivePayload));
                    writeResponse(response, 200, 'OCR callback processed and extraction parsed.');
                    return;
                }

                System.enqueueJob(new KT_OcrPollingBatch(job.Id));
                writeResponse(response, 202, 'OCR callback accepted. Result retrieval has been queued.');
                return;
            }

            if (FAILURE_STATUSES.contains(context.status)) {
                updateFailure(job, context.providerName, 'OCR callback indicated provider failure with status ' + context.status + '.');
                writeResponse(response, 200, 'OCR callback processed as failed.');
                return;
            }

            writeResponse(response, 202, 'OCR callback acknowledged. No action was required for status ' + context.status + '.');
        } catch (CallbackException ex) {
            writeResponse(response, 400, ex.getMessage());
        } catch (SecurityException ex) {
            writeResponse(response, 401, ex.getMessage());
        } catch (Exception ex) {
            writeResponse(response, 500, ex.getMessage());
        }
    }

    private static CallbackContext buildContext(RestRequest request) {
        if (request == null || request.requestBody == null) {
            throw new CallbackException('Callback request body is required.');
        }

        CallbackContext context = new CallbackContext();
        context.rawBody = request.requestBody.toString();
        context.outerPayload = deserializePayload(context.rawBody);
        context.effectivePayload = extractEffectivePayload(context.outerPayload);
        context.providerName = detectProvider(request, context.outerPayload, context.effectivePayload);
        if (String.isBlank(context.providerName)) {
            throw new CallbackException('Unable to determine OCR provider from the callback payload.');
        }

        context.status = detectStatus(context.effectivePayload);
        context.providerJobId = detectProviderJobId(context.providerName, request, context.effectivePayload);
        if (String.isBlank(context.providerJobId)) {
            throw new CallbackException('Unable to determine the OCR provider job id from the callback payload.');
        }
        return context;
    }

    private static void validateSignature(RestRequest request, CallbackContext context) {
        String expectedSecret = resolveCallbackSecret(context.providerName);
        if (String.isBlank(expectedSecret)) {
            throw new SecurityException('No OCR callback shared secret is configured for ' + context.providerName + '.');
        }

        String providedSignature = getHeader(
            request,
            new List<String>{
                'X-KT-Signature',
                'X-KT-OCR-Signature',
                'X-Signature',
                'X-Hub-Signature-256',
                'X-Azure-Signature',
                'X-Aws-Signature'
            }
        );
        if (String.isBlank(providedSignature)) {
            throw new SecurityException('OCR callback signature header was not provided.');
        }

        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(context.rawBody), Blob.valueOf(expectedSecret));
        String expectedHex = EncodingUtil.convertToHex(mac).toLowerCase();
        String expectedBase64 = EncodingUtil.base64Encode(mac);
        String normalizedSignature = normalizeSignature(providedSignature);

        if (normalizedSignature != expectedHex && normalizedSignature != expectedBase64.toLowerCase()) {
            throw new SecurityException('OCR callback HMAC signature validation failed.');
        }
    }

    private static KT_OCR_Job__c findOcrJob(CallbackContext context) {
        if (context.providerName == PROVIDER_AZURE) {
            KT_OCR_Job__c azureJob = findAzureJob(context.providerJobId);
            if (azureJob != null) {
                return azureJob;
            }
        }

        List<KT_OCR_Job__c> jobs = [
            SELECT Id, OCR_Provider__c, Job_Id__c, Status__c, KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE Job_Id__c = :context.providerJobId
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0];
    }

    private static KT_OCR_Job__c findAzureJob(String providerJobId) {
        List<KT_OCR_Job__c> exactMatches = [
            SELECT Id, OCR_Provider__c, Job_Id__c, Status__c, KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE OCR_Provider__c = :PROVIDER_AZURE
            AND Job_Id__c = :providerJobId
            LIMIT 1
        ];
        if (!exactMatches.isEmpty()) {
            return exactMatches[0];
        }

        String suffix = normalizeAzureOperationSuffix(providerJobId);
        if (String.isBlank(suffix)) {
            return null;
        }

        for (KT_OCR_Job__c job : [
            SELECT Id, OCR_Provider__c, Job_Id__c, Status__c, KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE OCR_Provider__c = :PROVIDER_AZURE
            AND Status__c IN ('Submitted', 'Processing')
        ]) {
            if (!String.isBlank(job.Job_Id__c) && normalizeAzureOperationSuffix(job.Job_Id__c) == suffix) {
                return job;
            }
        }
        return null;
    }

    private static Boolean hasInlineExtractionPayload(CallbackContext context) {
        Map<String, Object> payload = context.effectivePayload;
        if (payload == null) {
            return false;
        }
        if (context.providerName == PROVIDER_AWS) {
            return payload.containsKey('IdentityDocuments')
                || payload.containsKey('Blocks')
                || payload.containsKey('Fields');
        }
        return payload.containsKey('analyzeResult') || payload.containsKey('fields');
    }

    private static void updateFailure(KT_OCR_Job__c job, String providerName, String message) {
        update new KT_OCR_Job__c(
            Id = job.Id,
            OCR_Provider__c = providerName,
            Status__c = 'Failed',
            Review_Notes__c = truncate(message, 255)
        );
        if (job.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = job.KT_DocumentVault__c,
                OCR_Status__c = 'Failed'
            );
        }
    }

    private static Map<String, Object> deserializePayload(String rawJson) {
        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            if (!(parsed instanceof Map<String, Object>)) {
                throw new CallbackException('OCR callback payload must be a JSON object.');
            }
            return (Map<String, Object>) parsed;
        } catch (CallbackException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new CallbackException('OCR callback payload is not valid JSON.');
        }
    }

    private static Map<String, Object> extractEffectivePayload(Map<String, Object> outerPayload) {
        if (outerPayload.containsKey('Message') && outerPayload.get('Message') instanceof String) {
            String nestedJson = String.valueOf(outerPayload.get('Message'));
            try {
                Object parsed = JSON.deserializeUntyped(nestedJson);
                if (parsed instanceof Map<String, Object>) {
                    return (Map<String, Object>) parsed;
                }
            } catch (Exception ignored) {
            }
        }
        return outerPayload;
    }

    private static String detectProvider(RestRequest request, Map<String, Object> outerPayload, Map<String, Object> effectivePayload) {
        String providerHeader = getHeader(request, new List<String>{ 'X-KT-OCR-Provider', 'X-OCR-Provider', 'Provider' });
        if (!String.isBlank(providerHeader)) {
            return normalizeProvider(providerHeader);
        }

        String topicArn = stringValue(outerPayload.get('TopicArn'));
        if (!String.isBlank(topicArn) && topicArn.toLowerCase().contains('textract')) {
            return PROVIDER_AWS;
        }

        if (effectivePayload.containsKey('JobId') || effectivePayload.containsKey('JobStatus')) {
            return PROVIDER_AWS;
        }
        if (effectivePayload.containsKey('analyzeResult')
            || effectivePayload.containsKey('operationLocation')
            || effectivePayload.containsKey('status')) {
            return PROVIDER_AZURE;
        }
        return null;
    }

    private static String detectStatus(Map<String, Object> effectivePayload) {
        String status = stringValue(effectivePayload.get('JobStatus'));
        if (!String.isBlank(status)) {
            return status;
        }
        status = stringValue(effectivePayload.get('status'));
        if (!String.isBlank(status)) {
            return status;
        }
        return 'unknown';
    }

    private static String detectProviderJobId(String providerName, RestRequest request, Map<String, Object> effectivePayload) {
        if (providerName == PROVIDER_AWS) {
            return stringValue(effectivePayload.get('JobId'));
        }

        String operationLocation = stringValue(effectivePayload.get('operationLocation'));
        if (!String.isBlank(operationLocation)) {
            return operationLocation;
        }
        operationLocation = getHeader(request, new List<String>{ 'Operation-Location', 'X-Operation-Location' });
        if (!String.isBlank(operationLocation)) {
            return operationLocation;
        }
        String jobId = stringValue(effectivePayload.get('JobId'));
        if (!String.isBlank(jobId)) {
            return jobId;
        }
        return stringValue(effectivePayload.get('id'));
    }

    private static String normalizeProvider(String providerValue) {
        String lowered = providerValue == null ? null : providerValue.toLowerCase();
        if (String.isBlank(lowered)) {
            return null;
        }
        if (lowered.contains('aws') || lowered.contains('textract')) {
            return PROVIDER_AWS;
        }
        if (lowered.contains('azure') || lowered.contains('recognizer') || lowered.contains('document intelligence')) {
            return PROVIDER_AZURE;
        }
        return providerValue;
    }

    private static String resolveCallbackSecret(String providerName) {
        if (callbackSecretOverrides.containsKey(providerName)) {
            return callbackSecretOverrides.get(providerName);
        }

        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        Schema.SObjectType settingType = describeMap.get('KT_Integration_Security__c');
        if (settingType == null) {
            settingType = describeMap.get('KT_OCR_Callback_Security__c');
        }
        if (settingType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = settingType.getDescribe().fields.getMap();
        String fieldName = providerName == PROVIDER_AWS
            ? firstExistingField(fieldMap, new List<String>{ 'AWS_OCR_Callback_Secret__c', 'AWS_Callback_Secret__c' })
            : firstExistingField(fieldMap, new List<String>{ 'Azure_OCR_Callback_Secret__c', 'Azure_Callback_Secret__c' });
        if (String.isBlank(fieldName)) {
            return null;
        }

        String query = 'SELECT ' + fieldName + ' FROM ' + settingType.getDescribe().getName() + ' LIMIT 1';
        List<SObject> rows = Database.query(query);
        if (rows.isEmpty()) {
            return null;
        }
        Object value = rows[0].get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static String firstExistingField(Map<String, Schema.SObjectField> fieldMap, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                return fieldName;
            }
        }
        return null;
    }

    private static String getHeader(RestRequest request, List<String> headerNames) {
        if (request == null || request.headers == null) {
            return null;
        }

        for (String headerName : headerNames) {
            if (request.headers.containsKey(headerName)) {
                return request.headers.get(headerName);
            }
            for (String existingHeader : request.headers.keySet()) {
                if (existingHeader != null && existingHeader.equalsIgnoreCase(headerName)) {
                    return request.headers.get(existingHeader);
                }
            }
        }
        return null;
    }

    private static String normalizeSignature(String providedSignature) {
        String normalized = providedSignature == null ? null : providedSignature.trim().toLowerCase();
        if (String.isBlank(normalized)) {
            return null;
        }
        if (normalized.startsWith('sha256=')) {
            normalized = normalized.substring(7);
        }
        return normalized;
    }

    private static String normalizeAzureOperationSuffix(String operationLocation) {
        if (String.isBlank(operationLocation)) {
            return null;
        }

        String normalized = operationLocation.trim().toLowerCase();
        if (normalized.startsWith('http')) {
            Matcher matcher = Pattern.compile('https?://[^/]+(.*)').matcher(normalized);
            if (matcher.matches()) {
                normalized = matcher.group(1);
            }
        }
        return normalized.startsWith('/') ? normalized : '/' + normalized;
    }

    private static void writeResponse(RestResponse response, Integer statusCode, String message) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => statusCode >= 200 && statusCode < 300,
            'message' => message
        }));
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}
