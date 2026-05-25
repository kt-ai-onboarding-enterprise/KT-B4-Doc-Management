public with sharing class KT_DocumentGeneratorService {
    private static final Integer MAX_TRAVERSAL_SEGMENTS = 4;
    private static final Pattern MERGE_TOKEN_PATTERN = Pattern.compile('\\{\\{([^}]+)\\}\\}');
    private static final Pattern SAFE_FIELD_PATH_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*){0,3}$');

    public class KT_DocGenResult {
        @AuraEnabled public Id vaultEntryId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id templateId;
        @AuraEnabled public String documentName;
        @AuraEnabled public Boolean requiresSignature;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class DocumentGenerationException extends Exception {}

    @AuraEnabled
    public static KT_DocGenResult generateDocument(Id onboardingId, Id templateId) {
        if (onboardingId == null) {
            throw new AuraHandledException('onboardingId is required.');
        }
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }

        KT_DocumentTemplate__c template = [
            SELECT Id, Template_Name__c, Template_Binary__c, Output_Format__c, Merge_Field_Map__c,
                   Requires_Signature__c, Regulatory_Framework__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        String templateBody = loadTemplateBody(template);
        String renderedDocument = resolveMergeFields(templateBody, onboardingId);
        if (String.isBlank(renderedDocument)) {
            renderedDocument = template.Template_Name__c;
        }

        String extension = getOutputExtension(template.Output_Format__c);
        Blob documentBody = buildDocumentBody(renderedDocument, template.Output_Format__c);
        String documentName = String.isBlank(template.Template_Name__c) ? 'Generated Document' : template.Template_Name__c;
        ContentVersion version = new ContentVersion(
            Title = documentName,
            PathOnClient = documentName + '.' + extension,
            FirstPublishLocationId = onboardingId,
            VersionData = documentBody
        );
        insert version;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        KT_DocumentVault__c vaultEntry = new KT_DocumentVault__c(
            KT_Onboarding__c = onboardingId,
            Document_Name__c = documentName,
            Content_Document_Id__c = insertedVersion.ContentDocumentId,
            Document_Type__c = 'Generated',
            Status__c = template.Requires_Signature__c ? 'Pending Signature' : 'Verified',
            OCR_Status__c = 'Not Required',
            Version_Number__c = 1,
            Signature_Status__c = template.Requires_Signature__c ? 'Pending' : 'Not Required',
            Regulatory_Tag__c = template.Regulatory_Framework__c
        );
        insert vaultEntry;

        updateMatchingDocumentRequest(onboardingId, template.Id, vaultEntry.Id, template.Requires_Signature__c);
        publishDocumentGeneratedEvent(vaultEntry.Id, onboardingId, template.Id, vaultEntry.Document_Type__c);

        KT_DocGenResult result = new KT_DocGenResult();
        result.vaultEntryId = vaultEntry.Id;
        result.contentDocumentId = insertedVersion.ContentDocumentId;
        result.contentVersionId = insertedVersion.Id;
        result.templateId = template.Id;
        result.documentName = documentName;
        result.requiresSignature = template.Requires_Signature__c;
        result.success = true;
        result.message = 'Document generated successfully.';
        return result;
    }

    public static List<KT_DocGenResult> generateFromDIE(Id onboardingId) {
        if (onboardingId == null) {
            throw new DocumentGenerationException('onboardingId is required.');
        }

        List<KT_DocGenResult> results = new List<KT_DocGenResult>();
        List<KT_Document_Request__c> requests = [
            SELECT Id, Document_Template__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboardingId
            AND Document_Template__c != null
            AND Document_Direction__c IN ('Outbound', 'Both')
            AND Status__c IN ('Not Started', 'In Progress')
            ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC
        ];

        for (KT_Document_Request__c request : requests) {
            KT_DocGenResult result = generateDocument(onboardingId, request.Document_Template__c);
            results.add(result);
        }
        return results;
    }

    public static String resolveMergeFields(String templateJson, Id onboardingId) {
        if (String.isBlank(templateJson)) {
            return '';
        }
        if (onboardingId == null) {
            throw new DocumentGenerationException('onboardingId is required.');
        }

        String rendered = templateJson;
        Map<String, String> tokenToFieldPath = extractTokenMap(templateJson);
        for (String token : tokenToFieldPath.keySet()) {
            String fieldPath = tokenToFieldPath.get(token);
            String value = resolveTokenValue(fieldPath, onboardingId);
            rendered = rendered.replace(token, value == null ? token : value);
        }
        return rendered;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPreviewData(Id templateId, Id onboardingId) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }
        if (onboardingId == null) {
            throw new AuraHandledException('onboardingId is required.');
        }

        KT_DocumentTemplate__c template = [
            SELECT Id, Merge_Field_Map__c
            FROM KT_DocumentTemplate__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        Map<String, String> previewData = new Map<String, String>();
        Map<String, String> tokenToFieldPath = extractTokenMap(template.Merge_Field_Map__c);
        for (String token : tokenToFieldPath.keySet()) {
            String value = resolveTokenValue(tokenToFieldPath.get(token), onboardingId);
            previewData.put(token, value == null ? token : value);
        }
        return previewData;
    }

    @TestVisible
    private static Map<String, String> extractTokenMap(String source) {
        Map<String, String> tokenToFieldPath = new Map<String, String>();
        if (String.isBlank(source)) {
            return tokenToFieldPath;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(source);
        } catch (Exception ignored) {
            parsed = null;
        }

        if (parsed instanceof List<Object>) {
            for (Object item : (List<Object>) parsed) {
                if (item instanceof Map<String, Object>) {
                    Map<String, Object> row = (Map<String, Object>) item;
                    String token = firstString(row, new List<String>{ 'token', 'placeholder', 'mergeToken' });
                    String fieldPath = firstString(row, new List<String>{ 'fieldPath', 'field', 'sourceField' });
                    addToken(tokenToFieldPath, token, fieldPath);
                }
            }
        } else if (parsed instanceof Map<String, Object>) {
            for (String token : ((Map<String, Object>) parsed).keySet()) {
                Object value = ((Map<String, Object>) parsed).get(token);
                if (value != null) {
                    addToken(tokenToFieldPath, token, String.valueOf(value));
                }
            }
        }

        Matcher matcher = MERGE_TOKEN_PATTERN.matcher(source);
        while (matcher.find()) {
            String token = matcher.group(0);
            String fieldPath = matcher.group(1).trim();
            if (!tokenToFieldPath.containsKey(token)) {
                addToken(tokenToFieldPath, token, fieldPath);
            }
        }
        return tokenToFieldPath;
    }

    private static String loadTemplateBody(KT_DocumentTemplate__c template) {
        if (!String.isBlank(template.Template_Binary__c)) {
            Id contentDocumentId;
            try {
                contentDocumentId = (Id) template.Template_Binary__c;
            } catch (Exception ignored) {
                contentDocumentId = null;
            }

            if (contentDocumentId != null) {
                List<ContentVersion> versions = [
                    SELECT VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId = :contentDocumentId
                    AND IsLatest = true
                    LIMIT 1
                ];
                if (!versions.isEmpty()) {
                    return versions[0].VersionData.toString();
                }
            }
        }
        String configuredBody = extractConfiguredTemplateBody(template.Merge_Field_Map__c);
        if (!String.isBlank(configuredBody)) {
            return configuredBody;
        }
        return buildDefaultTemplateBody(template);
    }

    private static String extractConfiguredTemplateBody(String source) {
        if (String.isBlank(source)) {
            return null;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(source);
        } catch (Exception ignored) {
            parsed = null;
        }

        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> values = (Map<String, Object>) parsed;
            for (String key : new List<String>{ 'body', 'templateBody', 'content', 'documentBody' }) {
                if (values.containsKey(key) && values.get(key) != null && !String.isBlank(String.valueOf(values.get(key)))) {
                    return String.valueOf(values.get(key));
                }
            }
            return null;
        }
        if (parsed instanceof List<Object>) {
            return null;
        }
        return source;
    }

    private static String buildDefaultTemplateBody(KT_DocumentTemplate__c template) {
        String documentType = inferDocumentType(template);
        if (documentType == 'Offer Letter') {
            return buildOfferLetterBody(template);
        }
        if (documentType == 'HIPAA Agreement') {
            return buildHipaaAgreementBody(template);
        }
        if (documentType == 'Mutual NDA') {
            return buildNdaBody(template);
        }
        if (documentType == 'Background Check Consent') {
            return buildBackgroundConsentBody(template);
        }
        if (documentType == 'Equipment Agreement') {
            return buildEquipmentAgreementBody(template);
        }
        if (documentType == 'Policy Acknowledgment') {
            return buildPolicyAcknowledgmentBody(template);
        }
        return buildGenericOnboardingBody(template, documentType);
    }

    private static String inferDocumentType(KT_DocumentTemplate__c template) {
        String templateName = (template.Template_Name__c == null ? '' : template.Template_Name__c).toLowerCase();
        String framework = (template.Regulatory_Framework__c == null ? '' : template.Regulatory_Framework__c).toLowerCase();
        if (templateName.contains('offer letter')) {
            return 'Offer Letter';
        }
        if (templateName.contains('hipaa')) {
            return 'HIPAA Agreement';
        }
        if (templateName.contains('nda')) {
            return 'Mutual NDA';
        }
        if (templateName.contains('background check')) {
            return 'Background Check Consent';
        }
        if (templateName.contains('equipment')) {
            return 'Equipment Agreement';
        }
        if (templateName.contains('policy')) {
            return 'Policy Acknowledgment';
        }
        if (templateName.contains('training certificate')) {
            return 'Training Certificate';
        }
        if (templateName.contains('safety')) {
            return 'Safety Certification';
        }
        if (templateName.contains('data privacy')) {
            return 'Data Privacy Notice';
        }
        if (framework.contains('hipaa') && templateName.contains('compliance')) {
            return 'HIPAA Agreement';
        }
        return String.isBlank(template.Template_Name__c) ? 'Onboarding Document' : template.Template_Name__c;
    }

    private static String buildCommonHeader(KT_DocumentTemplate__c template, String title) {
        return title + '\n'
            + 'Template: ' + safeTemplateName(template) + '\n'
            + 'Generated Date: {{TODAY}}\n'
            + 'Onboarding Record: {{Name}}\n'
            + 'Candidate: {{Candidate_Name__c}}\n'
            + 'Role: {{Role__c}}\n'
            + 'Department: {{Department__c}}\n'
            + 'Start Date: {{Start_Date__c}}\n'
            + 'Work Location: {{Work_Location__c}}\n'
            + 'Hiring Manager: {{Hiring_Manager__r.Name}}\n\n';
    }

    private static String buildOfferLetterBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'OFFER LETTER')
            + 'Dear {{Candidate_Name__c}},\n\n'
            + 'We are pleased to offer you the role of {{Role__c}} with a planned start date of {{Start_Date__c}}. '
            + 'This offer is associated with onboarding record {{Name}} and will be administered by {{Hiring_Manager__r.Name}}.\n\n'
            + 'Your primary department will be {{Department__c}}, and your expected work location will be {{Work_Location__c}}. '
            + 'This offer is contingent upon completion of required onboarding documents, policy acknowledgments, and any required background or compliance checks.\n\n'
            + 'Please review this letter carefully. By signing, you acknowledge the offered role, start date, and onboarding requirements.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildHipaaAgreementBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'HIPAA CONFIDENTIALITY AND PRIVACY AGREEMENT')
            + 'This agreement applies to {{Candidate_Name__c}} in connection with onboarding record {{Name}}. '
            + 'The candidate may access protected health information only for assigned job duties and only according to company policy, HIPAA requirements, and applicable privacy safeguards.\n\n'
            + 'The candidate agrees to protect patient information, avoid unauthorized disclosure, report suspected privacy incidents promptly, and complete required privacy and security training. '
            + 'Access to systems and records must be limited to the minimum necessary information needed to perform the assigned role of {{Role__c}}.\n\n'
            + 'Violation of this agreement may result in disciplinary action, removal of access, termination, and any required regulatory reporting.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildNdaBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'MUTUAL NON-DISCLOSURE AGREEMENT')
            + 'The parties may exchange confidential business, technical, employee, client, or operational information during onboarding and employment activities. '
            + '{{Candidate_Name__c}} agrees to use confidential information only for authorized business purposes and to protect it from unauthorized access or disclosure.\n\n'
            + 'This obligation continues after the onboarding process unless the information becomes public through no fault of the recipient or disclosure is required by law.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildBackgroundConsentBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'BACKGROUND CHECK CONSENT')
            + '{{Candidate_Name__c}} authorizes the company or its approved vendor to perform background screening for the {{Role__c}} onboarding process. '
            + 'The review may include identity verification, employment verification, education verification, and legally permitted checks relevant to the role.\n\n'
            + 'The candidate confirms that information provided during onboarding is accurate and understands that consent may be withdrawn according to applicable law.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildEquipmentAgreementBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'EQUIPMENT AGREEMENT')
            + '{{Candidate_Name__c}} acknowledges receipt of company equipment or access resources for the {{Role__c}} role. '
            + 'Equipment must be used for authorized business purposes, protected from loss or misuse, and returned when requested or at the end of assignment.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildPolicyAcknowledgmentBody(KT_DocumentTemplate__c template) {
        return buildCommonHeader(template, 'POLICY ACKNOWLEDGMENT')
            + '{{Candidate_Name__c}} acknowledges receipt of applicable company policies for the {{Role__c}} role and agrees to follow all assigned onboarding, compliance, security, safety, and conduct requirements.\n\n'
            + 'Candidate Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String buildGenericOnboardingBody(KT_DocumentTemplate__c template, String documentType) {
        return buildCommonHeader(template, String.valueOf(documentType).toUpperCase())
            + 'This document supports the onboarding process for {{Candidate_Name__c}}. '
            + 'It is generated from the selected B4 template and merged with the current KT Onboarding record data.\n\n'
            + 'The candidate and responsible teams should review the document details, complete any required acknowledgments, and retain the generated file in the document vault.\n\n'
            + 'Acknowledgment Signature: ______________________________\n'
            + 'Date: ______________________________\n';
    }

    private static String safeTemplateName(KT_DocumentTemplate__c template) {
        return String.isBlank(template.Template_Name__c) ? 'Selected Template' : template.Template_Name__c;
    }

    private static String getOutputExtension(String outputFormat) {
        String normalizedFormat = String.isBlank(outputFormat) ? 'PDF' : outputFormat.trim().toUpperCase();
        if (normalizedFormat == 'DOCX') {
            return 'docx';
        }
        return 'pdf';
    }

    private static Blob buildDocumentBody(String renderedDocument, String outputFormat) {
        String normalizedFormat = String.isBlank(outputFormat) ? 'PDF' : outputFormat.trim().toUpperCase();
        if (normalizedFormat == 'PDF') {
            return Blob.valueOf(renderSimplePdf(renderedDocument));
        }
        return Blob.valueOf(renderedDocument);
    }

    private static String renderSimplePdf(String source) {
        PdfSections sections = parsePdfSections(source);
        String contentStream = buildProfessionalPdfContent(sections);

        List<String> objects = new List<String>{
            '<< /Type /Catalog /Pages 2 0 R >>',
            '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
            '<< /Length ' + contentStream.length() + ' >>\nstream\n' + contentStream + 'endstream'
        };

        String pdf = '%PDF-1.4\n';
        List<Integer> offsets = new List<Integer>();
        for (Integer index = 0; index < objects.size(); index++) {
            offsets.add(pdf.length());
            pdf += String.valueOf(index + 1) + ' 0 obj\n' + objects[index] + '\nendobj\n';
        }

        Integer xrefOffset = pdf.length();
        pdf += 'xref\n0 ' + String.valueOf(objects.size() + 1) + '\n';
        pdf += '0000000000 65535 f \n';
        for (Integer offset : offsets) {
            pdf += String.valueOf(offset).leftPad(10, '0') + ' 00000 n \n';
        }
        pdf += 'trailer\n<< /Root 1 0 R /Size ' + String.valueOf(objects.size() + 1) + ' >>\n';
        pdf += 'startxref\n' + String.valueOf(xrefOffset) + '\n%%EOF';
        return pdf;
    }

    private class PdfSections {
        String title;
        List<String> metaLines = new List<String>();
        List<String> bodyLines = new List<String>();
    }

    private static PdfSections parsePdfSections(String source) {
        PdfSections sections = new PdfSections();
        String normalized = String.isBlank(source) ? 'Generated Document' : source.replace('\r\n', '\n').replace('\r', '\n');
        List<String> lines = normalized.split('\n');
        sections.title = lines.isEmpty() || String.isBlank(lines[0]) ? 'Generated Document' : lines[0].trim();

        Boolean inBody = false;
        for (Integer index = 1; index < lines.size(); index++) {
            String line = lines[index] == null ? '' : lines[index].trim();
            if (!inBody && String.isBlank(line)) {
                inBody = true;
                continue;
            }
            if (inBody) {
                sections.bodyLines.add(line);
            } else {
                sections.metaLines.add(line);
            }
        }
        return sections;
    }

    private static String buildProfessionalPdfContent(PdfSections sections) {
        String stream = '';
        stream += 'q\n0.12 0.25 0.40 rg\n0 735 612 42 re f\nQ\n';
        stream += 'q\n0.78 0.84 0.90 rg\n0 726 612 5 re f\nQ\n';
        stream += 'q\n0.96 0.98 1.00 rg\n48 562 516 98 re f\nQ\n';
        stream += 'q\n0.86 0.90 0.95 RG\n48 562 516 98 re S\nQ\n';
        stream += 'q\n0.88 0.88 0.88 RG\n72 124 468 1 re f\nQ\n';

        stream += writeText('KT B4 DOCUMENT OPERATIONS', 54, 752, 8, 'F2', '1 1 1');
        stream += writeText('CONFIDENTIAL', 500, 752, 8, 'F2', '1 1 1');

        Integer titleX = Math.max(64, 306 - (sections.title.length() * 4));
        stream += writeText(sections.title, titleX, 694, 16, 'F2', '0.10 0.13 0.18');
        stream += 'q\n0.12 0.25 0.40 rg\n250 678 112 2 re f\nQ\n';

        Integer metaY = 638;
        Integer metaIndex = 0;
        for (String metaLine : sections.metaLines) {
            if (String.isBlank(metaLine) || metaIndex >= 8) {
                continue;
            }
            List<String> parts = splitLabelValue(metaLine);
            Integer x = Math.mod(metaIndex, 2) == 0 ? 64 : 318;
            Integer y = metaY - (Math.floor(metaIndex / 2).intValue() * 20);
            stream += writeText(parts[0].toUpperCase(), x, y, 7, 'F2', '0.35 0.42 0.52');
            stream += writeText(parts[1], x, y - 10, 9, 'F1', '0.10 0.13 0.18');
            metaIndex++;
        }

        Integer bodyY = 522;
        for (String rawLine : sections.bodyLines) {
            if (bodyY < 178) {
                break;
            }
            if (String.isBlank(rawLine)) {
                bodyY -= 13;
                continue;
            }
            if (rawLine.contains('Signature:') || rawLine == 'Date:' || rawLine.startsWith('Date: ')) {
                continue;
            }
            for (String wrappedLine : wrapWords(rawLine, 92)) {
                if (bodyY < 178) {
                    break;
                }
                stream += writeText(wrappedLine, 72, bodyY, 9, 'F1', '0.16 0.18 0.22');
                bodyY -= 13;
            }
            bodyY -= 5;
        }

        stream += writeText('Acceptance and Signature', 228, 104, 10, 'F2', '0.10 0.13 0.18');
        stream += writeText('Candidate Signature', 84, 78, 8, 'F2', '0.35 0.42 0.52');
        stream += writeText('Date', 386, 78, 8, 'F2', '0.35 0.42 0.52');
        stream += 'q\n0.10 0.13 0.18 RG\n84 68 230 1 re S\n386 68 142 1 re S\nQ\n';
        stream += writeText('Generated by KT B4 Document Operations', 72, 38, 7, 'F1', '0.45 0.50 0.58');
        return stream;
    }

    private static List<String> splitLabelValue(String line) {
        Integer separatorIndex = line == null ? -1 : line.indexOf(':');
        if (separatorIndex <= 0) {
            return new List<String>{ 'Detail', line == null ? '' : line };
        }
        return new List<String>{
            line.substring(0, separatorIndex),
            separatorIndex + 1 >= line.length() ? '' : line.substring(separatorIndex + 1).trim()
        };
    }

    private static List<String> wrapWords(String source, Integer maxLength) {
        List<String> lines = new List<String>();
        String remaining = source == null ? '' : source.replace('\t', ' ').trim();
        while (remaining.length() > maxLength) {
            Integer breakIndex = remaining.lastIndexOf(' ', maxLength);
            if (breakIndex <= 0) {
                breakIndex = maxLength;
            }
            lines.add(remaining.substring(0, breakIndex).trim());
            remaining = remaining.substring(breakIndex).trim();
        }
        if (!String.isBlank(remaining)) {
            lines.add(remaining);
        }
        return lines;
    }

    private static String writeText(String value, Integer x, Integer y, Integer size, String fontName, String rgb) {
        return 'BT\n' + rgb + ' rg\n/' + fontName + ' ' + String.valueOf(size) + ' Tf\n'
            + String.valueOf(x) + ' ' + String.valueOf(y) + ' Td\n(' + escapePdfText(value) + ') Tj\nET\n';
    }

    private static String escapePdfText(String value) {
        String sanitized = value == null ? '' : value.replaceAll('[^ -~]', '?');
        sanitized = sanitized.replace('\\', '\\\\');
        sanitized = sanitized.replace('(', '\\(');
        sanitized = sanitized.replace(')', '\\)');
        return sanitized;
    }

    private static void updateMatchingDocumentRequest(Id onboardingId, Id templateId, Id vaultEntryId, Boolean requiresSignature) {
        List<KT_Document_Request__c> requests = [
            SELECT Id, Status__c, Completed_Date__c, Document_Vault_Entry__c
            FROM KT_Document_Request__c
            WHERE KT_Onboarding__c = :onboardingId
            AND Document_Template__c = :templateId
            AND Status__c IN ('Not Started', 'In Progress', 'Awaiting Signature')
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (requests.isEmpty()) {
            return;
        }

        KT_Document_Request__c request = requests[0];
        request.Document_Vault_Entry__c = vaultEntryId;
        request.Status__c = requiresSignature ? 'Awaiting Signature' : 'Complete';
        if (!requiresSignature) {
            request.Completed_Date__c = System.now();
        }
        update request;
    }

    private static void publishDocumentGeneratedEvent(Id vaultEntryId, Id onboardingId, Id templateId, String documentType) {
        Schema.SObjectType eventType = Schema.getGlobalDescribe().get('KT_Document_Generated__e');
        if (eventType == null) {
            return;
        }

        SObject eventRecord = eventType.newSObject();
        Map<String, Schema.SObjectField> eventFields = eventType.getDescribe().fields.getMap();
        if (eventFields.containsKey('VaultId__c')) {
            eventRecord.put('VaultId__c', String.valueOf(vaultEntryId));
        }
        if (eventFields.containsKey('KT_DocumentVault__c')) {
            eventRecord.put('KT_DocumentVault__c', vaultEntryId);
        }
        if (eventFields.containsKey('Document_Vault_Id__c')) {
            eventRecord.put('Document_Vault_Id__c', String.valueOf(vaultEntryId));
        }
        if (eventFields.containsKey('OnboardingId__c')) {
            eventRecord.put('OnboardingId__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('KT_Onboarding__c')) {
            eventRecord.put('KT_Onboarding__c', onboardingId);
        }
        if (eventFields.containsKey('Onboarding_Id__c')) {
            eventRecord.put('Onboarding_Id__c', String.valueOf(onboardingId));
        }
        if (eventFields.containsKey('TemplateId__c')) {
            eventRecord.put('TemplateId__c', String.valueOf(templateId));
        }
        if (eventFields.containsKey('DocumentType__c')) {
            eventRecord.put('DocumentType__c', documentType);
        }
        if (eventFields.containsKey('Timestamp__c')) {
            eventRecord.put('Timestamp__c', System.now());
        }
        EventBus.publish(eventRecord);
    }

    private static String firstString(Map<String, Object> row, List<String> keys) {
        for (String key : keys) {
            if (row.containsKey(key) && row.get(key) != null) {
                return String.valueOf(row.get(key));
            }
        }
        return null;
    }

    private static void addToken(Map<String, String> tokenToFieldPath, String token, String fieldPath) {
        if (String.isBlank(token) || String.isBlank(fieldPath)) {
            return;
        }
        String normalizedToken = token.startsWith('{{') ? token : '{{' + token + '}}';
        tokenToFieldPath.put(normalizedToken, fieldPath.trim());
    }

    private static String resolveTokenValue(String fieldPath, Id recordId) {
        if (String.isBlank(fieldPath)) {
            return null;
        }

        String normalizedPath = normalizeFieldPath(fieldPath.trim(), recordId.getSObjectType());
        if (isDynamicDateToken(normalizedPath)) {
            return resolveDynamicDate(normalizedPath);
        }
        if (!isSafeFieldPath(normalizedPath)) {
            return null;
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        String query = 'SELECT ' + normalizedPath + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        try {
            SObject record = Database.query(query);
            Object value = getNestedValue(record, normalizedPath);
            return value == null ? null : String.valueOf(value);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String normalizeFieldPath(String fieldPath, Schema.SObjectType sObjectType) {
        String objectApiName = sObjectType.getDescribe().getName();
        if (fieldPath == objectApiName) {
            return 'Id';
        }
        String objectPrefix = objectApiName + '.';
        return fieldPath.startsWith(objectPrefix) ? fieldPath.substring(objectPrefix.length()) : fieldPath;
    }

    private static Boolean isSafeFieldPath(String fieldPath) {
        if (String.isBlank(fieldPath)) {
            return false;
        }
        if (!SAFE_FIELD_PATH_PATTERN.matcher(fieldPath).matches()) {
            return false;
        }
        return fieldPath.split('\\.').size() <= MAX_TRAVERSAL_SEGMENTS;
    }

    private static Boolean isDynamicDateToken(String fieldPath) {
        return fieldPath == 'TODAY' || fieldPath.startsWith('TODAY+') || fieldPath.startsWith('TODAY-');
    }

    private static String resolveDynamicDate(String token) {
        Integer offset = 0;
        if (token.length() > 'TODAY'.length()) {
            String offsetText = token.substring('TODAY'.length());
            if (offsetText.startsWith('+')) {
                offsetText = offsetText.substring(1);
            }
            offset = Integer.valueOf(offsetText);
        }
        return String.valueOf(Date.today().addDays(offset));
    }

    private static Object getNestedValue(SObject record, String fieldPath) {
        List<String> parts = fieldPath.split('\\.');
        SObject current = record;
        for (Integer index = 0; index < parts.size(); index++) {
            String part = parts[index];
            if (index == parts.size() - 1) {
                return current.get(part);
            }
            current = current.getSObject(part);
            if (current == null) {
                return null;
            }
        }
        return null;
    }
}
