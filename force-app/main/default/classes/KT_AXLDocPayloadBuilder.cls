public with sharing class KT_AXLDocPayloadBuilder {
    public class PayloadBuilderException extends Exception {}

    public class PayloadRequest {
        @InvocableVariable(required=true) public Id signatureRequestId;
        @InvocableVariable public String channel;
    }

    public class PayloadResult {
        @AuraEnabled @InvocableVariable public Id signatureRequestId;
        @AuraEnabled @InvocableVariable public Id signerId;
        @AuraEnabled @InvocableVariable public String channel;
        @AuraEnabled @InvocableVariable public String signingUrl;
        @AuraEnabled @InvocableVariable public String cardPayload;
        @AuraEnabled @InvocableVariable public String message;
    }

    @AuraEnabled
    public static PayloadResult buildPayload(Id signatureRequestId, String channel) {
        try {
            return fromTileResult(KT_AXLSigningTileService.buildSigningTile(signatureRequestId, channel));
        } catch (Exception ex) {
            throw new PayloadBuilderException('Unable to build AXL document payload: ' + ex.getMessage());
        }
    }

    @InvocableMethod(label='Build KT AXL Document Payload' description='Builds Slack or Teams document signing card payloads using the B4 AXL signing tile service.')
    public static List<PayloadResult> buildPayloads(List<PayloadRequest> requests) {
        List<PayloadResult> results = new List<PayloadResult>();
        if (requests == null) {
            return results;
        }
        for (PayloadRequest request : requests) {
            if (request == null) {
                continue;
            }
            results.add(buildPayload(request.signatureRequestId, request.channel));
        }
        return results;
    }

    private static PayloadResult fromTileResult(KT_AXLSigningTileService.TileResult tileResult) {
        PayloadResult result = new PayloadResult();
        result.signatureRequestId = tileResult.signatureRequestId;
        result.signerId = tileResult.signerId;
        result.channel = tileResult.channel;
        result.signingUrl = tileResult.signingUrl;
        result.cardPayload = tileResult.cardPayload;
        result.message = 'AXL document payload generated.';
        return result;
    }
}
