String docuSignAccountId = 'faf1d738-3e7e-4692-8804-09f403a398b2';
Id signatureRequestId = 'a07g500000Orn99AAB';

Map<String, Object> summary = new Map<String, Object>();

KT_DocuSignEnvelopeService.EnvelopeResult statusResult =
    KT_DocuSignEnvelopeService.getEnvelopeStatus(signatureRequestId, docuSignAccountId);
summary.put('statusEnvelopeId', statusResult.envelopeId);
summary.put('status', statusResult.status);
summary.put('statusMessage', statusResult.message);

if (String.valueOf(statusResult.status).toLowerCase() == 'completed') {
    KT_DocuSignEnvelopeService.EnvelopeResult documentResult =
        KT_DocuSignEnvelopeService.retrieveCompletedDocument(signatureRequestId, docuSignAccountId);
    summary.put('retrievedContentDocumentId', documentResult.contentDocumentId);
    summary.put('retrieveStatus', documentResult.status);
    summary.put('retrieveMessage', documentResult.message);
}

KT_Signature_Request__c request = [
    SELECT Id, Status__c, External_Envelope_Id__c, Completed_Document_Id__c,
           KT_DocumentVault__c, KT_DocumentVault__r.Status__c, KT_DocumentVault__r.Signature_Status__c,
           KT_DocumentVault__r.Content_Document_Id__c
    FROM KT_Signature_Request__c
    WHERE Id = :signatureRequestId
    LIMIT 1
];
summary.put('signatureRequestStatus', request.Status__c);
summary.put('completedDocumentId', request.Completed_Document_Id__c);
summary.put('vaultId', request.KT_DocumentVault__c);
summary.put('vaultStatus', request.KT_DocumentVault__r.Status__c);
summary.put('vaultSignatureStatus', request.KT_DocumentVault__r.Signature_Status__c);
summary.put('vaultContentDocumentId', request.KT_DocumentVault__r.Content_Document_Id__c);
summary.put('signerStatuses', [
    SELECT Id, Signer_Name__c, Signer_Email__c, Status__c, Signed_At__c
    FROM KT_Signer__c
    WHERE KT_Signature_Request__c = :signatureRequestId
]);

System.debug('KT_B4_DOCUSIGN_LIVE_REFRESH_RETRIEVE::' + JSON.serialize(summary));
