@IsTest
private class KT_DocumentGeneratorServiceTest {
    private static KT_Onboarding__c createOnboarding() {
        KT_Onboarding__c onboarding = new KT_Onboarding__c(
            Candidate_Name__c = 'Asha Raman',
            Role__c = 'Clinical Analyst',
            Department__c = 'Care Operations',
            Work_Location__c = 'Bengaluru',
            Start_Date__c = Date.today().addDays(14),
            Hiring_Manager__c = UserInfo.getUserId()
        );
        insert onboarding;
        return onboarding;
    }

    private static Id createTemplateFile(String body) {
        ContentVersion version = new ContentVersion(
            Title = 'Template File',
            PathOnClient = 'template.txt',
            VersionData = Blob.valueOf(body)
        );
        insert version;

        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    @IsTest
    static void extractsTokensFromJsonArrayAndPreviewData() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Preview Template',
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = '[{"token":"{{Id}}","fieldPath":"Id"},{"token":"{{TODAY+30}}","fieldPath":"TODAY+30"}]',
            Requires_Signature__c = false,
            Is_Active__c = true,
            Version__c = 1
        );
        insert template;

        Test.startTest();
        Map<String, String> previewData = KT_DocumentGeneratorService.getPreviewData(template.Id, onboarding.Id);
        Test.stopTest();

        System.assertEquals(String.valueOf(onboarding.Id), previewData.get('{{Id}}'));
        System.assertEquals(String.valueOf(Date.today().addDays(30)), previewData.get('{{TODAY+30}}'));
    }

    @IsTest
    static void resolvesMergeFieldsAndLeavesUnresolvedTokensVisible() {
        String mergeJson = '{"{{Name}}":"Name","{{Unsafe}}":"Name FROM User","{{TODAY}}":"TODAY"}';

        Test.startTest();
        String rendered = KT_DocumentGeneratorService.resolveMergeFields(mergeJson, UserInfo.getUserId());
        Test.stopTest();

        System.assert(rendered.contains(UserInfo.getName()), 'Expected the current user name to be merged.');
        System.assert(rendered.contains('{{Unsafe}}'), 'Unsafe dynamic field paths must remain unresolved.');
        System.assert(rendered.contains(String.valueOf(Date.today())), 'Expected dynamic TODAY token to be resolved.');
    }

    @IsTest
    static void generatesDocumentAndCompletesMatchingRequest() {
        KT_Onboarding__c onboarding = createOnboarding();
        Id templateDocumentId = createTemplateFile('Offer letter for {{Id}}');
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Offer Letter',
            Template_Binary__c = templateDocumentId,
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = '{"{{Id}}":"Id"}',
            Requires_Signature__c = false,
            Is_Active__c = true,
            Version__c = 1,
            Regulatory_Framework__c = 'SOX'
        );
        insert template;

        KT_Document_Request__c request = new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Outbound',
            Is_Required__c = true
        );
        insert request;

        Test.startTest();
        KT_DocumentGeneratorService.KT_DocGenResult result =
            KT_DocumentGeneratorService.generateDocument(onboarding.Id, template.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.vaultEntryId);
        System.assertNotEquals(null, result.contentDocumentId);

        ContentVersion generatedVersion = [
            SELECT PathOnClient, VersionData
            FROM ContentVersion
            WHERE Id = :result.contentVersionId
        ];
        System.assertEquals('Offer Letter.pdf', generatedVersion.PathOnClient);
        System.assert(
            generatedVersion.VersionData.toString().startsWith('%PDF-1.4'),
            'PDF output should be a real PDF stream, not plain text.'
        );

        KT_DocumentVault__c vault = [
            SELECT KT_Onboarding__c, Document_Name__c, Status__c, Signature_Status__c, Regulatory_Tag__c
            FROM KT_DocumentVault__c
            WHERE Id = :result.vaultEntryId
        ];
        System.assertEquals(onboarding.Id, vault.KT_Onboarding__c);
        System.assertEquals('Offer Letter', vault.Document_Name__c);
        System.assertEquals('Verified', vault.Status__c);
        System.assertEquals('Not Required', vault.Signature_Status__c);
        System.assertEquals('SOX', vault.Regulatory_Tag__c);

        KT_Document_Request__c updatedRequest = [
            SELECT Status__c, Document_Vault_Entry__c, Completed_Date__c
            FROM KT_Document_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('Complete', updatedRequest.Status__c);
        System.assertEquals(result.vaultEntryId, updatedRequest.Document_Vault_Entry__c);
        System.assertNotEquals(null, updatedRequest.Completed_Date__c);
    }

    @IsTest
    static void generatesDocumentSpecificFallbackBodyWhenTemplateFileIsMissing() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Healthcare - HIPAA Agreement',
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = '{"{{Candidate_Name__c}}":"Candidate_Name__c","{{Role__c}}":"Role__c"}',
            Requires_Signature__c = true,
            Is_Active__c = true,
            Version__c = 1,
            Regulatory_Framework__c = 'HIPAA'
        );
        insert template;

        Test.startTest();
        KT_DocumentGeneratorService.KT_DocGenResult result =
            KT_DocumentGeneratorService.generateDocument(onboarding.Id, template.Id);
        Test.stopTest();

        ContentVersion generatedVersion = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :result.contentVersionId
        ];
        String generatedBody = generatedVersion.VersionData.toString();
        System.assert(generatedBody.contains('HIPAA CONFIDENTIALITY AND PRIVACY AGREEMENT'));
        System.assert(generatedBody.contains('Asha Raman'));
        System.assert(generatedBody.contains('Clinical Analyst'));
        System.assert(generatedBody.contains('Care Operations'));
    }

    @IsTest
    static void generateFromDIEProcessesOutboundRequests() {
        KT_Onboarding__c onboarding = createOnboarding();
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Signature Template',
            Output_Format__c = 'DOCX',
            Merge_Field_Map__c = 'Document for {{Id}}',
            Requires_Signature__c = true,
            Is_Active__c = true,
            Version__c = 1
        );
        insert template;

        insert new KT_Document_Request__c(
            KT_Onboarding__c = onboarding.Id,
            Document_Template__c = template.Id,
            Status__c = 'Not Started',
            Document_Direction__c = 'Both',
            Is_Required__c = true
        );

        Test.startTest();
        List<KT_DocumentGeneratorService.KT_DocGenResult> results =
            KT_DocumentGeneratorService.generateFromDIE(onboarding.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].requiresSignature);

        KT_Document_Request__c request = [
            SELECT Status__c, Completed_Date__c, Document_Vault_Entry__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboarding.Id
            LIMIT 1
        ];
        System.assertEquals('Awaiting Signature', request.Status__c);
        System.assertEquals(null, request.Completed_Date__c);
        System.assertNotEquals(null, request.Document_Vault_Entry__c);
    }

    @IsTest
    static void rejectsMissingRequiredInputs() {
        KT_DocumentTemplate__c template = new KT_DocumentTemplate__c(
            Template_Name__c = 'Required Inputs Template',
            Output_Format__c = 'PDF',
            Merge_Field_Map__c = '{"{{Name}}":"Name"}',
            Requires_Signature__c = false,
            Is_Active__c = true,
            Version__c = 1
        );
        insert template;

        try {
            KT_DocumentGeneratorService.generateDocument(null, template.Id);
            System.assert(false, 'Expected an exception for missing onboardingId.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        try {
            KT_DocumentGeneratorService.getPreviewData(null, UserInfo.getUserId());
            System.assert(false, 'Expected an exception for missing templateId.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
    }
}
