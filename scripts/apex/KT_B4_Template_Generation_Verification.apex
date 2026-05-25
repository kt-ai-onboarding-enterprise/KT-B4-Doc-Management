Id onboardingId = 'a05g5000006yPHpAAM';

SObject onboarding = [
    SELECT Id
    FROM KT_Onboarding__c
    WHERE Id = :onboardingId
    LIMIT 1
];
onboarding.put('Candidate_Name__c', 'Chethan Kumar');
onboarding.put('Role__c', 'Manufacturing Operations Specialist');
onboarding.put('Department__c', 'Manufacturing Operations');
onboarding.put('Work_Location__c', 'Bengaluru Plant 01');
onboarding.put('Start_Date__c', Date.today().addDays(14));
onboarding.put('Hiring_Manager__c', UserInfo.getUserId());
update onboarding;

List<KT_DocumentTemplate__c> templates = [
    SELECT Id, Template_Name__c, Regulatory_Framework__c
    FROM KT_DocumentTemplate__c
    WHERE Template_Name__c IN ('Manufacturing - Offer Letter 01', 'Healthcare - Compliance Acknowledgment 03')
    ORDER BY Template_Name__c
];

for (KT_DocumentTemplate__c template : templates) {
    KT_DocumentGeneratorService.KT_DocGenResult result =
        KT_DocumentGeneratorService.generateDocument(onboardingId, template.Id);
    ContentVersion version = [
        SELECT Id, ContentDocumentId, Title, VersionData
        FROM ContentVersion
        WHERE Id = :result.contentVersionId
        LIMIT 1
    ];
    String body = version.VersionData.toString();
    System.debug(LoggingLevel.INFO,
        'Generated ' + template.Template_Name__c +
        ' | Vault=' + result.vaultEntryId +
        ' | ContentDocument=' + version.ContentDocumentId +
        ' | ContainsCandidate=' + body.contains('Chethan Kumar') +
        ' | ContainsOffer=' + body.contains('OFFER LETTER') +
        ' | ContainsHIPAA=' + body.contains('HIPAA CONFIDENTIALITY AND PRIVACY AGREEMENT')
    );
}
