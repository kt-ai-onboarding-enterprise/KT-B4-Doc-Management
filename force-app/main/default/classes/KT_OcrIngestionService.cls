public with sharing class KT_OcrIngestionService {
    private static final String PROVIDER_AWS = 'AWS Textract';
    private static final String PROVIDER_AZURE = 'Azure Form Recognizer';
    private static final Integer TEXTRACT_SYNC_MAX_PAGES = 9;
    private static final Integer EXTRACTED_JSON_MAX_LENGTH = 131072;
    private static final Integer EXTRACTED_FIELDS_MAX_LENGTH = 32768;
    private static final List<String> CONTACT_LOOKUP_FIELD_CANDIDATES = new List<String>{
        'Contact__c',
        'Primary_Contact__c',
        'Onboardee_Contact__c',
        'Candidate_Contact__c',
        'PersonContactId'
    };
    @TestVisible private static Boolean enqueueAsyncPolling = true;

    public class OcrIngestionException extends Exception {}

    public class SubmitJobRequest {
        @InvocableVariable(required=true)
        public Id ocrJobId;
    }

    public class SubmitJobResult {
        @AuraEnabled @InvocableVariable public Id ocrJobId;
        @AuraEnabled @InvocableVariable public String provider;
        @AuraEnabled @InvocableVariable public String status;
        @AuraEnabled @InvocableVariable public String providerJobId;
        @AuraEnabled @InvocableVariable public Boolean asyncProcessing;
        @AuraEnabled @InvocableVariable public String message;
    }

    public class ParseResult {
        @AuraEnabled public Id ocrJobId;
        @AuraEnabled public String provider;
        @AuraEnabled public String status;
        @AuraEnabled public String documentType;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public Integer mappedFieldCount;
        @AuraEnabled public Integer highConfidenceFieldCount;
        @AuraEnabled public String message;
    }

    public class ApplyResult {
        @AuraEnabled public Id ocrJobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer acceptedFieldCount;
        @AuraEnabled public Integer skippedFieldCount;
        @AuraEnabled public Boolean onboardingUpdated;
        @AuraEnabled public Boolean contactUpdated;
        @AuraEnabled public String message;
    }

    public class ReviewField {
        @AuraEnabled public String providerFieldPath;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String targetObjectLabel;
        @AuraEnabled public String targetField;
        @AuraEnabled public String targetFieldLabel;
        @AuraEnabled public String extractedValue;
        @AuraEnabled public String currentValue;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public Decimal confidenceThreshold;
        @AuraEnabled public Boolean highConfidence;
    }

    public class ReviewData {
        @AuraEnabled public Id ocrJobId;
        @AuraEnabled public Id onboardingId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String provider;
        @AuraEnabled public String status;
        @AuraEnabled public String documentType;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public Integer fieldCount;
        @AuraEnabled public Integer highConfidenceFieldCount;
        @AuraEnabled public List<ReviewField> fields;
    }

    private class ProviderConfigRecord {
        String providerName;
        String namedCredential;
        String endpointPath;
        Integer pollingIntervalSeconds;
        Integer maxRetries;
    }

    private class ProviderValue {
        String value;
        Decimal confidence;

        ProviderValue(String value, Decimal confidence) {
            this.value = value;
            this.confidence = confidence;
        }
    }

    @InvocableMethod(
        label='Submit KT OCR Job'
        description='Submits a KT OCR job to the active configured provider.'
    )
    public static List<SubmitJobResult> submitJob(List<SubmitJobRequest> requests) {
        List<SubmitJobResult> results = new List<SubmitJobResult>();
        if (requests == null) {
            return results;
        }

        for (SubmitJobRequest request : requests) {
            SubmitJobResult result = new SubmitJobResult();
            result.ocrJobId = request == null ? null : request.ocrJobId;
            result.status = 'Failed';
            result.asyncProcessing = false;
            result.message = 'ocrJobId is required.';

            if (request == null || request.ocrJobId == null) {
                results.add(result);
                continue;
            }

            try {
                result = submitJobInternal(request.ocrJobId, null);
            } catch (Exception ex) {
                result = new SubmitJobResult();
                result.ocrJobId = request.ocrJobId;
                result.status = 'Failed';
                result.asyncProcessing = false;
                result.message = ex.getMessage();
            }
            results.add(result);
        }
        return results;
    }

    @AuraEnabled
    public static SubmitJobResult submitJob(Id ocrJobId) {
        try {
            return submitJobInternal(ocrJobId, null);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public static SubmitJobResult submitToTextract(Id ocrJobId) {
        return submitJobInternal(ocrJobId, PROVIDER_AWS);
    }

    public static SubmitJobResult submitToAzure(Id ocrJobId) {
        return submitJobInternal(ocrJobId, PROVIDER_AZURE);
    }

    @AuraEnabled
    public static ParseResult parseAndMap(Id ocrJobId, String rawJson) {
        try {
            return parseAndMapInternal(ocrJobId, rawJson, null);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public static ParseResult parseAndMap(Id ocrJobId) {
        KT_OCR_Job__c job = loadJob(ocrJobId);
        return parseAndMapInternal(ocrJobId, job.Extracted_JSON__c, job.OCR_Provider__c);
    }

    @AuraEnabled
    public static ApplyResult applyExtraction(Id ocrJobId, List<String> acceptedFieldPaths) {
        try {
            return applyExtractionInternal(ocrJobId, acceptedFieldPaths, null);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public static ApplyResult applyExtraction(Id ocrJobId, List<String> acceptedFieldPaths, Id contactId) {
        return applyExtractionInternal(ocrJobId, acceptedFieldPaths, contactId);
    }

    @AuraEnabled(cacheable=true)
    public static ReviewData getReviewData(Id ocrJobId) {
        try {
            return getReviewDataInternal(ocrJobId, null);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public static ReviewData getReviewData(Id ocrJobId, Id contactId) {
        return getReviewDataInternal(ocrJobId, contactId);
    }

    private static SubmitJobResult submitJobInternal(Id ocrJobId, String providerOverride) {
        if (ocrJobId == null) {
            throw new OcrIngestionException('ocrJobId is required.');
        }

        KT_OCR_Job__c job = loadJob(ocrJobId);
        ContentVersion version = loadLatestVersion(job.KT_DocumentVault__r == null ? null : job.KT_DocumentVault__r.Content_Document_Id__c);
        ProviderConfigRecord config = String.isBlank(providerOverride)
            ? getActiveProviderConfig()
            : getProviderConfig(providerOverride);

        if (config.providerName == PROVIDER_AWS) {
            return submitToTextractInternal(job, version, config);
        }
        if (config.providerName == PROVIDER_AZURE) {
            return submitToAzureInternal(job, version, config);
        }
        throw new OcrIngestionException('Unsupported OCR provider: ' + config.providerName);
    }

    private static SubmitJobResult submitToTextractInternal(
        KT_OCR_Job__c job,
        ContentVersion version,
        ProviderConfigRecord config
    ) {
        Boolean asyncProcessing = estimatePageCount(version) > TEXTRACT_SYNC_MAX_PAGES;
        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildEndpoint(config));
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-amz-json-1.1');
        request.setHeader('X-Amz-Target', asyncProcessing ? 'Textract.StartDocumentAnalysis' : 'Textract.AnalyzeDocument');
        request.setTimeout(120000);
        request.setBody(JSON.serialize(new Map<String, Object>{
            'Document' => new Map<String, Object>{ 'Bytes' => EncodingUtil.base64Encode(version.VersionData) },
            'FeatureTypes' => new List<String>{ 'FORMS' }
        }));

        try {
            HttpResponse response = new Http().send(request);
            ensureSuccessStatus(response);
            String responseBody = response.getBody();
            String providerJobId = extractAsyncJobId(responseBody, 'JobId');

            if (asyncProcessing || !String.isBlank(providerJobId)) {
                updateJobProcessing(job.Id, PROVIDER_AWS, providerJobId, 'Submitted to AWS Textract for asynchronous processing.');
                if (enqueueAsyncPolling) {
                    System.enqueueJob(new KT_OcrPollingBatch(job.Id));
                }
                return buildSubmitResult(job.Id, PROVIDER_AWS, 'Processing', providerJobId, true, 'OCR job submitted to AWS Textract.');
            }

            ParseResult parseResult = parseAndMapInternal(job.Id, responseBody, PROVIDER_AWS);
            return buildSubmitResult(job.Id, PROVIDER_AWS, parseResult.status, null, false, parseResult.message);
        } catch (Exception ex) {
            markJobFailed(job.Id, PROVIDER_AWS, ex.getMessage(), null);
            throw ex;
        }
    }

    private static SubmitJobResult submitToAzureInternal(
        KT_OCR_Job__c job,
        ContentVersion version,
        ProviderConfigRecord config
    ) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildEndpoint(config));
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/octet-stream');
        request.setTimeout(120000);
        request.setBodyAsBlob(version.VersionData);

        try {
            HttpResponse response = new Http().send(request);
            ensureSuccessStatus(response);
            String operationLocation = response.getHeader('Operation-Location');
            if (String.isBlank(operationLocation)) {
                operationLocation = extractAsyncJobId(response.getBody(), 'operationLocation');
            }
            if (String.isBlank(operationLocation)) {
                throw new OcrIngestionException('Azure Form Recognizer did not return an Operation-Location header.');
            }

            updateJobProcessing(job.Id, PROVIDER_AZURE, operationLocation, 'Submitted to Azure Form Recognizer for asynchronous processing.');
            if (enqueueAsyncPolling) {
                System.enqueueJob(new KT_OcrPollingBatch(job.Id));
            }
            return buildSubmitResult(job.Id, PROVIDER_AZURE, 'Processing', operationLocation, true, 'OCR job submitted to Azure Form Recognizer.');
        } catch (Exception ex) {
            markJobFailed(job.Id, PROVIDER_AZURE, ex.getMessage(), null);
            throw ex;
        }
    }

    private static ParseResult parseAndMapInternal(Id ocrJobId, String rawJson, String providerOverride) {
        if (ocrJobId == null) {
            throw new OcrIngestionException('ocrJobId is required.');
        }
        if (String.isBlank(rawJson)) {
            throw new OcrIngestionException('OCR response payload is required.');
        }

        KT_OCR_Job__c job = loadJob(ocrJobId);
        String providerName = String.isBlank(providerOverride) ? job.OCR_Provider__c : providerOverride;
        if (String.isBlank(providerName)) {
            providerName = getActiveProviderConfig().providerName;
        }

        Map<String, Object> payload;
        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            payload = parsed instanceof Map<String, Object>
                ? (Map<String, Object>) parsed
                : new Map<String, Object>{ 'payload' => parsed };
        } catch (Exception ex) {
            markJobFailed(job.Id, providerName, 'OCR response could not be parsed as JSON.', rawJson);
            throw new OcrIngestionException('OCR response could not be parsed as JSON.');
        }

        Map<String, ProviderValue> providerValues = providerName == PROVIDER_AWS
            ? extractAwsFieldValues(payload)
            : extractAzureFieldValues(payload);
        String documentType = normalizeDocumentType(detectDocumentType(providerName, payload, providerValues.keySet()));
        if (String.isBlank(documentType)) {
            markJobFailed(job.Id, providerName, 'OCR provider did not return a supported document type.', rawJson);
            throw new OcrIngestionException('OCR provider did not return a supported document type.');
        }

        List<KT_OCR_FieldMapping__mdt> mappings = [
            SELECT Document_Type__c, OCR_Provider__c, Provider_Field_Path__c,
                   Target_Object__c, Target_Field__c, Confidence_Threshold__c
            FROM KT_OCR_FieldMapping__mdt
            WHERE Document_Type__c = :documentType
            AND OCR_Provider__c = :providerName
            ORDER BY DeveloperName
        ];
        if (mappings.isEmpty()) {
            markJobFailed(job.Id, providerName, 'No OCR field mappings were found for ' + documentType + '.', rawJson);
            throw new OcrIngestionException('No OCR field mappings were found for ' + documentType + '.');
        }

        List<Object> mappedFields = new List<Object>();
        Decimal totalConfidence = 0;
        Integer matchedFieldCount = 0;
        Integer highConfidenceFieldCount = 0;

        for (KT_OCR_FieldMapping__mdt mapping : mappings) {
            ProviderValue providerValue = providerValues.get(mapping.Provider_Field_Path__c);
            if (providerValue == null || String.isBlank(providerValue.value)) {
                continue;
            }

            Decimal threshold = mapping.Confidence_Threshold__c;
            Decimal confidence = providerValue.confidence == null ? 0 : providerValue.confidence.setScale(2);
            Boolean highConfidence = threshold == null || confidence >= threshold;
            if (highConfidence) {
                highConfidenceFieldCount++;
            }

            mappedFields.add(new Map<String, Object>{
                'providerFieldPath' => mapping.Provider_Field_Path__c,
                'targetObject' => mapping.Target_Object__c,
                'targetField' => mapping.Target_Field__c,
                'value' => providerValue.value,
                'confidence' => confidence,
                'confidenceThreshold' => threshold,
                'highConfidence' => highConfidence
            });
            totalConfidence += confidence;
            matchedFieldCount++;
        }

        if (matchedFieldCount == 0) {
            markJobFailed(job.Id, providerName, 'No OCR response fields matched the configured field mappings.', rawJson);
            throw new OcrIngestionException('No OCR response fields matched the configured field mappings.');
        }

        Decimal overallConfidence = (totalConfidence / matchedFieldCount).setScale(2);
        update new KT_OCR_Job__c(
            Id = job.Id,
            OCR_Provider__c = providerName,
            Status__c = 'Review Required',
            Extracted_JSON__c = truncate(rawJson, EXTRACTED_JSON_MAX_LENGTH),
            Extracted_Fields__c = truncate(JSON.serialize(mappedFields), EXTRACTED_FIELDS_MAX_LENGTH),
            Confidence_Score__c = overallConfidence,
            Document_Type_Detected__c = documentType,
            Review_Notes__c = null
        );
        if (job.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = job.KT_DocumentVault__c,
                OCR_Status__c = 'Review Required'
            );
        }

        publishOcrCompleteEvent(job.Id, job.KT_Onboarding__c, documentType, overallConfidence, 'Review Required');

        ParseResult result = new ParseResult();
        result.ocrJobId = job.Id;
        result.provider = providerName;
        result.status = 'Review Required';
        result.documentType = documentType;
        result.confidenceScore = overallConfidence;
        result.mappedFieldCount = matchedFieldCount;
        result.highConfidenceFieldCount = highConfidenceFieldCount;
        result.message = 'OCR extraction parsed successfully and is ready for HR review.';
        return result;
    }

    private static ApplyResult applyExtractionInternal(Id ocrJobId, List<String> acceptedFieldPaths, Id contactId) {
        if (ocrJobId == null) {
            throw new OcrIngestionException('ocrJobId is required.');
        }

        KT_OCR_Job__c job = [
            SELECT Id, KT_DocumentVault__c, KT_Onboarding__c, Extracted_Fields__c, Status__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJobId
            LIMIT 1
            FOR UPDATE
        ];
        if (String.isBlank(job.Extracted_Fields__c)) {
            throw new OcrIngestionException('No extracted OCR fields are available to apply.');
        }

        Object parsedFields = JSON.deserializeUntyped(job.Extracted_Fields__c);
        if (!(parsedFields instanceof List<Object>)) {
            throw new OcrIngestionException('Extracted OCR fields are not in the expected format.');
        }

        Set<String> acceptedKeys = new Set<String>();
        if (acceptedFieldPaths != null) {
            for (String acceptedPath : acceptedFieldPaths) {
                if (!String.isBlank(acceptedPath)) {
                    acceptedKeys.add(acceptedPath.trim().toLowerCase());
                }
            }
        }

        Id resolvedContactId = contactId == null ? resolveRelatedContactId(job.KT_Onboarding__c) : contactId;
        Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
        Integer acceptedFieldCount = 0;
        Integer skippedFieldCount = 0;
        Set<String> acceptedLog = new Set<String>();
        Set<String> skippedLog = new Set<String>();

        for (Object rowObject : (List<Object>) parsedFields) {
            if (!(rowObject instanceof Map<String, Object>)) {
                skippedFieldCount++;
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObject;
            String providerFieldPath = stringValue(row.get('providerFieldPath'));
            String targetObject = stringValue(row.get('targetObject'));
            String targetField = stringValue(row.get('targetField'));
            Boolean highConfidence = row.containsKey('highConfidence')
                ? Boolean.valueOf(String.valueOf(row.get('highConfidence')))
                : false;
            Boolean isAccepted = acceptedKeys.isEmpty()
                ? highConfidence
                : acceptedKeys.contains(providerFieldPath == null ? null : providerFieldPath.toLowerCase())
                    || acceptedKeys.contains((targetObject + '.' + targetField).toLowerCase());

            if (!isAccepted) {
                skippedFieldCount++;
                continue;
            }

            Id targetRecordId = resolveTargetRecordId(targetObject, job.KT_Onboarding__c, resolvedContactId);
            if (targetRecordId == null) {
                skippedFieldCount++;
                skippedLog.add(providerFieldPath);
                continue;
            }

            SObject targetRecord = getOrCreateTargetRecord(recordsToUpdate, targetObject, targetRecordId);
            Map<String, Schema.SObjectField> fieldMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
            if (!fieldMap.containsKey(targetField)) {
                skippedFieldCount++;
                skippedLog.add(providerFieldPath);
                continue;
            }

            Object convertedValue = convertFieldValue(stringValue(row.get('value')), fieldMap.get(targetField).getDescribe());
            targetRecord.put(targetField, convertedValue);
            recordsToUpdate.put(targetObject, targetRecord);
            acceptedFieldCount++;
            acceptedLog.add(providerFieldPath);
        }

        if (recordsToUpdate.isEmpty()) {
            throw new OcrIngestionException('No accepted OCR fields could be applied to Salesforce records.');
        }

        update recordsToUpdate.values();

        update new KT_OCR_Job__c(
            Id = job.Id,
            Status__c = 'Accepted',
            Reviewed_By__c = UserInfo.getUserId(),
            Reviewed_At__c = System.now(),
            Review_Notes__c = buildReviewNotes(acceptedLog, skippedLog)
        );
        if (job.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = job.KT_DocumentVault__c,
                OCR_Status__c = 'Accepted'
            );
        }

        ApplyResult result = new ApplyResult();
        result.ocrJobId = job.Id;
        result.status = 'Accepted';
        result.acceptedFieldCount = acceptedFieldCount;
        result.skippedFieldCount = skippedFieldCount;
        result.onboardingUpdated = recordsToUpdate.containsKey('KT_Onboarding__c');
        result.contactUpdated = recordsToUpdate.containsKey('Contact');
        result.message = 'Accepted OCR fields were applied successfully.';
        return result;
    }

    private static ReviewData getReviewDataInternal(Id ocrJobId, Id contactId) {
        if (ocrJobId == null) {
            throw new OcrIngestionException('ocrJobId is required.');
        }

        KT_OCR_Job__c job = [
            SELECT Id, KT_Onboarding__c, OCR_Provider__c, Status__c, Document_Type_Detected__c,
                   Confidence_Score__c, Extracted_Fields__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJobId
            LIMIT 1
        ];
        if (String.isBlank(job.Extracted_Fields__c)) {
            throw new OcrIngestionException('No extracted OCR fields are available for review.');
        }

        Object parsedFields = JSON.deserializeUntyped(job.Extracted_Fields__c);
        if (!(parsedFields instanceof List<Object>)) {
            throw new OcrIngestionException('Extracted OCR fields are not in the expected format.');
        }

        Id resolvedContactId = contactId == null ? resolveRelatedContactId(job.KT_Onboarding__c) : contactId;
        Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();
        for (Object rowObject : (List<Object>) parsedFields) {
            Map<String, Object> row = asMap(rowObject);
            if (row == null) {
                continue;
            }

            String targetObject = stringValue(row.get('targetObject'));
            String targetField = stringValue(row.get('targetField'));
            if (String.isBlank(targetObject) || String.isBlank(targetField)) {
                continue;
            }

            if (!fieldsByObject.containsKey(targetObject)) {
                fieldsByObject.put(targetObject, new Set<String>());
            }
            fieldsByObject.get(targetObject).add(targetField);
        }

        Map<String, Map<String, String>> currentValues = loadReviewCurrentValues(
            job.KT_Onboarding__c,
            resolvedContactId,
            fieldsByObject
        );
        ReviewData result = new ReviewData();
        result.ocrJobId = job.Id;
        result.onboardingId = job.KT_Onboarding__c;
        result.contactId = resolvedContactId;
        result.provider = job.OCR_Provider__c;
        result.status = job.Status__c;
        result.documentType = job.Document_Type_Detected__c;
        result.confidenceScore = job.Confidence_Score__c;
        result.fields = new List<ReviewField>();

        Integer highConfidenceFieldCount = 0;
        for (Object rowObject : (List<Object>) parsedFields) {
            Map<String, Object> row = asMap(rowObject);
            if (row == null) {
                continue;
            }

            ReviewField reviewField = new ReviewField();
            reviewField.providerFieldPath = stringValue(row.get('providerFieldPath'));
            reviewField.targetObject = stringValue(row.get('targetObject'));
            reviewField.targetField = stringValue(row.get('targetField'));
            reviewField.extractedValue = stringValue(row.get('value'));
            reviewField.confidence = normalizeConfidence(row.get('confidence'));
            reviewField.confidenceThreshold = normalizeConfidence(row.get('confidenceThreshold'));
            reviewField.highConfidence = row.containsKey('highConfidence')
                ? Boolean.valueOf(String.valueOf(row.get('highConfidence')))
                : reviewField.confidenceThreshold == null
                    || (reviewField.confidence != null && reviewField.confidence >= reviewField.confidenceThreshold);

            if (reviewField.highConfidence) {
                highConfidenceFieldCount++;
            }

            Schema.SObjectType objectType = String.isBlank(reviewField.targetObject)
                ? null
                : Schema.getGlobalDescribe().get(reviewField.targetObject);
            if (objectType != null) {
                reviewField.targetObjectLabel = objectType.getDescribe().getLabel();
                Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
                if (fieldMap.containsKey(reviewField.targetField)) {
                    reviewField.targetFieldLabel = fieldMap.get(reviewField.targetField).getDescribe().getLabel();
                }
            }
            if (String.isBlank(reviewField.targetObjectLabel)) {
                reviewField.targetObjectLabel = reviewField.targetObject;
            }
            if (String.isBlank(reviewField.targetFieldLabel)) {
                reviewField.targetFieldLabel = reviewField.targetField;
            }

            Map<String, String> objectValues = currentValues.get(reviewField.targetObject);
            reviewField.currentValue = objectValues == null || String.isBlank(reviewField.targetField)
                ? null
                : objectValues.get(reviewField.targetField);
            result.fields.add(reviewField);
        }

        result.fieldCount = result.fields.size();
        result.highConfidenceFieldCount = highConfidenceFieldCount;
        return result;
    }

    private static KT_OCR_Job__c loadJob(Id ocrJobId) {
        List<KT_OCR_Job__c> jobs = [
            SELECT Id, KT_DocumentVault__c, KT_Onboarding__c, OCR_Provider__c, Job_Id__c, Status__c,
                   Extracted_JSON__c, Extracted_Fields__c, Confidence_Score__c, Document_Type_Detected__c,
                   KT_DocumentVault__r.Content_Document_Id__c, KT_DocumentVault__r.Document_Name__c
            FROM KT_OCR_Job__c
            WHERE Id = :ocrJobId
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            throw new OcrIngestionException('KT_OCR_Job__c record was not found.');
        }
        return jobs[0];
    }

    private static ContentVersion loadLatestVersion(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            throw new OcrIngestionException('The OCR job does not have a document to process.');
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, PathOnClient, FileType, FileExtension, ContentSize, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new OcrIngestionException('The source document content could not be found.');
        }
        return versions[0];
    }

    private static ProviderConfigRecord getActiveProviderConfig() {
        List<KT_OCR_Provider_Config__mdt> configs = [
            SELECT Provider_Name__c, Named_Credential__c, Endpoint_Path__c,
                   Async_Polling_Interval__c, Max_Retries__c, Is_Active__c
            FROM KT_OCR_Provider_Config__mdt
            WHERE Is_Active__c = true
        ];
        if (configs.isEmpty()) {
            throw new OcrIngestionException('No active OCR provider configuration was found.');
        }
        if (configs.size() > 1) {
            throw new OcrIngestionException('Multiple active OCR provider configurations were found.');
        }
        return toProviderConfig(configs[0]);
    }

    private static ProviderConfigRecord getProviderConfig(String providerName) {
        List<KT_OCR_Provider_Config__mdt> configs = [
            SELECT Provider_Name__c, Named_Credential__c, Endpoint_Path__c,
                   Async_Polling_Interval__c, Max_Retries__c, Is_Active__c
            FROM KT_OCR_Provider_Config__mdt
            WHERE Provider_Name__c = :providerName
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            throw new OcrIngestionException('OCR provider configuration not found for ' + providerName + '.');
        }
        return toProviderConfig(configs[0]);
    }

    private static ProviderConfigRecord toProviderConfig(KT_OCR_Provider_Config__mdt config) {
        ProviderConfigRecord record = new ProviderConfigRecord();
        record.providerName = config.Provider_Name__c;
        record.namedCredential = config.Named_Credential__c;
        record.endpointPath = config.Endpoint_Path__c;
        record.pollingIntervalSeconds = config.Async_Polling_Interval__c == null
            ? null
            : Integer.valueOf(config.Async_Polling_Interval__c);
        record.maxRetries = config.Max_Retries__c == null ? null : Integer.valueOf(config.Max_Retries__c);
        return record;
    }

    private static String buildEndpoint(ProviderConfigRecord config) {
        if (String.isBlank(config.namedCredential)) {
            throw new OcrIngestionException('OCR provider configuration is missing a Named Credential.');
        }

        String endpoint = 'callout:' + config.namedCredential;
        String path = String.isBlank(config.endpointPath) ? '' : config.endpointPath.trim();
        if (String.isBlank(path) || path == '/') {
            return endpoint;
        }
        if (!path.startsWith('/')) {
            path = '/' + path;
        }
        return endpoint + path;
    }

    private static void ensureSuccessStatus(HttpResponse response) {
        Integer statusCode = response == null ? 0 : response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new OcrIngestionException('OCR provider returned HTTP ' + statusCode + '.');
        }
    }

    private static SubmitJobResult buildSubmitResult(
        Id ocrJobId,
        String providerName,
        String status,
        String providerJobId,
        Boolean asyncProcessing,
        String message
    ) {
        SubmitJobResult result = new SubmitJobResult();
        result.ocrJobId = ocrJobId;
        result.provider = providerName;
        result.status = status;
        result.providerJobId = providerJobId;
        result.asyncProcessing = asyncProcessing;
        result.message = message;
        return result;
    }

    private static void updateJobProcessing(Id jobId, String providerName, String providerJobId, String reviewNotes) {
        KT_OCR_Job__c updateJob = new KT_OCR_Job__c(
            Id = jobId,
            OCR_Provider__c = providerName,
            Job_Id__c = providerJobId,
            Status__c = 'Processing',
            Review_Notes__c = reviewNotes
        );
        update updateJob;

        KT_OCR_Job__c refreshedJob = [
            SELECT KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];
        if (refreshedJob.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = refreshedJob.KT_DocumentVault__c,
                OCR_Status__c = 'Processing'
            );
        }
    }

    private static void markJobFailed(Id jobId, String providerName, String message, String rawJson) {
        KT_OCR_Job__c job = [
            SELECT Id, KT_DocumentVault__c
            FROM KT_OCR_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        update new KT_OCR_Job__c(
            Id = job.Id,
            OCR_Provider__c = providerName,
            Status__c = 'Failed',
            Review_Notes__c = truncate(message, 255),
            Extracted_JSON__c = rawJson == null ? null : truncate(rawJson, EXTRACTED_JSON_MAX_LENGTH)
        );
        if (job.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = job.KT_DocumentVault__c,
                OCR_Status__c = 'Failed'
            );
        }
        publishOcrCompleteEvent(job.Id, null, null, null, 'Failed');
    }

    private static Integer estimatePageCount(ContentVersion version) {
        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        if (extension == 'jpg' || extension == 'jpeg' || extension == 'png') {
            return 1;
        }

        if (extension == 'pdf') {
            try {
                String body = version.VersionData.toString();
                Matcher matcher = Pattern.compile('/Type\\s*/Page\\b').matcher(body);
                Integer count = 0;
                while (matcher.find()) {
                    count++;
                }
                if (count > 0) {
                    return count;
                }
            } catch (Exception ignored) {
            }
        }

        return TEXTRACT_SYNC_MAX_PAGES + 1;
    }

    private static Map<String, ProviderValue> extractAwsFieldValues(Map<String, Object> payload) {
        Map<String, ProviderValue> values = new Map<String, ProviderValue>();
        if (payload.containsKey('IdentityDocuments')) {
            Object identityDocuments = payload.get('IdentityDocuments');
            if (identityDocuments instanceof List<Object> && !((List<Object>) identityDocuments).isEmpty()) {
                Object documentObject = ((List<Object>) identityDocuments)[0];
                if (documentObject instanceof Map<String, Object>) {
                    Map<String, Object> document = (Map<String, Object>) documentObject;
                    parseFieldCollection(document.get('IdentityDocumentFields'), values);
                }
            }
        }
        if (values.isEmpty()) {
            parseFieldCollection(payload.get('Fields'), values);
        }
        if (values.isEmpty()) {
            parseFlexibleFieldContainer(payload.get('fields'), values);
        }
        return values;
    }

    private static Map<String, ProviderValue> extractAzureFieldValues(Map<String, Object> payload) {
        Map<String, ProviderValue> values = new Map<String, ProviderValue>();
        Map<String, Object> fields = null;

        Map<String, Object> analyzeResult = asMap(payload.get('analyzeResult'));
        if (analyzeResult != null) {
            List<Object> documents = asList(analyzeResult.get('documents'));
            if (!documents.isEmpty()) {
                Map<String, Object> firstDocument = asMap(documents[0]);
                fields = firstDocument == null ? null : asMap(firstDocument.get('fields'));
            }
        }
        if (fields == null) {
            fields = asMap(payload.get('fields'));
        }

        if (fields == null) {
            return values;
        }

        for (String fieldPath : fields.keySet()) {
            Map<String, Object> fieldValue = asMap(fields.get(fieldPath));
            if (fieldValue == null) {
                values.put(fieldPath, new ProviderValue(stringValue(fields.get(fieldPath)), null));
                continue;
            }

            String value = firstNonBlank(new List<String>{
                stringValue(fieldValue.get('content')),
                stringValue(fieldValue.get('valueString')),
                stringValue(fieldValue.get('valueDate')),
                stringValue(fieldValue.get('valueDateTime')),
                stringValue(fieldValue.get('valueCountryRegion')),
                stringValue(fieldValue.get('valuePhoneNumber')),
                stringValue(fieldValue.get('valueInteger')),
                stringValue(fieldValue.get('valueNumber'))
            });
            if (String.isBlank(value) && fieldValue.containsKey('valueAddress')) {
                Map<String, Object> addressValue = asMap(fieldValue.get('valueAddress'));
                value = addressValue == null
                    ? null
                    : firstNonBlank(new List<String>{
                        stringValue(addressValue.get('streetAddress')),
                        stringValue(addressValue.get('city')),
                        stringValue(addressValue.get('content'))
                    });
            }

            values.put(fieldPath, new ProviderValue(value, normalizeConfidence(fieldValue.get('confidence'))));
        }
        return values;
    }

    private static void parseFieldCollection(Object collectionObject, Map<String, ProviderValue> values) {
        List<Object> rows = asList(collectionObject);
        for (Object rowObject : rows) {
            Map<String, Object> row = asMap(rowObject);
            if (row == null) {
                continue;
            }

            String fieldPath = firstNonBlank(new List<String>{
                extractNestedString(row, 'Type.Text'),
                extractNestedString(row, 'type.text'),
                stringValue(row.get('field')),
                stringValue(row.get('key')),
                stringValue(row.get('Type'))
            });
            String value = firstNonBlank(new List<String>{
                extractNestedString(row, 'ValueDetection.Text'),
                extractNestedString(row, 'Value.Text'),
                extractNestedString(row, 'value.content'),
                stringValue(row.get('value'))
            });
            Decimal confidence = firstNonNullDecimal(new List<Decimal>{
                normalizeConfidence(extractNestedValue(row, 'ValueDetection.Confidence')),
                normalizeConfidence(extractNestedValue(row, 'Value.Confidence')),
                normalizeConfidence(row.get('confidence'))
            });
            if (!String.isBlank(fieldPath)) {
                values.put(fieldPath, new ProviderValue(value, confidence));
            }
        }
    }

    private static void parseFlexibleFieldContainer(Object fieldContainer, Map<String, ProviderValue> values) {
        Map<String, Object> fieldMap = asMap(fieldContainer);
        if (fieldMap == null) {
            return;
        }

        for (String fieldPath : fieldMap.keySet()) {
            Object rawValue = fieldMap.get(fieldPath);
            Map<String, Object> rawMap = asMap(rawValue);
            String value = rawMap == null
                ? stringValue(rawValue)
                : firstNonBlank(new List<String>{
                    stringValue(rawMap.get('content')),
                    stringValue(rawMap.get('value')),
                    stringValue(rawMap.get('text'))
                });
            Decimal confidence = rawMap == null ? null : normalizeConfidence(rawMap.get('confidence'));
            values.put(fieldPath, new ProviderValue(value, confidence));
        }
    }

    private static String detectDocumentType(String providerName, Map<String, Object> payload, Set<String> providerFieldPaths) {
        String rawDocumentType;
        if (providerName == PROVIDER_AWS) {
            rawDocumentType = firstNonBlank(new List<String>{
                stringValue(payload.get('DocumentType')),
                stringValue(extractNestedValue(payload, 'IdentityDocuments.0.DocumentType')),
                stringValue(extractNestedValue(payload, 'IdentityDocuments.0.DocumentType.Text'))
            });
        } else {
            rawDocumentType = firstNonBlank(new List<String>{
                stringValue(extractNestedValue(payload, 'analyzeResult.documents.0.docType')),
                stringValue(payload.get('docType')),
                stringValue(payload.get('DocumentType'))
            });
        }

        if (!String.isBlank(rawDocumentType)) {
            return rawDocumentType;
        }

        Set<String> loweredKeys = new Set<String>();
        for (String providerFieldPath : providerFieldPaths) {
            loweredKeys.add(providerFieldPath == null ? null : providerFieldPath.toLowerCase());
        }
        if (loweredKeys.contains('certtype') || loweredKeys.contains('issuer') || loweredKeys.contains('validfrom')) {
            return 'Professional Certificate';
        }
        if (loweredKeys.contains('address')) {
            return 'Driver\'s License';
        }
        if (loweredKeys.contains('nationality')) {
            return 'Passport';
        }
        return null;
    }

    private static String normalizeDocumentType(String rawDocumentType) {
        if (String.isBlank(rawDocumentType)) {
            return null;
        }

        String lowered = rawDocumentType.toLowerCase();
        if (lowered.contains('passport')) {
            return 'Passport';
        }
        if (lowered.contains('driver') || lowered.contains('licence') || lowered.contains('license')) {
            return 'Driver\'s License';
        }
        if (lowered.contains('certificate') || lowered.contains('professional')) {
            return 'Professional Certificate';
        }
        return rawDocumentType;
    }

    private static void publishOcrCompleteEvent(
        Id ocrJobId,
        Id onboardingId,
        String documentType,
        Decimal confidenceScore,
        String status
    ) {
        Schema.SObjectType eventType = Schema.getGlobalDescribe().get('KT_OCR_Job_Complete__e');
        if (eventType == null) {
            return;
        }

        SObject eventRecord = eventType.newSObject();
        Map<String, Schema.SObjectField> fieldMap = eventType.getDescribe().fields.getMap();
        if (fieldMap.containsKey('OcrJobId__c')) {
            eventRecord.put('OcrJobId__c', ocrJobId == null ? null : String.valueOf(ocrJobId));
        }
        if (fieldMap.containsKey('OnboardingId__c')) {
            eventRecord.put('OnboardingId__c', onboardingId == null ? null : String.valueOf(onboardingId));
        }
        if (fieldMap.containsKey('Status__c')) {
            eventRecord.put('Status__c', status);
        }
        if (fieldMap.containsKey('DocumentType__c')) {
            eventRecord.put('DocumentType__c', documentType);
        }
        if (fieldMap.containsKey('ConfidenceScore__c')) {
            eventRecord.put('ConfidenceScore__c', confidenceScore);
        }
        EventBus.publish(eventRecord);
    }

    private static Id resolveTargetRecordId(String targetObject, Id onboardingId, Id contactId) {
        if (targetObject == 'KT_Onboarding__c') {
            return onboardingId;
        }
        if (targetObject == 'Contact') {
            return contactId;
        }
        return null;
    }

    private static Map<String, Map<String, String>> loadReviewCurrentValues(
        Id onboardingId,
        Id contactId,
        Map<String, Set<String>> fieldsByObject
    ) {
        Map<String, Map<String, String>> valuesByObject = new Map<String, Map<String, String>>();
        for (String targetObject : fieldsByObject.keySet()) {
            Id targetRecordId = resolveTargetRecordId(targetObject, onboardingId, contactId);
            if (targetRecordId == null) {
                continue;
            }

            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(targetObject);
            if (objectType == null) {
                continue;
            }

            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            Map<String, String> objectValues = new Map<String, String>();
            for (String fieldName : fieldsByObject.get(targetObject)) {
                if (!fieldMap.containsKey(fieldName)) {
                    continue;
                }

                try {
                    SObject currentRecord = Database.query(
                        'SELECT ' + fieldName
                        + ' FROM ' + targetObject
                        + ' WHERE Id = :targetRecordId LIMIT 1'
                    );
                    objectValues.put(fieldName, stringValue(currentRecord.get(fieldName)));
                } catch (Exception ignored) {
                }
            }
            valuesByObject.put(targetObject, objectValues);
        }
        return valuesByObject;
    }

    private static Id resolveRelatedContactId(Id onboardingId) {
        if (onboardingId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.KT_Onboarding__c.fields.getMap();
        List<String> availableLookupFields = new List<String>();
        for (String candidate : CONTACT_LOOKUP_FIELD_CANDIDATES) {
            if (fieldMap.containsKey(candidate)) {
                availableLookupFields.add(candidate);
            }
        }
        if (availableLookupFields.isEmpty()) {
            return null;
        }

        SObject onboarding = Database.query(
            'SELECT ' + String.join(availableLookupFields, ',')
            + ' FROM KT_Onboarding__c WHERE Id = :onboardingId LIMIT 1'
        );
        for (String fieldName : availableLookupFields) {
            Object fieldValue = onboarding.get(fieldName);
            if (fieldValue != null) {
                return (Id) fieldValue;
            }
        }
        return null;
    }

    private static SObject getOrCreateTargetRecord(Map<String, SObject> recordsToUpdate, String targetObject, Id recordId) {
        if (recordsToUpdate.containsKey(targetObject)) {
            return recordsToUpdate.get(targetObject);
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(targetObject);
        if (objectType == null) {
            throw new OcrIngestionException('Unsupported target object: ' + targetObject);
        }

        SObject record = objectType.newSObject(recordId);
        recordsToUpdate.put(targetObject, record);
        return record;
    }

    private static Object convertFieldValue(String value, Schema.DescribeFieldResult describe) {
        if (value == null) {
            return null;
        }

        Schema.DisplayType displayType = describe.getType();
        if (displayType == Schema.DisplayType.Boolean) {
            return Boolean.valueOf(value);
        }
        if (displayType == Schema.DisplayType.Date) {
            return Date.valueOf(value);
        }
        if (displayType == Schema.DisplayType.DateTime) {
            return DateTime.valueOf(value);
        }
        if (displayType == Schema.DisplayType.Currency
            || displayType == Schema.DisplayType.Double
            || displayType == Schema.DisplayType.Percent) {
            return Decimal.valueOf(value);
        }
        if (displayType == Schema.DisplayType.Integer) {
            return Integer.valueOf(value);
        }
        if (displayType == Schema.DisplayType.Long) {
            return Long.valueOf(value);
        }
        if (displayType == Schema.DisplayType.Reference) {
            return (Id) value;
        }
        return value;
    }

    private static String buildReviewNotes(Set<String> acceptedFields, Set<String> skippedFields) {
        List<String> parts = new List<String>();
        if (!acceptedFields.isEmpty()) {
            parts.add('Accepted fields: ' + String.join(new List<String>(acceptedFields), ', '));
        }
        if (!skippedFields.isEmpty()) {
            parts.add('Skipped fields: ' + String.join(new List<String>(skippedFields), ', '));
        }
        return truncate(String.join(parts, ' | '), 255);
    }

    private static String extractAsyncJobId(String responseBody, String fieldName) {
        if (String.isBlank(responseBody)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(responseBody);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> payload = (Map<String, Object>) parsed;
                if (payload.containsKey(fieldName)) {
                    return stringValue(payload.get(fieldName));
                }
                if (payload.containsKey(fieldName.toLowerCase())) {
                    return stringValue(payload.get(fieldName.toLowerCase()));
                }
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String extractNestedString(Map<String, Object> source, String path) {
        return stringValue(extractNestedValue(source, path));
    }

    private static Object extractNestedValue(Map<String, Object> source, String path) {
        if (source == null || String.isBlank(path)) {
            return null;
        }

        Object current = source;
        for (String segment : path.split('\\.')) {
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>) current).get(segment);
            } else if (current instanceof List<Object>) {
                Integer index;
                try {
                    index = Integer.valueOf(segment);
                } catch (Exception ex) {
                    return null;
                }
                List<Object> currentList = (List<Object>) current;
                if (index < 0 || index >= currentList.size()) {
                    return null;
                }
                current = currentList[index];
            } else {
                return null;
            }
        }
        return current;
    }

    private static Decimal normalizeConfidence(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        try {
            Decimal confidence = Decimal.valueOf(String.valueOf(rawValue));
            if (confidence <= 1) {
                confidence *= 100;
            }
            return confidence.setScale(2);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal firstNonNullDecimal(List<Decimal> values) {
        for (Decimal value : values) {
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (!String.isBlank(value)) {
                return value;
            }
        }
        return null;
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
