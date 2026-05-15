@RestResource(urlMapping='/kt/v1/adobesign/webhook')
global with sharing class KT_AdobeSignWebhookHandler {
    @TestVisible private static String verificationTokenOverride;

    global class WebhookException extends Exception {}

    private class WebhookContext {
        String rawBody;
        Map<String, Object> payload;
        String agreementId;
        String eventType;
    }

    @HttpGet
    global static void verifyWebhook() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response == null ? new RestResponse() : RestContext.response;
        RestContext.response = response;

        try {
            String clientId = getHeader(request, new List<String>{ 'X-AdobeSign-ClientId', 'x-adobesign-clientid' });
            validateVerificationToken(clientId);
            response.statusCode = 200;
            response.addHeader('X-AdobeSign-ClientId', clientId);
            response.addHeader('Content-Type', 'application/json');
            response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Adobe Sign webhook verified.'
            }));
        } catch (SecurityException ex) {
            writeResponse(response, 401, ex.getMessage());
        }
    }

    @HttpPost
    global static void handleWebhook() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response == null ? new RestResponse() : RestContext.response;
        RestContext.response = response;

        try {
            validateVerificationToken(getHeader(
                request,
                new List<String>{ 'X-AdobeSign-ClientId', 'x-adobesign-clientid', 'X-KT-AdobeSign-Token' }
            ));
            WebhookContext context = buildContext(request);
            processEvent(context);
            writeResponse(response, 200, 'Adobe Sign webhook processed.');
        } catch (SecurityException ex) {
            writeResponse(response, 401, ex.getMessage());
        } catch (WebhookException ex) {
            writeResponse(response, 400, ex.getMessage());
        } catch (Exception ex) {
            writeResponse(response, 500, ex.getMessage());
        }
    }

    private static WebhookContext buildContext(RestRequest request) {
        if (request == null || request.requestBody == null) {
            throw new WebhookException('Adobe Sign webhook body is required.');
        }

        WebhookContext context = new WebhookContext();
        context.rawBody = request.requestBody.toString();
        try {
            Object parsed = JSON.deserializeUntyped(context.rawBody);
            if (!(parsed instanceof Map<String, Object>)) {
                throw new WebhookException('Adobe Sign webhook payload must be a JSON object.');
            }
            context.payload = (Map<String, Object>) parsed;
        } catch (WebhookException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new WebhookException('Adobe Sign webhook payload is not valid JSON.');
        }

        context.eventType = firstString(context.payload, new List<String>{ 'event', 'eventType', 'eventName' });
        context.agreementId = firstString(context.payload, new List<String>{ 'agreementId', 'agreement_id', 'id' });

        Map<String, Object> agreement = getMap(context.payload.get('agreement'));
        if (agreement != null && String.isBlank(context.agreementId)) {
            context.agreementId = firstString(agreement, new List<String>{ 'id', 'agreementId' });
        }

        Map<String, Object> agreementInfo = getMap(context.payload.get('agreementInfo'));
        if (agreementInfo != null && String.isBlank(context.agreementId)) {
            context.agreementId = firstString(agreementInfo, new List<String>{ 'agreementId', 'id' });
        }

        Map<String, Object> data = getMap(context.payload.get('data'));
        if (data != null) {
            if (String.isBlank(context.eventType)) {
                context.eventType = firstString(data, new List<String>{ 'event', 'eventType', 'eventName' });
            }
            if (String.isBlank(context.agreementId)) {
                context.agreementId = firstString(data, new List<String>{ 'agreementId', 'agreement_id', 'id' });
            }
        }

        if (String.isBlank(context.agreementId)) {
            throw new WebhookException('Adobe Sign agreement id was not provided.');
        }
        if (String.isBlank(context.eventType)) {
            throw new WebhookException('Adobe Sign event type was not provided.');
        }
        return context;
    }

    private static void processEvent(WebhookContext context) {
        String normalizedEvent = normalizeEvent(context.eventType);

        if (normalizedEvent == 'AGREEMENT_ACTION_COMPLETED') {
            Id signatureRequestId = findSignatureRequestId(context.agreementId);
            KT_AdobeSignService.retrieveCompletedDocument(signatureRequestId);
            insertAudit(signatureRequestId, 'Completed', context.rawBody);
            return;
        }

        if (normalizedEvent == 'AGREEMENT_RECALLED') {
            KT_AdobeSignService.webhookCallback(context.agreementId, 'AGREEMENT_RECALLED');
            return;
        }

        if (normalizedEvent == 'AGREEMENT_EXPIRED') {
            KT_AdobeSignService.webhookCallback(context.agreementId, 'AGREEMENT_EXPIRED');
            return;
        }

        if (normalizedEvent == 'AGREEMENT_OUT_FOR_SIGNATURE' || normalizedEvent == 'AGREEMENT_SENT') {
            KT_AdobeSignService.webhookCallback(context.agreementId, 'IN_PROCESS');
            return;
        }

        throw new WebhookException('Unsupported Adobe Sign webhook event: ' + context.eventType + '.');
    }

    private static Id findSignatureRequestId(String agreementId) {
        List<KT_Signature_Request__c> signatureRequests = [
            SELECT Id
            FROM KT_Signature_Request__c
            WHERE External_Envelope_Id__c = :agreementId
            LIMIT 1
        ];
        if (signatureRequests.isEmpty()) {
            throw new WebhookException('No signature request was found for Adobe Sign agreement ' + agreementId + '.');
        }
        return signatureRequests[0].Id;
    }

    private static void validateVerificationToken(String providedToken) {
        String expectedToken = resolveVerificationToken();
        if (String.isBlank(expectedToken)) {
            throw new SecurityException('No Adobe Sign webhook verification token is configured.');
        }
        if (String.isBlank(providedToken) || providedToken != expectedToken) {
            throw new SecurityException('Adobe Sign webhook verification token validation failed.');
        }
    }

    private static String resolveVerificationToken() {
        if (!String.isBlank(verificationTokenOverride)) {
            return verificationTokenOverride;
        }

        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        Schema.SObjectType settingType = describeMap.get('KT_Integration_Security__c');
        if (settingType == null) {
            settingType = describeMap.get('KT_AdobeSign_Webhook_Security__c');
        }
        if (settingType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = settingType.getDescribe().fields.getMap();
        String fieldName = firstExistingField(
            fieldMap,
            new List<String>{ 'AdobeSign_Webhook_Token__c', 'AdobeSign_Client_Id__c', 'Webhook_Verification_Token__c' }
        );
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

    private static void insertAudit(Id signatureRequestId, String eventType, String rawBody) {
        insert new KT_Signature_Audit__c(
            KT_Signature_Request__c = signatureRequestId,
            Event_Type__c = eventType,
            Event_Timestamp__c = System.now(),
            Device_User_Agent__c = getHeader(RestContext.request, new List<String>{ 'User-Agent' }),
            Hash_Value__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(rawBody)))
        );
    }

    private static String normalizeEvent(String eventType) {
        String normalized = String.isBlank(eventType) ? null : eventType.trim().toUpperCase();
        if (String.isBlank(normalized)) {
            return null;
        }
        if (normalized.contains('COMPLETED') || normalized.contains('SIGNED')) {
            return 'AGREEMENT_ACTION_COMPLETED';
        }
        if (normalized.contains('RECALLED') || normalized.contains('CANCELLED')) {
            return 'AGREEMENT_RECALLED';
        }
        if (normalized.contains('EXPIRED')) {
            return 'AGREEMENT_EXPIRED';
        }
        if (normalized.contains('OUT_FOR_SIGNATURE') || normalized.contains('SENT') || normalized.contains('IN_PROCESS')) {
            return 'AGREEMENT_OUT_FOR_SIGNATURE';
        }
        return normalized;
    }

    private static String firstString(Map<String, Object> payload, List<String> fieldNames) {
        if (payload == null) {
            return null;
        }
        for (String fieldName : fieldNames) {
            if (payload.containsKey(fieldName) && payload.get(fieldName) != null) {
                return String.valueOf(payload.get(fieldName));
            }
        }
        return null;
    }

    private static Map<String, Object> getMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
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

    private static String firstExistingField(Map<String, Schema.SObjectField> fieldMap, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                return fieldName;
            }
        }
        return null;
    }

    private static void writeResponse(RestResponse response, Integer statusCode, String message) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => statusCode >= 200 && statusCode < 300,
            'message' => message
        }));
    }
}
