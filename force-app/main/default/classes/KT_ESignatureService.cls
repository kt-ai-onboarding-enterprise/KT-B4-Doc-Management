public with sharing class KT_ESignatureService {
    public class ESignatureServiceException extends Exception {}

    public class LegalEvidence {
        @AuraEnabled public String ipAddress;
        @AuraEnabled public String deviceUserAgent;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String sessionToken;
    }

    public class SessionTokenResult {
        @AuraEnabled public Id signerId;
        @AuraEnabled public String sessionToken;
        @AuraEnabled public Boolean valid;
        @AuraEnabled public String message;
    }

    public class SigningSession {
        @AuraEnabled public Id signerId;
        @AuraEnabled public Boolean valid;
        @AuraEnabled public String legalNoticeText;
        @AuraEnabled public String signerName;
        @AuraEnabled public String signerEmail;
        @AuraEnabled public String status;
    }

    @AuraEnabled
    public static SessionTokenResult issueSessionToken(Id signerId) {
        if (signerId == null) {
            throw new AuraHandledException('signerId is required.');
        }

        KT_Signer__c signer = [
            SELECT Id, Status__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
            FOR UPDATE
        ];
        if (signer.Status__c == 'Signed' || signer.Status__c == 'Expired') {
            throw new AuraHandledException('Signer is not eligible for a new session token.');
        }

        String token = generateToken(signerId);
        signer.Session_Token__c = hashToken(token);
        update signer;

        SessionTokenResult result = new SessionTokenResult();
        result.signerId = signerId;
        result.sessionToken = token;
        result.valid = true;
        result.message = 'Session token issued.';
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean validateSessionToken(Id signerId, String sessionToken) {
        if (signerId == null || String.isBlank(sessionToken)) {
            return false;
        }

        List<KT_Signer__c> signers = [
            SELECT Id, Status__c, Session_Token__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
        ];
        if (signers.isEmpty()) {
            return false;
        }

        KT_Signer__c signer = signers[0];
        return signer.Status__c != 'Signed'
            && signer.Status__c != 'Expired'
            && !String.isBlank(signer.Session_Token__c)
            && signer.Session_Token__c == hashToken(sessionToken);
    }

    @AuraEnabled(cacheable=true)
    public static SigningSession getSigningSession(Id signerId, String sessionToken) {
        SigningSession session = new SigningSession();
        session.signerId = signerId;
        session.valid = validateSessionToken(signerId, sessionToken);
        session.legalNoticeText = getLegalNoticeText();

        if (signerId != null) {
            List<KT_Signer__c> signers = [
                SELECT Signer_Name__c, Signer_Email__c, Status__c
                FROM KT_Signer__c
                WHERE Id = :signerId
                LIMIT 1
            ];
            if (!signers.isEmpty()) {
                session.signerName = signers[0].Signer_Name__c;
                session.signerEmail = signers[0].Signer_Email__c;
                session.status = signers[0].Status__c;
            }
        }
        return session;
    }

    @AuraEnabled
    public static void invalidateSessionToken(Id signerId) {
        if (signerId == null) {
            throw new AuraHandledException('signerId is required.');
        }
        update new KT_Signer__c(Id = signerId, Session_Token__c = null);
    }

    public static String generateSignatureHash(String documentContentHash, String signerEmail, Datetime eventTimestamp) {
        String seed = String.valueOf(documentContentHash) + '|'
            + String.valueOf(signerEmail).toLowerCase() + '|'
            + String.valueOf(eventTimestamp == null ? System.now().getTime() : eventTimestamp.getTime());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
    }

    public static Id captureLegalEvidence(Id signerId, String eventType, LegalEvidence evidence) {
        if (signerId == null) {
            throw new ESignatureServiceException('signerId is required.');
        }
        if (String.isBlank(eventType)) {
            eventType = 'Signature Captured';
        }
        if (evidence == null) {
            evidence = new LegalEvidence();
        }

        KT_Signer__c signer = [
            SELECT Id, KT_Signature_Request__c, Signer_Email__c
            FROM KT_Signer__c
            WHERE Id = :signerId
            LIMIT 1
            FOR UPDATE
        ];
        signer.IP_Address__c = evidence.ipAddress;
        signer.Device_User_Agent__c = evidence.deviceUserAgent;
        update signer;

        String hashValue = generateSignatureHash(
            String.valueOf(signer.KT_Signature_Request__c),
            signer.Signer_Email__c,
            System.now()
        );
        KT_Signature_Audit__c audit = new KT_Signature_Audit__c(
            KT_Signer__c = signer.Id,
            KT_Signature_Request__c = signer.KT_Signature_Request__c,
            Event_Type__c = eventType,
            Event_Timestamp__c = System.now(),
            IP_Address__c = evidence.ipAddress,
            Device_User_Agent__c = evidence.deviceUserAgent,
            Geolocation_Latitude__c = evidence.latitude,
            Geolocation_Longitude__c = evidence.longitude,
            Hash_Value__c = hashValue,
            Session_Token__c = evidence.sessionToken
        );
        insert audit;
        return audit.Id;
    }

    @TestVisible
    private static String generateToken(Id signerId) {
        Blob randomBytes = Crypto.generateAesKey(128);
        String payload = String.valueOf(signerId) + '|' + String.valueOf(System.now().getTime()) + '|'
            + EncodingUtil.convertToHex(randomBytes);
        return EncodingUtil.base64Encode(Blob.valueOf(payload));
    }

    @TestVisible
    private static String hashToken(String token) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token)));
    }

    private static String getLegalNoticeText() {
        List<KT_Signature_Config__mdt> configs = [
            SELECT Legal_Notice_Text__c
            FROM KT_Signature_Config__mdt
            ORDER BY DeveloperName ASC
            LIMIT 1
        ];
        if (!configs.isEmpty() && !String.isBlank(configs[0].Legal_Notice_Text__c)) {
            return configs[0].Legal_Notice_Text__c;
        }
        return 'By signing electronically, you agree that your signature has the same legal effect as a handwritten signature.';
    }
}
