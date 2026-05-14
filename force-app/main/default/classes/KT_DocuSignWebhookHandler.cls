@RestResource(urlMapping='/kt/v1/docusign/webhook')
global with sharing class KT_DocuSignWebhookHandler {
    @TestVisible private static String webhookSecretOverride;

    global class WebhookException extends Exception {}

    private class WebhookContext {
        String rawBody;
        Map<String, Object> payload;
        String envelopeId;
        String status;
        String accountId;
    }

    @HttpPost
    global static void handleWebhook() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response == null ? new RestResponse() : RestContext.response;
        RestContext.response = response;

        try {
            WebhookContext context = buildContext(request);
            validateSignature(request, context.rawBody);

            List<KT_Signature_Request__c> signatureRequests = [
                SELECT Id, KT_DocumentVault__c, KT_Onboarding__c, Status__c, External_Envelope_Id__c
                FROM KT_Signature_Request__c
                WHERE External_Envelope_Id__c = :context.envelopeId
                LIMIT 1
            ];
            if (signatureRequests.isEmpty()) {
                writeResponse(response, 404, 'No signature request found for DocuSign envelope ' + context.envelopeId + '.');
                return;
            }

            KT_Signature_Request__c signatureRequest = signatureRequests[0];
            processStatus(signatureRequest, context);
            writeResponse(response, 200, 'DocuSign webhook processed.');
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
            throw new WebhookException('DocuSign webhook body is required.');
        }

        WebhookContext context = new WebhookContext();
        context.rawBody = request.requestBody.toString();
        try {
            Object parsed = JSON.deserializeUntyped(context.rawBody);
            if (!(parsed instanceof Map<String, Object>)) {
                throw new WebhookException('DocuSign webhook payload must be a JSON object.');
            }
            context.payload = (Map<String, Object>) parsed;
        } catch (WebhookException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new WebhookException('DocuSign webhook payload is not valid JSON.');
        }

        context.envelopeId = firstString(context.payload, new List<String>{ 'envelopeId', 'envelope_id', 'EnvelopeId' });
        context.status = firstString(context.payload, new List<String>{ 'status', 'event', 'eventType', 'envelopeStatus' });
        context.accountId = firstString(context.payload, new List<String>{ 'accountId', 'account_id' });

        Map<String, Object> data = getMap(context.payload.get('data'));
        if (data != null) {
            if (String.isBlank(context.envelopeId)) {
                context.envelopeId = firstString(data, new List<String>{ 'envelopeId', 'envelope_id' });
            }
            if (String.isBlank(context.status)) {
                context.status = firstString(data, new List<String>{ 'status', 'event', 'eventType', 'envelopeStatus' });
            }
            if (String.isBlank(context.accountId)) {
                context.accountId = firstString(data, new List<String>{ 'accountId', 'account_id' });
            }
        }

        if (String.isBlank(context.envelopeId)) {
            throw new WebhookException('DocuSign envelope id was not provided.');
        }
        if (String.isBlank(context.status)) {
            throw new WebhookException('DocuSign envelope status was not provided.');
        }
        return context;
    }

    private static void processStatus(KT_Signature_Request__c signatureRequest, WebhookContext context) {
        String normalized = normalizeStatus(context.status);
        if (normalized == 'completed') {
            KT_DocuSignEnvelopeService.retrieveCompletedDocument(signatureRequest.Id, context.accountId);
            insertAudit(signatureRequest.Id, 'Completed', context);
            return;
        }

        if (normalized == 'sent' || normalized == 'delivered') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'In Progress');
            updateSigners(signatureRequest.Id, normalized == 'delivered' ? 'Viewed' : 'Invitation Sent');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(
                    Id = signatureRequest.KT_DocumentVault__c,
                    Status__c = 'Pending Signature',
                    Signature_Status__c = 'Pending'
                );
            }
            insertAudit(signatureRequest.Id, normalized == 'delivered' ? 'Document Viewed' : 'Invitation Sent', context);
            return;
        }

        if (normalized == 'declined') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Cancelled');
            updateSigners(signatureRequest.Id, 'Declined');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(
                    Id = signatureRequest.KT_DocumentVault__c,
                    Status__c = 'Draft',
                    Signature_Status__c = 'Pending'
                );
            }
            insertAudit(signatureRequest.Id, 'Declined', context);
            return;
        }

        if (normalized == 'voided' || normalized == 'expired') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = normalized == 'expired' ? 'Expired' : 'Cancelled');
            updateSigners(signatureRequest.Id, normalized == 'expired' ? 'Expired' : 'Declined');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(
                    Id = signatureRequest.KT_DocumentVault__c,
                    Status__c = normalized == 'expired' ? 'Expired' : 'Draft',
                    Signature_Status__c = normalized == 'expired' ? 'Expired' : 'Pending'
                );
            }
            insertAudit(signatureRequest.Id, normalized == 'expired' ? 'Expired' : 'Declined', context);
        }
    }

    private static void validateSignature(RestRequest request, String rawBody) {
        String expectedSecret = resolveWebhookSecret();
        if (String.isBlank(expectedSecret)) {
            throw new SecurityException('No DocuSign webhook shared secret is configured.');
        }

        String providedSignature = getHeader(
            request,
            new List<String>{ 'X-DocuSign-Signature-1', 'X-DocuSign-Signature', 'X-KT-Signature', 'X-Hub-Signature-256' }
        );
        if (String.isBlank(providedSignature)) {
            throw new SecurityException('DocuSign webhook signature header was not provided.');
        }

        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(rawBody), Blob.valueOf(expectedSecret));
        String expectedBase64 = EncodingUtil.base64Encode(mac).toLowerCase();
        String expectedHex = EncodingUtil.convertToHex(mac).toLowerCase();
        String normalized = normalizeSignature(providedSignature);
        if (normalized != expectedBase64 && normalized != expectedHex) {
            throw new SecurityException('DocuSign webhook HMAC signature validation failed.');
        }
    }

    private static String resolveWebhookSecret() {
        if (!String.isBlank(webhookSecretOverride)) {
            return webhookSecretOverride;
        }

        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        Schema.SObjectType settingType = describeMap.get('KT_Integration_Security__c');
        if (settingType == null) {
            settingType = describeMap.get('KT_DocuSign_Webhook_Security__c');
        }
        if (settingType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = settingType.getDescribe().fields.getMap();
        String fieldName = firstExistingField(
            fieldMap,
            new List<String>{ 'DocuSign_Webhook_Secret__c', 'DocuSign_HMAC_Secret__c', 'Webhook_Secret__c' }
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

    private static void updateSigners(Id signatureRequestId, String status) {
        List<KT_Signer__c> signers = [
            SELECT Id, Status__c, Signed_At__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
        ];
        for (KT_Signer__c signer : signers) {
            signer.Status__c = status;
            if (status == 'Signed' && signer.Signed_At__c == null) {
                signer.Signed_At__c = System.now();
            }
        }
        if (!signers.isEmpty()) {
            update signers;
        }
    }

    private static void insertAudit(Id signatureRequestId, String eventType, WebhookContext context) {
        insert new KT_Signature_Audit__c(
            KT_Signature_Request__c = signatureRequestId,
            Event_Type__c = eventType,
            Event_Timestamp__c = System.now(),
            Hash_Value__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(context.rawBody))),
            Device_User_Agent__c = getHeader(RestContext.request, new List<String>{ 'User-Agent' }),
            IP_Address__c = firstString(context.payload, new List<String>{ 'ipAddress', 'ip_address' })
        );
    }

    private static String normalizeStatus(String status) {
        String normalized = status == null ? null : status.trim().toLowerCase();
        if (String.isBlank(normalized)) {
            return null;
        }
        if (normalized.contains('completed')) {
            return 'completed';
        }
        if (normalized.contains('delivered') || normalized.contains('viewed')) {
            return 'delivered';
        }
        if (normalized.contains('sent')) {
            return 'sent';
        }
        if (normalized.contains('declined')) {
            return 'declined';
        }
        if (normalized.contains('voided') || normalized.contains('cancel')) {
            return 'voided';
        }
        if (normalized.contains('expired')) {
            return 'expired';
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
