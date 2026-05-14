public with sharing class KT_DocuSignEnvelopeService {
    private static final String NAMED_CREDENTIAL = 'KT_DocuSign_NC';
    private static final String DEFAULT_ACCOUNT_ID = 'default';

    public class DocuSignException extends Exception {}

    public class EnvelopeResult {
        @AuraEnabled public Id signatureRequestId;
        @AuraEnabled public String envelopeId;
        @AuraEnabled public String status;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static EnvelopeResult createEnvelope(Id signatureRequestId, String accountId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, true);
        ContentVersion sourceVersion = loadLatestVersion(signatureRequest.KT_DocumentVault__r.Content_Document_Id__c);

        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(envelopeEndpoint(accountId));
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(buildEnvelopePayload(signatureRequest, sourceVersion, 'created')));

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 201);
        String envelopeId = String.valueOf(body.get('envelopeId'));
        String status = body.containsKey('status') ? String.valueOf(body.get('status')) : 'created';
        if (String.isBlank(envelopeId)) {
            throw new DocuSignException('DocuSign create envelope response did not include envelopeId.');
        }

        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Signing_Provider__c = 'DocuSign',
            External_Envelope_Id__c = envelopeId,
            Status__c = 'Configured'
        );

        return result(signatureRequest.Id, envelopeId, status, null, 'DocuSign envelope created.');
    }

    @AuraEnabled
    public static EnvelopeResult sendEnvelope(Id signatureRequestId, String accountId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External envelope id is required before sending.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('PUT');
        request.setEndpoint(envelopeEndpoint(accountId) + '/' + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8'));
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"status":"sent"}');

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 200);
        String status = body.containsKey('status') ? String.valueOf(body.get('status')) : 'sent';

        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Status__c = 'In Progress'
        );
        updatePendingSigners(signatureRequest.Id, 'Invitation Sent');
        if (signatureRequest.KT_DocumentVault__c != null) {
            update new KT_DocumentVault__c(
                Id = signatureRequest.KT_DocumentVault__c,
                Status__c = 'Pending Signature',
                Signature_Status__c = 'Pending'
            );
        }

        return result(signatureRequest.Id, signatureRequest.External_Envelope_Id__c, status, null, 'DocuSign envelope sent.');
    }

    @AuraEnabled
    public static EnvelopeResult getEnvelopeStatus(Id signatureRequestId, String accountId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External envelope id is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(envelopeEndpoint(accountId) + '/' + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8'));

        HttpResponse response = new Http().send(request);
        Map<String, Object> body = parseJsonResponse(response, 200);
        String status = body.containsKey('status') ? String.valueOf(body.get('status')) : null;
        applyEnvelopeStatus(signatureRequest, status);

        return result(signatureRequest.Id, signatureRequest.External_Envelope_Id__c, status, null, 'DocuSign envelope status refreshed.');
    }

    @AuraEnabled
    public static EnvelopeResult retrieveCompletedDocument(Id signatureRequestId, String accountId) {
        KT_Signature_Request__c signatureRequest = loadSignatureRequest(signatureRequestId, false);
        if (String.isBlank(signatureRequest.External_Envelope_Id__c)) {
            throw new AuraHandledException('External envelope id is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(
            envelopeEndpoint(accountId)
            + '/'
            + EncodingUtil.urlEncode(signatureRequest.External_Envelope_Id__c, 'UTF-8')
            + '/documents/combined'
        );

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() > 299) {
            throw new DocuSignException('DocuSign completed document retrieval failed: ' + response.getStatus());
        }

        ContentVersion version = new ContentVersion(
            Title = 'DocuSign Completed - ' + safe(signatureRequest.KT_DocumentVault__r.Document_Name__c, 'Document'),
            PathOnClient = 'docusign-completed-' + String.valueOf(Date.today()) + '.pdf',
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

        return result(
            signatureRequest.Id,
            signatureRequest.External_Envelope_Id__c,
            'completed',
            contentDocumentId,
            'DocuSign completed document retrieved.'
        );
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
            throw new DocuSignException('The vault entry must have a source ContentDocument before creating a DocuSign envelope.');
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
            throw new DocuSignException('No source ContentVersion was found for the vault document.');
        }
        return versions[0];
    }

    private static Map<String, Object> buildEnvelopePayload(KT_Signature_Request__c signatureRequest, ContentVersion sourceVersion, String status) {
        List<Object> signerPayloads = new List<Object>();
        for (KT_Signer__c signer : [
            SELECT Id, Signer_Name__c, Signer_Email__c, Signer_Role__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequest.Id
            ORDER BY Signing_Order__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            signerPayloads.add(new Map<String, Object>{
                'name' => safe(signer.Signer_Name__c, signer.Signer_Email__c),
                'email' => signer.Signer_Email__c,
                'recipientId' => String.valueOf(signer.Signing_Order__c == null ? 1 : signer.Signing_Order__c),
                'routingOrder' => signatureRequest.Signing_Order__c == 'Parallel'
                    ? '1'
                    : String.valueOf(signer.Signing_Order__c == null ? 1 : signer.Signing_Order__c),
                'tabs' => new Map<String, Object>{
                    'signHereTabs' => new List<Object>{
                        new Map<String, Object>{
                            'documentId' => '1',
                            'pageNumber' => '1',
                            'xPosition' => '72',
                            'yPosition' => '680'
                        }
                    }
                }
            });
        }

        return new Map<String, Object>{
            'emailSubject' => 'Please sign ' + safe(signatureRequest.KT_DocumentVault__r.Document_Name__c, 'your onboarding document'),
            'status' => status,
            'documents' => new List<Object>{
                new Map<String, Object>{
                    'documentBase64' => EncodingUtil.base64Encode(sourceVersion.VersionData),
                    'name' => safe(sourceVersion.Title, 'Onboarding Document'),
                    'fileExtension' => String.isBlank(sourceVersion.FileExtension) ? 'pdf' : sourceVersion.FileExtension,
                    'documentId' => '1'
                }
            },
            'recipients' => new Map<String, Object>{
                'signers' => signerPayloads
            }
        };
    }

    private static void applyEnvelopeStatus(KT_Signature_Request__c signatureRequest, String docuSignStatus) {
        if (String.isBlank(docuSignStatus)) {
            return;
        }
        String normalized = docuSignStatus.trim().toLowerCase();
        if (normalized == 'completed') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Fully Signed');
            updatePendingSigners(signatureRequest.Id, 'Signed');
            if (signatureRequest.KT_DocumentVault__c != null) {
                update new KT_DocumentVault__c(
                    Id = signatureRequest.KT_DocumentVault__c,
                    Status__c = 'Signed',
                    Signature_Status__c = 'Fully Signed'
                );
            }
        } else if (normalized == 'sent' || normalized == 'delivered') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'In Progress');
            updatePendingSigners(signatureRequest.Id, 'Invitation Sent');
        } else if (normalized == 'declined' || normalized == 'voided') {
            update new KT_Signature_Request__c(Id = signatureRequest.Id, Status__c = 'Cancelled');
            updatePendingSigners(signatureRequest.Id, 'Declined');
        }
    }

    private static void completeSignatureRequest(KT_Signature_Request__c signatureRequest, Id contentDocumentId) {
        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Status__c = 'Fully Signed',
            Completed_Document_Id__c = String.valueOf(contentDocumentId)
        );
        updatePendingSigners(signatureRequest.Id, 'Signed');

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

    private static void updatePendingSigners(Id signatureRequestId, String status) {
        List<KT_Signer__c> signers = [
            SELECT Id, Status__c, Signed_At__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
        ];
        for (KT_Signer__c signer : signers) {
            if (status == 'Signed') {
                signer.Signed_At__c = signer.Status__c == 'Signed' ? signer.Signed_At__c : System.now();
            }
            signer.Status__c = status;
        }
        if (!signers.isEmpty()) {
            update signers;
        }
    }

    private static String envelopeEndpoint(String accountId) {
        String normalizedAccountId = String.isBlank(accountId) ? DEFAULT_ACCOUNT_ID : accountId.trim();
        return 'callout:' + NAMED_CREDENTIAL + '/v2.1/accounts/' + EncodingUtil.urlEncode(normalizedAccountId, 'UTF-8') + '/envelopes';
    }

    private static Map<String, Object> parseJsonResponse(HttpResponse response, Integer expectedStatusCode) {
        if (response.getStatusCode() != expectedStatusCode) {
            throw new DocuSignException('DocuSign callout failed: ' + response.getStatus());
        }
        if (String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(response.getBody());
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    private static EnvelopeResult result(Id signatureRequestId, String envelopeId, String status, Id contentDocumentId, String message) {
        EnvelopeResult result = new EnvelopeResult();
        result.signatureRequestId = signatureRequestId;
        result.envelopeId = envelopeId;
        result.status = status;
        result.contentDocumentId = contentDocumentId;
        result.message = message;
        return result;
    }

    private static String safe(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }
}
