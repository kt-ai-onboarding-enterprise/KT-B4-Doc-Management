/*
 * B4-T047 Template Library Seed
 *
 * Creates the 205 baseline KT_DocumentTemplate__c records required by the B4
 * document management tracker. The script is rerunnable: existing template
 * names are updated, missing template names are inserted.
 *
 * Before production use, upload the approved DOCX/PDF template files to
 * Salesforce Files and populate contentDocumentIds by template name.
 */

Map<String, Integer> domainCounts = new Map<String, Integer>{
    'Healthcare' => 40,
    'Manufacturing' => 30,
    'Retail' => 25,
    'Finance' => 30,
    'Technology' => 25,
    'Government/Public Sector' => 20,
    'Construction' => 15,
    'Generic/All Domains' => 20
};

Map<String, String> domainFrameworks = new Map<String, String>{
    'Healthcare' => 'HIPAA;FDA',
    'Manufacturing' => 'OSHA;ISO 9001',
    'Retail' => 'GDPR',
    'Finance' => 'SOX;GDPR',
    'Technology' => 'GDPR;ISO 9001',
    'Government/Public Sector' => 'GDPR',
    'Construction' => 'OSHA;ISO 45001',
    'Generic/All Domains' => 'GDPR'
};

Map<String, String> domainPersonas = new Map<String, String>{
    'Healthcare' => 'Nurse,Clinician,Credentialed Staff',
    'Manufacturing' => 'Plant Operator,Supervisor,Quality Inspector',
    'Retail' => 'Store Associate,Store Manager,Seasonal Worker',
    'Finance' => 'Analyst,Advisor,Compliance User',
    'Technology' => 'Engineer,Product User,Contractor',
    'Government/Public Sector' => 'Case Worker,Field Officer,Contractor',
    'Construction' => 'Site Worker,Foreman,Subcontractor',
    'Generic/All Domains' => 'Employee,Manager,Contractor'
};

List<String> documentTypes = new List<String>{
    'Offer Letter',
    'Mutual NDA',
    'Compliance Acknowledgment',
    'Onboarding Checklist',
    'Training Certificate',
    'Policy Acknowledgment',
    'Safety Certification',
    'Credential Verification',
    'Tax Form',
    'Equipment Agreement',
    'Handbook Acknowledgment',
    'Benefits Enrollment',
    'Emergency Contact Form',
    'Background Check Consent',
    'Data Privacy Notice',
    'Role Addendum',
    'Probation Review',
    'Exit Checklist',
    'Remote Work Agreement',
    'Access Request'
};

Set<String> signatureTypes = new Set<String>{
    'Offer Letter',
    'Mutual NDA',
    'Compliance Acknowledgment',
    'Policy Acknowledgment',
    'Equipment Agreement',
    'Background Check Consent',
    'Data Privacy Notice',
    'Role Addendum',
    'Remote Work Agreement',
    'Access Request'
};

Map<String, String> contentDocumentIds = new Map<String, String>{
    // Example after files are uploaded:
    // 'Healthcare - Offer Letter 01' => '069xxxxxxxxxxxxxxx'
};

Set<String> targetNames = new Set<String>();
Map<String, KT_DocumentTemplate__c> desiredByName = new Map<String, KT_DocumentTemplate__c>();

for (String domain : domainCounts.keySet()) {
    Integer targetCount = domainCounts.get(domain);
    for (Integer i = 0; i < targetCount; i++) {
        String docType = documentTypes[Math.mod(i, documentTypes.size())];
        Integer displayNumber = i + 1;
        String suffix = displayNumber < 10 ? '0' + String.valueOf(displayNumber) : String.valueOf(displayNumber);
        String templateName = domain + ' - ' + docType + ' ' + suffix;
        Boolean requiresSignature = signatureTypes.contains(docType);

        KT_DocumentTemplate__c templateRecord = new KT_DocumentTemplate__c();
        templateRecord.Template_Name__c = templateName;
        templateRecord.Domain__c = domain == 'Generic/All Domains' ? null : domain;
        templateRecord.Persona__c = domainPersonas.get(domain);
        templateRecord.Output_Format__c = requiresSignature ? 'PDF' : 'Both';
        templateRecord.Requires_Signature__c = requiresSignature;
        templateRecord.Signer_Roles__c = requiresSignature
            ? '[{"role":"Onboardee","order":1},{"role":"HR","order":2}]'
            : '[]';
        templateRecord.Signature_Expiry_Days__c = requiresSignature ? 14 : null;
        templateRecord.Is_Active__c = true;
        templateRecord.Regulatory_Framework__c = domainFrameworks.get(domain);
        templateRecord.Version__c = 1;
        templateRecord.Language__c = 'English';
        templateRecord.Merge_Field_Map__c = JSON.serialize(new List<Object>{
            new Map<String, String>{ 'token' => '{{Name}}', 'fieldPath' => 'Name' },
            new Map<String, String>{ 'token' => '{{Candidate_Name__c}}', 'fieldPath' => 'Candidate_Name__c' },
            new Map<String, String>{ 'token' => '{{Start_Date__c}}', 'fieldPath' => 'Start_Date__c' },
            new Map<String, String>{ 'token' => '{{Role__c}}', 'fieldPath' => 'Role__c' },
            new Map<String, String>{ 'token' => '{{Department__c}}', 'fieldPath' => 'Department__c' },
            new Map<String, String>{ 'token' => '{{Work_Location__c}}', 'fieldPath' => 'Work_Location__c' },
            new Map<String, String>{ 'token' => '{{Hiring_Manager__r.Name}}', 'fieldPath' => 'Hiring_Manager__r.Name' },
            new Map<String, String>{ 'token' => '{{TODAY}}', 'fieldPath' => 'TODAY' }
        });

        if (contentDocumentIds.containsKey(templateName)) {
            templateRecord.Template_Binary__c = contentDocumentIds.get(templateName);
        }

        targetNames.add(templateName);
        desiredByName.put(templateName, templateRecord);
    }
}

Map<String, KT_DocumentTemplate__c> existingByName = new Map<String, KT_DocumentTemplate__c>();
for (KT_DocumentTemplate__c existingTemplate : [
    SELECT Id, Template_Name__c
    FROM KT_DocumentTemplate__c
    WHERE Template_Name__c IN :targetNames
]) {
    existingByName.put(existingTemplate.Template_Name__c, existingTemplate);
}

List<KT_DocumentTemplate__c> toInsert = new List<KT_DocumentTemplate__c>();
List<KT_DocumentTemplate__c> toUpdate = new List<KT_DocumentTemplate__c>();

for (String templateName : desiredByName.keySet()) {
    KT_DocumentTemplate__c desired = desiredByName.get(templateName);
    if (existingByName.containsKey(templateName)) {
        desired.Id = existingByName.get(templateName).Id;
        toUpdate.add(desired);
    } else {
        toInsert.add(desired);
    }
}

if (!toInsert.isEmpty()) {
    insert toInsert;
}
if (!toUpdate.isEmpty()) {
    update toUpdate;
}

System.debug(LoggingLevel.INFO, 'B4-T047 template library seed complete. Inserted=' + toInsert.size() + ', Updated=' + toUpdate.size() + ', Total desired=' + desiredByName.size());
