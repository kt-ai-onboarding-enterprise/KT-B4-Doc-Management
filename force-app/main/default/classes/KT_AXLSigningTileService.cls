public with sharing class KT_AXLSigningTileService {
    public class AXLSigningTileException extends Exception {}

    public class TileRequest {
        @InvocableVariable(required=true) public Id signatureRequestId;
        @InvocableVariable public String channel;
    }

    public class TileResult {
        @AuraEnabled @InvocableVariable public Id signatureRequestId;
        @AuraEnabled @InvocableVariable public Id signerId;
        @AuraEnabled @InvocableVariable public String channel;
        @AuraEnabled @InvocableVariable public String signingUrl;
        @AuraEnabled @InvocableVariable public String cardPayload;
        @AuraEnabled @InvocableVariable public String message;
    }

    @AuraEnabled
    public static TileResult buildSigningTile(Id signatureRequestId, String channel) {
        if (signatureRequestId == null) {
            throw new AuraHandledException('signatureRequestId is required.');
        }
        String normalizedChannel = normalizeChannel(channel);

        KT_Signature_Request__c signatureRequest = [
            SELECT Id, Status__c, Signing_Provider__c, KT_DocumentVault__r.Document_Name__c,
                   KT_DocumentVault__r.Document_Type__c
            FROM KT_Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];

        KT_Signer__c signer = nextTileSigner(signatureRequestId);
        KT_ESignatureService.SessionTokenResult token = KT_ESignatureService.issueSessionToken(signer.Id);
        String signingUrl = buildSigningUrl(signer.Id, token.sessionToken);
        String documentName = signatureRequest.KT_DocumentVault__r == null
            ? 'Document'
            : signatureRequest.KT_DocumentVault__r.Document_Name__c;

        TileResult result = new TileResult();
        result.signatureRequestId = signatureRequestId;
        result.signerId = signer.Id;
        result.channel = normalizedChannel;
        result.signingUrl = signingUrl;
        result.cardPayload = normalizedChannel == 'Teams'
            ? buildTeamsCard(signatureRequest, signer, documentName, signingUrl)
            : buildSlackCard(signatureRequest, signer, documentName, signingUrl);
        result.message = 'AXL signing tile generated.';
        return result;
    }

    @InvocableMethod(label='Build KT AXL Signing Tile' description='Builds Slack or Teams signing tile payloads for pending KT Sign workflows.')
    public static List<TileResult> buildSigningTiles(List<TileRequest> requests) {
        List<TileResult> results = new List<TileResult>();
        if (requests == null) {
            return results;
        }
        for (TileRequest request : requests) {
            if (request == null) {
                continue;
            }
            results.add(buildSigningTile(request.signatureRequestId, request.channel));
        }
        return results;
    }

    private static KT_Signer__c nextTileSigner(Id signatureRequestId) {
        List<KT_Signer__c> signers = [
            SELECT Id, Signer_Name__c, Signer_Email__c, Signer_Role__c, Status__c, Signing_Order__c
            FROM KT_Signer__c
            WHERE KT_Signature_Request__c = :signatureRequestId
            AND Status__c IN ('Invitation Sent', 'Pending', 'Viewed')
            ORDER BY Signing_Order__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 1
        ];
        if (signers.isEmpty()) {
            throw new AXLSigningTileException('No pending signer is available for this signature request.');
        }
        return signers[0];
    }

    private static String buildSigningUrl(Id signerId, String sessionToken) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        return baseUrl
            + '/lightning/n/KT_B4_04_Signature_Capture'
            + '?c__signerId=' + EncodingUtil.urlEncode(String.valueOf(signerId), 'UTF-8')
            + '&c__sessionToken=' + EncodingUtil.urlEncode(sessionToken, 'UTF-8');
    }

    private static String buildSlackCard(
        KT_Signature_Request__c signatureRequest,
        KT_Signer__c signer,
        String documentName,
        String signingUrl
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'text' => 'Signature requested: ' + documentName,
            'blocks' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'section',
                    'text' => new Map<String, Object>{
                        'type' => 'mrkdwn',
                        'text' => '*Signature requested*\\n' + documentName + '\\nSigner: ' + signer.Signer_Name__c
                    }
                },
                new Map<String, Object>{
                    'type' => 'actions',
                    'elements' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'button',
                            'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'Open mobile signing' },
                            'url' => signingUrl,
                            'style' => 'primary',
                            'value' => String.valueOf(signatureRequest.Id)
                        }
                    }
                }
            }
        };
        return JSON.serialize(payload);
    }

    private static String buildTeamsCard(
        KT_Signature_Request__c signatureRequest,
        KT_Signer__c signer,
        String documentName,
        String signingUrl
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'type' => 'AdaptiveCard',
            '$schema' => 'http://adaptivecards.io/schemas/adaptive-card.json',
            'version' => '1.5',
            'body' => new List<Object>{
                new Map<String, Object>{ 'type' => 'TextBlock', 'size' => 'Medium', 'weight' => 'Bolder', 'text' => 'Signature requested' },
                new Map<String, Object>{ 'type' => 'TextBlock', 'text' => documentName, 'wrap' => true },
                new Map<String, Object>{ 'type' => 'FactSet', 'facts' => new List<Object>{
                    new Map<String, Object>{ 'title' => 'Signer', 'value' => signer.Signer_Name__c },
                    new Map<String, Object>{ 'title' => 'Provider', 'value' => signatureRequest.Signing_Provider__c }
                }}
            },
            'actions' => new List<Object>{
                new Map<String, Object>{ 'type' => 'Action.OpenUrl', 'title' => 'Open mobile signing', 'url' => signingUrl }
            }
        };
        return JSON.serialize(payload);
    }

    private static String normalizeChannel(String channel) {
        if (String.isBlank(channel)) {
            return 'Slack';
        }
        String normalized = channel.trim().toLowerCase();
        if (normalized == 'teams' || normalized == 'microsoft teams') {
            return 'Teams';
        }
        return 'Slack';
    }
}
