public with sharing class KT_VirusScanService implements Callable {
    private static final String NAMED_CREDENTIAL = 'KT_VirusScan_NC';
    private static final String SCAN_PATH = '/scan';

    public class VirusScanException extends Exception {}

    public class ScanResult {
        @AuraEnabled public Boolean isClean;
        @AuraEnabled public Boolean manualReviewRequired;
        @AuraEnabled public String message;
        @AuraEnabled public String threatName;

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'isClean' => isClean,
                'manualReviewRequired' => manualReviewRequired,
                'message' => message,
                'threatName' => threatName
            };
        }
    }

    public Object call(String action, Map<String, Object> args) {
        if (action == 'scanBase64') {
            return scanBase64(
                String.valueOf(args.get('fileName')),
                String.valueOf(args.get('base64Data')),
                String.valueOf(args.get('contentType'))
            ).toMap();
        }
        throw new VirusScanException('Unsupported action: ' + action);
    }

    public static ScanResult scanBase64(String fileName, String base64Data, String contentType) {
        if (String.isBlank(fileName)) {
            throw new VirusScanException('fileName is required.');
        }
        if (String.isBlank(base64Data)) {
            throw new VirusScanException('base64Data is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + NAMED_CREDENTIAL + SCAN_PATH);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(10000);
        request.setBody(JSON.serialize(new Map<String, Object>{
            'fileName' => fileName,
            'contentType' => contentType,
            'base64Data' => base64Data
        }));

        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                return parseResponse(response.getBody());
            }
            return manualReview('Virus scan service returned HTTP ' + response.getStatusCode() + '.');
        } catch (System.CalloutException ignored) {
            return manualReview('Virus scan timed out or was unavailable. Manual review required.');
        }
    }

    private static ScanResult parseResponse(String responseBody) {
        if (String.isBlank(responseBody)) {
            return manualReview('Virus scan returned an empty response. Manual review required.');
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        String status = payload.containsKey('status') && payload.get('status') != null
            ? String.valueOf(payload.get('status')).toLowerCase()
            : null;
        Boolean isClean = payload.containsKey('isClean')
            ? Boolean.valueOf(String.valueOf(payload.get('isClean')))
            : status == 'clean';

        ScanResult result = new ScanResult();
        result.isClean = isClean;
        result.manualReviewRequired = false;
        result.threatName = payload.containsKey('threatName') && payload.get('threatName') != null
            ? String.valueOf(payload.get('threatName'))
            : null;
        result.message = isClean
            ? 'Virus scan passed.'
            : 'Virus scan failed: ' + (String.isBlank(result.threatName) ? 'Threat detected.' : result.threatName);
        return result;
    }

    private static ScanResult manualReview(String message) {
        ScanResult result = new ScanResult();
        result.isClean = true;
        result.manualReviewRequired = true;
        result.message = message;
        return result;
    }
}
