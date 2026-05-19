// Safe helper for sending an already-created DocuSign envelope.
//
// Run order for a fresh live demo:
// 1. KT_B4_DocuSign_Live_Demo_Setup.apex
// 2. KT_B4_DocuSign_Live_Demo_CreateEnvelope.apex
// 3. This helper, or KT_B4_DocuSign_Live_Demo_SendEnvelope.apex
//
// This file intentionally does not create records. Salesforce blocks callouts
// after DML in the same Apex transaction, so setup/create/send stay separated.
String docuSignAccountId = 'faf1d738-3e7e-4692-8804-09f403a398b2';
Id signatureRequestId = null;

if (signatureRequestId == null) {
    List<KT_Signature_Request__c> requests = [
        SELECT Id
        FROM KT_Signature_Request__c
        WHERE Signing_Provider__c = 'DocuSign'
        AND External_Envelope_Id__c != null
        AND Status__c = 'Configured'
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (requests.isEmpty()) {
        throw new AuraHandledException('No created DocuSign signature request found. Run KT_B4_DocuSign_Live_Demo_CreateEnvelope.apex first.');
    }
    signatureRequestId = requests[0].Id;
}

KT_DocuSignEnvelopeService.EnvelopeResult sendResult =
    KT_DocuSignEnvelopeService.sendEnvelope(signatureRequestId, docuSignAccountId);

System.debug('KT_B4_DOCUSIGN_LIVE_DEMO_SEND::' + JSON.serialize(new Map<String, Object>{
    'signatureRequestId' => sendResult.signatureRequestId,
    'envelopeId' => sendResult.envelopeId,
    'status' => sendResult.status,
    'message' => sendResult.message
}));
