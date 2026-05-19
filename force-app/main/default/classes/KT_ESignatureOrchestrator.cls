public with sharing class KT_ESignatureOrchestrator {
    public class ESignatureException extends Exception {}

    public class SignatureConfig {
        @AuraEnabled public String signingProvider;
        @AuraEnabled public String signingOrder;
        @AuraEnabled public Integer expiryDays;
        @AuraEnabled public List<SignerConfig> signers;
    }

    public class SignerConfig {
        @AuraEnabled public String signerName;
        @AuraEnabled public String signerEmail;
        @AuraEnabled public String signerRole;
        @AuraEnabled public Integer signingOrder;
    }

    public class SignaturePayload {
        @AuraEnabled public String signatureBase64;
        @AuraEnabled public String ipAddress;
        @AuraEnabled public String deviceUserAgent;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String sessionToken;
    }

    public class SignatureCompletionRequest {
        @InvocableVariable(required=true) public Id signerId;
        @InvocableVariable public String signatureBase64;
        @InvocableVariable public String ipAddress;
        @InvocableVariable public String deviceUserAgent;
        @InvocableVariable public Decimal latitude;
        @InvocableVariable public Decimal longitude;
        @InvocableVariable public String sessionToken;
    }

    public class SignatureCompletionResult {
        @InvocableVariable public Id signerId;
        @InvocableVariable public Id signatureRequestId;
        @InvocableVariable public Boolean workflowComplete;
        @InvocableVariable public String message;
    }

    public class TrustedAgentIdentityResult {
        @AuraEnabled public Id signatureRequestId;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime verifiedAt;
        @AuraEnabled public String verificationReference;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static Boolean completeSignature(
        Id signerId,
        String signatureBase64,
        String ipAddress,
        String deviceUserAgent,
        Decimal latitude,
        Decimal longitude,
        String sessionToken
    ) {
        if (!KT_ESignatureService.validateSessionToken(signerId, sessionToken)) {
            throw new AuraHandledException('Signing session is invalid or expired.');
        }

        SignaturePayload payload = new SignaturePayload();
        payload.signatureBase64 = signatureBase64;
        payload.ipAddress = ipAddress;
        payload.deviceUserAgent = deviceUserAgent;
        payload.latitude = latitude;
        payload.longitude = longitude;
        payload.sessionToken = sessionToken;
        Boolean workflowComplete = handleSignatureComplete(signerId, payload);
        KT_ESignatureService.invalidateSessionToken(signerId);
        return workflowComplete;
    }

    @AuraEnabled
    public static Id initiateSigningWorkflow(Id vaultId, SignatureConfig config) {
        if (vaultId == null) {
            throw new AuraHandledException('vaultId is required.');
        }
        if (config == null || config.signers == null || config.signers.isEmpty()) {
            throw new AuraHandledException('At least one signer is required.');
        }

        KT_DocumentVault__c vaultEntry = [
            SELECT Id, KT_Onboarding__c, Regulatory_Tag__c
            FROM KT_DocumentVault__c
            WHERE Id = :vaultId
            LIMIT 1
        ];
        Boolean requiresTrustedIdentity = isHighValueSignature(vaultEntry.Regulatory_Tag__c);

        KT_Signature_Request__c signatureRequest = new KT_Signature_Request__c(
            KT_DocumentVault__c = vaultId,
            KT_Onboarding__c = vaultEntry.KT_Onboarding__c,
            Signing_Provider__c = String.isBlank(config.signingProvider) ? 'KT Sign' : config.signingProvider,
            Status__c = 'Configured',
            Total_Signers__c = config.signers.size(),
            Completed_Signers__c = 0,
            Expiry_Date__c = Date.today().addDays(config.expiryDays == null ? 14 : config.expiryDays),
            Signing_Order__c = String.isBlank(config.signingOrder) ? 'Sequential' : config.signingOrder,
            Initiated_By__c = UserInfo.getUserId(),
            Requires_Trusted_Agent_Identity__c = requiresTrustedIdentity,
            Trusted_Agent_Verification_Status__c = requiresTrustedIdentity ? 'Pending' : 'Not Required'
        );
        insert signatureRequest;

        List<KT_Signer__c> signers = new List<KT_Signer__c>();
        Integer index = 1;
        for (SignerConfig signerConfig : config.signers) {
            signers.add(new KT_Signer__c(
                KT_Signature_Request__c = signatureRequest.Id,
                Signer_Name__c = signerConfig.signerName,
                Signer_Email__c = signerConfig.signerEmail,
                Signer_Role__c = String.isBlank(signerConfig.signerRole) ? 'Onboardee' : signerConfig.signerRole,
                Signing_Order__c = signerConfig.signingOrder == null ? index : signerConfig.signingOrder,
                Status__c = 'Pending'
            ));
            index++;
        }
        insert signers;

        update new KT_DocumentVault__c(
            Id = vaultId,
            Status__c = 'Pending Signature',
            Signature_Status__c = 'Pending'
        );

        dispatchNextInvitation(signatureRequest.Id);
        return signatureRequest.Id;
    }

    @AuraEnabled
    public static TrustedAgentIdentityResult verifyTrustedAgentIdentity(
        Id signatureRequestId,
        String verificationReference,
        Boolean verified
    ) {
        if (signatureRequestId == null) {
            throw new AuraHandledException('signatureRequestId is required.');
        }

        KT_Signature_Request__c signatureRequest = [
            SELECT Id, Requires_Trusted_Agent_Identity__c, Trusted_Agent_Verification_Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
            FOR UPDATE
        ];

        String status = verified == true ? 'Verified' : 'Failed';
        Datetime verifiedAt = verified == true ? System.now() : null;
        update new KT_Signature_Request__c(
            Id = signatureRequest.Id,
            Trusted_Agent_Verification_Status__c = status,
            Trusted_Agent_Verified_At__c = verifiedAt,
            Trusted_Agent_Verification_Reference__c = verificationReference
        );

        SignaturePayload payload = new SignaturePayload();
        payload.sessionToken = verificationReference;
        createAuditEvent(null, signatureRequest.Id, verified == true ? 'Trusted Identity Verified' : 'Trusted Identity Failed', payload);

        TrustedAgentIdentityResult result = new TrustedAgentIdentityResult();
        result.signatureRequestId = signatureRequest.Id;
        result.status = status;
        result.verifiedAt = verifiedAt;
        result.verificationReference = verificationReference;
        result.message = verified == true ? 'Trusted agent identity verified.' : 'Trusted agent identity verification failed.';
        return result;
    }

    public static void dispatchNextInvitation(Id signatureRequestId) {
        if (signatureRequestId == null) {
            throw new ESignatureException('signatureRequestId is required.');
        }

        KT_Signature_Request__c signatureRequest = [
            SELECT Id, Signing_Order__c, Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
            FOR UPDATE
        ];
        List<KT_Signer__c> pendingSigners = [
            SELECT Id, KT_Signature_Request__c, Status__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c = 'Pending'
            ORDER BY Signing_Order__c ASC NULLS LAST, CreatedDate ASC
        ];
        if (pendingSigners.isEmpty()) {
            return;
        }

        List<KT_Signer__c> signersToInvite = new List<KT_Signer__c>();
        if (signatureRequest.Signing_Order__c == 'Parallel') {
            signersToInvite.addAll(pendingSigners);
        } else {
            signersToInvite.add(pendingSigners[0]);
        }

        for (KT_Signer__c signer : signersToInvite) {
            signer.Status__c = 'Invitation Sent';
        }
        update signersToInvite;

        signatureRequest.Status__c = 'In Progress';
        update signatureRequest;

        createAuditEvents(signersToInvite, 'Invitation Sent', null);
    }

    @InvocableMethod(label='Complete KT Signature' description='Completes a KT Sign signer step and advances the signing workflow.')
    public static List<SignatureCompletionResult> handleSignatureComplete(List<SignatureCompletionRequest> requests) {
        List<SignatureCompletionResult> results = new List<SignatureCompletionResult>();
        if (requests == null) {
            return results;
        }
        for (SignatureCompletionRequest request : requests) {
            SignaturePayload payload = new SignaturePayload();
            payload.signatureBase64 = request.signatureBase64;
            payload.ipAddress = request.ipAddress;
            payload.deviceUserAgent = request.deviceUserAgent;
            payload.latitude = request.latitude;
            payload.longitude = request.longitude;
            payload.sessionToken = request.sessionToken;
            Boolean workflowComplete = handleSignatureComplete(request.signerId, payload);

            SignatureCompletionResult result = new SignatureCompletionResult();
            result.signerId = request.signerId;
            result.signatureRequestId = getSignatureRequestId(request.signerId);
            result.workflowComplete = workflowComplete;
            result.message = workflowComplete ? 'Signing workflow complete.' : 'Signature captured.';
            results.add(result);
        }
        return results;
    }

    public static Boolean handleSignatureComplete(Id signerId, SignaturePayload payload) {
        if (signerId == null) {
            throw new ESignatureException('signerId is required.');
        }
        if (payload == null) {
            payload = new SignaturePayload();
        }

        KT_Signer__c signer = [
            SELECT Id, KT_Signature_Request__c, Signer_Email__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
            FOR UPDATE
        ];
        enforceTrustedIdentityBeforeFinalSignature(signer.KT_Signature_Request__c, signer.Id);

        Id signatureImageId = storeSignatureImage(signerId, payload.signatureBase64);
        signer.Status__c = 'Signed';
        signer.Signed_At__c = System.now();
        signer.IP_Address__c = payload.ipAddress;
        signer.Device_User_Agent__c = payload.deviceUserAgent;
        signer.Signature_Image_Id__c = signatureImageId;
        update signer;

        createAuditEvent(signer.Id, signer.KT_Signature_Request__c, 'Signature Captured', payload);
        createAuditEvent(signer.Id, signer.KT_Signature_Request__c, 'Signed', payload);

        refreshCounts(signer.KT_Signature_Request__c);
        if (isWorkflowComplete(signer.KT_Signature_Request__c)) {
            completeWorkflow(signer.KT_Signature_Request__c);
            return true;
        }
        dispatchNextInvitation(signer.KT_Signature_Request__c);
        return false;
    }

    @AuraEnabled
    public static Id handleDelegation(Id signerId, String delegateEmail, String reason) {
        if (signerId == null) {
            throw new AuraHandledException('signerId is required.');
        }
        if (String.isBlank(delegateEmail)) {
            throw new AuraHandledException('delegateEmail is required.');
        }

        KT_Signer__c originalSigner = [
            SELECT Id, KT_Signature_Request__c, Signer_Name__c, Signer_Role__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
            FOR UPDATE
        ];
        originalSigner.Status__c = 'Delegated';
        originalSigner.Delegated_To__c = delegateEmail;
        originalSigner.Delegation_Reason__c = reason;
        update originalSigner;

        KT_Signer__c delegateSigner = new KT_Signer__c(
            KT_Signature_Request__c = originalSigner.KT_Signature_Request__c,
            Signer_Name__c = delegateEmail,
            Signer_Email__c = delegateEmail,
            Signer_Role__c = originalSigner.Signer_Role__c,
            Signing_Order__c = originalSigner.Signing_Order__c,
            Status__c = 'Pending'
        );
        insert delegateSigner;

        createAuditEvent(originalSigner.Id, originalSigner.KT_Signature_Request__c, 'Delegated', null);
        refreshCounts(originalSigner.KT_Signature_Request__c);
        dispatchNextInvitation(originalSigner.KT_Signature_Request__c);
        return delegateSigner.Id;
    }

    public static void completeWorkflow(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = [
            SELECT Id, Status__c, KT_Onboarding__c, KT_DocumentVault__c, KT_DocumentVault__r.Content_Document_Id__c,
                   KT_DocumentVault__r.Document_Request__c, Requires_Trusted_Agent_Identity__c,
                   Trusted_Agent_Verification_Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
            FOR UPDATE
        ];
        if (signatureRequest.Status__c == 'Fully Signed') {
            return;
        }
        refreshCounts(signatureRequestId);
        if (signatureRequest.Requires_Trusted_Agent_Identity__c == true
            && signatureRequest.Trusted_Agent_Verification_Status__c != 'Verified') {
            throw new ESignatureException('Trusted Agent Identity verification is required before completing this high-value signature workflow.');
        }

        signatureRequest.Status__c = 'Fully Signed';
        signatureRequest.Completed_Document_Id__c = signatureRequest.KT_DocumentVault__r.Content_Document_Id__c;
        update signatureRequest;

        update new KT_DocumentVault__c(
            Id = signatureRequest.KT_DocumentVault__c,
            Status__c = 'Signed',
            Signature_Status__c = 'Fully Signed'
        );

        Id documentRequestId = signatureRequest.KT_DocumentVault__r == null
            ? null
            : signatureRequest.KT_DocumentVault__r.Document_Request__c;
        List<KT_Document_Request__c> requests = [
            SELECT Id
            FROM KT_Document_Request__c
            WHERE Document_Vault_Entry__c = :signatureRequest.KT_DocumentVault__c
            LIMIT 1
        ];
        if (!requests.isEmpty()) {
            documentRequestId = requests[0].Id;
        }
        if (documentRequestId != null) {
            update new KT_Document_Request__c(
                Id = documentRequestId,
                Status__c = 'Complete',
                Completed_Date__c = System.now()
            );
        }

        createAuditEvent(null, signatureRequestId, 'Completed', null);
        publishSignatureCompleteEvent(
            signatureRequestId,
            signatureRequest.KT_Onboarding__c,
            signatureRequest.Completed_Document_Id__c,
            System.now(),
            signatureRequest.KT_DocumentVault__c
        );
    }

    public static void handleExpiryEscalation(Id signatureRequestId) {
        KT_Signature_Request__c signatureRequest = [
            SELECT Id, KT_DocumentVault__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
            FOR UPDATE
        ];
        List<KT_Signer__c> signers = [
            SELECT Id, KT_Signature_Request__c, Status__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c IN ('Pending', 'Invitation Sent', 'Viewed')
        ];
        for (KT_Signer__c signer : signers) {
            signer.Status__c = 'Expired';
        }
        if (!signers.isEmpty()) {
            update signers;
            createAuditEvents(signers, 'Expired', null);
        }

        signatureRequest.Status__c = 'Expired';
        update signatureRequest;
        update new KT_DocumentVault__c(
            Id = signatureRequest.KT_DocumentVault__c,
            Status__c = 'Expired',
            Signature_Status__c = 'Expired'
        );
    }

    private static Id storeSignatureImage(Id signerId, String signatureBase64) {
        if (String.isBlank(signatureBase64)) {
            return null;
        }
        String body = stripDataUrlPrefix(signatureBase64);
        ContentVersion version = new ContentVersion(
            Title = 'Signature-' + signerId,
            PathOnClient = 'signature.png',
            VersionData = EncodingUtil.base64Decode(body)
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    private static void refreshCounts(Id signatureRequestId) {
        AggregateResult signed = [
            SELECT COUNT(Id) signedCount
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c = 'Signed'
        ];
        AggregateResult required = [
            SELECT COUNT(Id) requiredCount
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c != 'Delegated'
        ];
        update new KT_Signature_Request__c(
            Id = signatureRequestId,
            Completed_Signers__c = (Integer) signed.get('signedCount'),
            Total_Signers__c = (Integer) required.get('requiredCount')
        );
    }

    private static Boolean isWorkflowComplete(Id signatureRequestId) {
        Integer activeCount = [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c IN ('Pending', 'Invitation Sent', 'Viewed')
        ];
        Integer signedCount = [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c = 'Signed'
        ];
        return activeCount == 0 && signedCount > 0;
    }

    private static void enforceTrustedIdentityBeforeFinalSignature(Id signatureRequestId, Id currentSignerId) {
        KT_Signature_Request__c signatureRequest = [
            SELECT Requires_Trusted_Agent_Identity__c, Trusted_Agent_Verification_Status__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];
        if (signatureRequest.Requires_Trusted_Agent_Identity__c != true
            || signatureRequest.Trusted_Agent_Verification_Status__c == 'Verified') {
            return;
        }

        Integer otherActiveSignerCount = [
            SELECT COUNT()
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Id != :currentSignerId
            AND Status__c IN ('Pending', 'Invitation Sent', 'Viewed')
        ];
        if (otherActiveSignerCount == 0) {
            throw new ESignatureException('Trusted Agent Identity verification is required before completing this high-value signature workflow.');
        }
    }

    private static Id getSignatureRequestId(Id signerId) {
        return [
            SELECT KT_Signature_Request__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
        ].KT_Signature_Request__c;
    }

    private static void createAuditEvents(List<KT_Signer__c> signers, String eventType, SignaturePayload payload) {
        List<KT_Signature_Audit__c> audits = new List<KT_Signature_Audit__c>();
        for (KT_Signer__c signer : signers) {
            audits.add(buildAudit(signer.Id, signer.KT_Signature_Request__c, eventType, payload));
        }
        insert audits;
    }

    private static void createAuditEvent(Id signerId, Id signatureRequestId, String eventType, SignaturePayload payload) {
        insert buildAudit(signerId, signatureRequestId, eventType, payload);
    }

    private static KT_Signature_Audit__c buildAudit(Id signerId, Id signatureRequestId, String eventType, SignaturePayload payload) {
        if (payload == null) {
            payload = new SignaturePayload();
        }
        return new KT_Signature_Audit__c(
            KT_Signer__c = signerId,
            KT_Signature_Request__c = signatureRequestId,
            Event_Type__c = eventType,
            Event_Timestamp__c = System.now(),
            IP_Address__c = payload.ipAddress,
            Device_User_Agent__c = payload.deviceUserAgent,
            Geolocation_Latitude__c = payload.latitude,
            Geolocation_Longitude__c = payload.longitude,
            Hash_Value__c = generateHash(signatureRequestId, signerId, payload),
            Session_Token__c = payload.sessionToken
        );
    }

    private static String generateHash(Id signatureRequestId, Id signerId, SignaturePayload payload) {
        String seed = String.valueOf(signatureRequestId) + '|' + String.valueOf(signerId) + '|' + System.now().getTime();
        if (payload != null) {
            seed += '|' + String.valueOf(payload.ipAddress) + '|' + String.valueOf(payload.sessionToken);
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
    }

    private static String stripDataUrlPrefix(String value) {
        Integer commaIndex = value.indexOf(',');
        return value.startsWith('data:') && commaIndex > -1 ? value.substring(commaIndex + 1) : value;
    }

    private static Boolean isHighValueSignature(String regulatoryTag) {
        if (String.isBlank(regulatoryTag)) {
            return false;
        }
        String normalized = regulatoryTag.toUpperCase();
        return normalized.contains('SOX') || normalized.contains('HIPAA');
    }

    private static void publishSignatureCompleteEvent(
        Id signatureRequestId,
        Id onboardingId,
        Id documentId,
        Datetime completedAt,
        Id vaultId
    ) {
        Schema.SObjectType eventType = Schema.getGlobalDescribe().get('KT_Signature_Complete__e');
        if (eventType == null) {
            return;
        }
        SObject eventRecord = eventType.newSObject();
        Map<String, Schema.SObjectField> eventFields = eventType.getDescribe().fields.getMap();
        if (eventFields.containsKey('KT_Signature_Request__c')) {
            eventRecord.put('KT_Signature_Request__c', signatureRequestId);
        }
        if (eventFields.containsKey('Signature_Request_Id__c')) {
            eventRecord.put('Signature_Request_Id__c', String.valueOf(signatureRequestId));
        }
        if (eventFields.containsKey('SignatureRequestId__c')) {
            eventRecord.put('SignatureRequestId__c', String.valueOf(signatureRequestId));
        }
        if (eventFields.containsKey('OnboardingId__c')) {
            eventRecord.put('OnboardingId__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('KT_Onboarding__c')) {
            eventRecord.put('KT_Onboarding__c', onboardingId);
        }
        if (eventFields.containsKey('DocumentId__c')) {
            eventRecord.put('DocumentId__c', String.valueOf(documentId));
        }
        if (eventFields.containsKey('CompletedAt__c')) {
            eventRecord.put('CompletedAt__c', completedAt);
        }
        if (eventFields.containsKey('AllSignersSigned__c')) {
            eventRecord.put('AllSignersSigned__c', true);
        }
        if (eventFields.containsKey('KT_DocumentVault__c')) {
            eventRecord.put('KT_DocumentVault__c', vaultId);
        }
        if (eventFields.containsKey('Document_Vault_Id__c')) {
            eventRecord.put('Document_Vault_Id__c', String.valueOf(vaultId));
        }
        EventBus.publish(eventRecord);
    }
}
