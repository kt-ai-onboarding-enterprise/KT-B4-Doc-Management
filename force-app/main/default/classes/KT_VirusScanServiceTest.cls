@IsTest
private class KT_VirusScanServiceTest {
    private class CleanScanMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:KT_VirusScan_NC'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"isClean":true,"status":"clean"}');
            return response;
        }
    }

    private class InfectedScanMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"isClean":false,"status":"infected","threatName":"EICAR-Test-File"}');
            return response;
        }
    }

    private class ErrorScanMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('unavailable');
            return response;
        }
    }

    @IsTest
    static void scanBase64ReturnsCleanResult() {
        Test.setMock(HttpCalloutMock.class, new CleanScanMock());

        Test.startTest();
        KT_VirusScanService.ScanResult result = KT_VirusScanService.scanBase64(
            'passport.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('body')),
            'application/pdf'
        );
        Test.stopTest();

        System.assertEquals(true, result.isClean);
        System.assertEquals(false, result.manualReviewRequired);
        System.assertEquals('Virus scan passed.', result.message);
    }

    @IsTest
    static void scanBase64ReturnsInfectedResultAndCallableMap() {
        Test.setMock(HttpCalloutMock.class, new InfectedScanMock());

        Test.startTest();
        KT_VirusScanService.ScanResult result = KT_VirusScanService.scanBase64(
            'passport.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('body')),
            'application/pdf'
        );
        Map<String, Object> callableResult = (Map<String, Object>) new KT_VirusScanService().call(
            'scanBase64',
            new Map<String, Object>{
                'fileName' => 'passport.pdf',
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('body')),
                'contentType' => 'application/pdf'
            }
        );
        Test.stopTest();

        System.assertEquals(false, result.isClean);
        System.assertEquals('EICAR-Test-File', result.threatName);
        System.assertEquals(false, callableResult.get('isClean'));
    }

    @IsTest
    static void scanBase64ReturnsManualReviewOnServiceError() {
        Test.setMock(HttpCalloutMock.class, new ErrorScanMock());

        Test.startTest();
        KT_VirusScanService.ScanResult result = KT_VirusScanService.scanBase64(
            'passport.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('body')),
            'application/pdf'
        );
        Test.stopTest();

        System.assertEquals(true, result.isClean);
        System.assertEquals(true, result.manualReviewRequired);
    }
}
