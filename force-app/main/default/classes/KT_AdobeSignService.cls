public with sharing class KT_AdobeSignService {
    private static final String NAMED_CREDENTIAL = 'KT_AdobeSign_NC';

    public class AdobeSignException extends Exception {}

    public class AgreementResult {
        @AuraEnabled public Id signatureRequestId;
        @AuraEnabled public String agreementId;
        @AuraEnabled public String status;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static AgreementResult createAgreement(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, true);
        ContentVersion sourceVersion = loadLatestVersion(signatureRequest.KT_DocumentVault__r.Content_Document_Id__c);

        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(agreementEndpoint());
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(buildAgreementPayload(signatureRequest, sourceVersion, 'DRAFT')));

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 201);
        String agreementId = firstString(body, new List<String>{ 'id', 'agreementId' });
        String status = firstString(body, new List<String>{ 'status', 'state' });
        if (String.isBlank(agreementId)) {
            throw new AdobeSignException('Adobe Sign create agreement response did not include an agreement id.');
        }

        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Signing_Provider__c = 'Adobe Sign',
            External_Envelope_Id__c = agreementId,
            Status__c = 'Configured'
        );

        return result(signatureRequest.Id, agreementId, String.isBlank(status) ? 'DRAFT' : status, null, 'Adobe Sign agreement created.');
    }

    @AuraEnabled
    public static AgreementResult sendAgreement(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External agreement id is required before sending.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('PUT');
        request.setEndpoint(agreementEndpoint() + '/' + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8') + '/state');
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"state":"IN_PROCESS"}');

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 200);
        String status = firstString(body, new List<String>{ 'status', 'state' });

        update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'In Progress');
        updateSigners(signatureRequest.Id, 'Invitation Sent');
        if (signatureRequest.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = signatureRequest.KT_DocumentVault__c,
                Status__c = 'Pending Signature',
                Signature_Status__c = 'Pending'
            );
        }

        return result(signatureRequest.Id, signatureRequest.External_Envelope_Id__c, String.isBlank(status) ? 'IN_PROCESS' : status, null, 'Adobe Sign agreement sent.');
    }

    @AuraEnabled
    public static AgreementResult getAgreementStatus(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External agreement id is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(agreementEndpoint() + '/' + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8'));

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 200);
        String status = firstString(body, new List<String>{ 'status', 'state' });
        applyAgreementStatus(signatureRequest, status);

        return result(signatureRequest.Id, signatureRequest.External_Envelope_Id__c, status, null, 'Adobe Sign agreement status refreshed.');
    }

    @AuraEnabled
    public static AgreementResult retrieveCompletedDocument(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External agreement id is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(
            agreementEndpoint()
            + '/'
            + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8')
            + '/combinedDocument'
        );

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() > 299) {
            throw new AdobeSignException('Adobe Sign completed document retrieval failed: ' + response.getStatus());
        }

        ContentVersion version = new ContentVersion(
            Title = 'Adobe Sign Completed - ' + safe(signatureRequest.KT_DocumentVault__r.Document_Name__c, 'Document'),
            PathOnClient = 'adobesign-completed-' + String.valueOf(Date.today()) + '.pdf',
            VersionData = response.getBodyAsBlob()
        );
        insert version;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;

        completeSignatureRequest(signatureRequest, contentDocumentId);
        return result(signatureRequest.Id, signatureRequest.External_Envelope_Id__c, 'SIGNED', contentDocumentId, 'Adobe Sign completed document retrieved.');
    }

    public static AgreementResult webhookCallback(String agreementId, String status) {
        if (String.isBlank(agreementId)) {
            throw new AdobeSignException('agreementId is required.');
        }

        List<KT_Signature_Request__c> signatureRequests = [
            SELECT Id, KT_Onboarding__c, KT_DocumentVault__c, Status__c, External_Envelope_Id__c,
                   KT_DocumentVault__r.Document_Name__c, KT_DocumentVault__r.Content_Document_Id__c,
                   KT_DocumentVault__r.Document_Request__c
            FROM KT_Signature_Request__c
            WHERE External_Envelope_Id__c = :agreementId
            LIMIT 1
        ];
        if (signatureRequests.isEmpty()) {
            throw new AdobeSignException('No signature request was found for Adobe Sign agreement ' + agreementId + '.');
        }

        KT_Signature_Request__c signatureRequest = signatureRequests[0];
        applyAgreementStatus(signatureRequest, status);
        insertAudit(signatureRequest.Id, status);
        return result(signatureRequest.Id, agreementId, status, null, 'Adobe Sign webhook status processed.');
    }

    private static KT_Signature_Request__c loadSignatureRequest(Id signatureRequestId, Boolean requireDocument) {
        if (signatureRequestId == null) {
            throw new AuraHandledException('signatureRequestId is required.');
        }

        KT_Signature_Request__c signatureRequest = [
            SELECT Id, KT_Onboarding__c, KT_DocumentVault__c, Signing_Provider__c, Status__c,
                   Signing_Order__c, Total_Signers__c, Completed_Signers__c, Expiry_Date__c,
                   External_Envelope_Id__c, KT_DocumentVault__r.Document_Name__c,
                   KT_DocumentVault__r.Content_Document_Id__c, KT_DocumentVault__r.Document_Request__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];

        if (requireDocument && String.isBlank(signatureRequest.KT_DocumentVault__r.Content_Document_Id__c)) {
            throw new AdobeSignException('The vault entry must have a source ContentDocument before creating an Adobe Sign agreement.');
        }
        return signatureRequest;
    }

    private static ContentVersion loadLatestVersion(String contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId = :((Id) contentDocumentId)
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new AdobeSignException('No source ContentVersion was found for the vault document.');
        }
        return versions[0];
    }

    private static Map<String, Object> buildAgreementPayload(KT_Signature_Request__c signatureRequest, ContentVersion sourceVersion, String state) {
        List<Object> participantSets = new List<Object>();
        for (KT_Signer__c signer : [
            SELECT Id, Signer_Name__c, Signer_Email__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            ORDER BY Signing_Order__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            participantSets.add(new Map<String, Object>{
                'memberInfos' => new List<Object>{
                    new Map<String, Object>{ 'email' => signer.Signer_Email__c }
                },
                'order' => signatureRequest.Signing_Order__c == 'Parallel' ? 1 : Integer.valueOf(signer.Signing_Order__c == null ? 1 : signer.Signing_Order__c),
                'role' => 'SIGNER'
            });
        }

        return new Map<String, Object>{
            'name' => safe(signatureRequest.KT_DocumentVault__r.Document_Name__c, safe(sourceVersion.Title, 'Onboarding Document')),
            'signatureType' => 'ESIGN',
            'state' => state,
            'fileInfos' => new List<Object>{
                new Map<String, Object>{
                    'documentBase64' => EncodingUtil.base64Encode(sourceVersion.VersionData),
                    'fileName' => safe(sourceVersion.Title, 'onboarding-document') + '.' + (String.isBlank(sourceVersion.FileExtension) ? 'pdf' : sourceVersion.FileExtension)
                }
            },
            'participantSetsInfo' => participantSets
        };
    }

    private static void applyAgreementStatus(KT_Signature_Request__c signatureRequest, String adobeStatus) {
        String normalized = normalizeStatus(adobeStatus);
        if (normalized == 'SIGNED') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Fully Signed');
            updateSigners(signatureRequest.Id, 'Signed');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(Id = signatureRequest.KT_DocumentVault__c, Status__c = 'Signed', Signature_Status__c = 'Fully Signed');
            }
        } else if (normalized == 'IN_PROCESS' || normalized == 'OUT_FOR_SIGNATURE') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'In Progress');
            updateSigners(signatureRequest.Id, 'Invitation Sent');
        } else if (normalized == 'CANCELLED' || normalized == 'RECALLED') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Cancelled');
            updateSigners(signatureRequest.Id, 'Declined');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(Id = signatureRequest.KT_DocumentVault__c, Status__c = 'Draft', Signature_Status__c = 'Pending');
            }
        } else if (normalized == 'EXPIRED') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Expired');
            updateSigners(signatureRequest.Id, 'Expired');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(Id = signatureRequest.KT_DocumentVault__c, Status__c = 'Expired', Signature_Status__c = 'Expired');
            }
        }
    }

    private static void completeSignatureRequest(KT_Signature_Request__c signatureRequest, Id contentDocumentId) {
        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Status__c = 'Fully Signed',
            Completed_Document_Id__c = String.valueOf(contentDocumentId)
        );
        updateSigners(signatureRequest.Id, 'Signed');

        if (signatureRequest.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = signatureRequest.KT_DocumentVault__c,
                Content_Document_Id__c = contentDocumentId,
                Status__c = 'Signed',
                Signature_Status__c = 'Fully Signed'
            );
        }

        Id documentRequestId = signatureRequest.KT_DocumentVault__r == null
            ? null
            : signatureRequest.KT_DocumentVault__r.Document_Request__c;
        if (documentRequestId != null) {
            update new KT_Document_Request__c(
                Id = documentRequestId,
                Status__c = 'Complete',
                Completed_Date__c = System.now()
            );
        }
    }

    private static void updateSigners(Id signatureRequestId, String status) {
        List<KT_Signer__c> signers = [
            SELECT Id, Status__c, Signed_At__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
        ];
        for (KT_Signer__c signer : signers) {
            if (status == 'Signed' && signer.Signed_At__c == null) {
                signer.Signed_At__c = System.now();
            }
            signer.Status__c = status;
        }
        if (!signers.isEmpty()) {
            update signers;
        }
    }

    private static void insertAudit(Id signatureRequestId, String status) {
        String normalized = normalizeStatus(status);
        String eventType = normalized == 'SIGNED'
            ? 'Completed'
            : normalized == 'EXPIRED'
                ? 'Expired'
                : normalized == 'CANCELLED' || normalized == 'RECALLED'
                    ? 'Declined'
                    : 'Invitation Sent';
        insert new KT_Signature_Audit__c(
            KT_Signature_Request__c = signatureRequestId,
            Event_Type__c = eventType,
            Event_Timestamp__c = System.now(),
            Hash_Value__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(signatureRequestId) + '|' + String.valueOf(status))))
        );
    }

    private static String normalizeStatus(String status) {
        String normalized = String.isBlank(status) ? null : status.trim().toUpperCase();
        if (String.isBlank(normalized)) {
            return null;
        }
        if (normalized.contains('SIGNED') || normalized.contains('COMPLETED') || normalized == 'AGREEMENT_ACTION_COMPLETED') {
            return 'SIGNED';
        }
        if (normalized.contains('RECALLED')) {
            return 'RECALLED';
        }
        if (normalized.contains('CANCEL')) {
            return 'CANCELLED';
        }
        if (normalized.contains('EXPIRED')) {
            return 'EXPIRED';
        }
        if (normalized.contains('OUT_FOR_SIGNATURE') || normalized.contains('IN_PROCESS')) {
            return 'IN_PROCESS';
        }
        return normalized;
    }

    private static String agreementEndpoint() {
        return 'callout:' + NAMED_CREDENTIAL + '/api/rest/v6/agreements';
    }

    private static Map<String, Object> parseJsonResponse(HttpResponse response, Integer expectedStatusCode) {
        if (response.getStatusCode() != expectedStatusCode) {
            throw new AdobeSignException('Adobe Sign callout failed: ' + response.getStatus());
        }
        if (String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(response.getBody());
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    private static String firstString(Map<String, Object> values, List<String> keys) {
        for (String key : keys) {
            if (values.containsKey(key) && values.get(key) != null) {
                return String.valueOf(values.get(key));
            }
        }
        return null;
    }

    private static AgreementResult result(Id signatureRequestId, String agreementId, String status, Id contentDocumentId, String message) {
        AgreementResult result = new AgreementResult();
        result.signatureRequestId = signatureRequestId;
        result.agreementId = agreementId;
        result.status = status;
        result.contentDocumentId = contentDocumentId;
        result.message = message;
        return result;
    }

    private static String safe(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }
}
