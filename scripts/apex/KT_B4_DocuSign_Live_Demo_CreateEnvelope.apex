String docuSignAccountId = 'faf1d738-3e7e-4692-8804-09f403a398b2';
Id signatureRequestId = null;

if (signatureRequestId == null) {
    List<KT_Signature_Request__c> requests = [
        SELECT Id
        FROM KT_Signature_Request__c
        WHERE Signing_Provider__c = 'DocuSign'
        AND External_Envelope_Id__c = null
        AND Status__c = 'Configured'
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (requests.isEmpty()) {
        throw new AuraHandledException('No configured DocuSign signature request found.');
    }
    signatureRequestId = requests[0].Id;
}

KT_DocuSignEnvelopeService.EnvelopeResult createResult =
    KT_DocuSignEnvelopeService.createEnvelope(signatureRequestId, docuSignAccountId);

System.debug('KT_B4_DOCUSIGN_LIVE_DEMO_CREATE::' + JSON.serialize(new Map<String, Object>{
    'signatureRequestId' => createResult.signatureRequestId,
    'envelopeId' => createResult.envelopeId,
    'status' => createResult.status,
    'message' => createResult.message
}));
