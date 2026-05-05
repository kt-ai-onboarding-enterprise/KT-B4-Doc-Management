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
        return template.Merge_Field_Map__c;
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
        List<String> pdfLines = buildPdfLines(source);
        String contentStream = 'BT\n/F1 11 Tf\n14 TL\n50 742 Td\n';
        for (String line : pdfLines) {
            contentStream += '(' + escapePdfText(line) + ') Tj\nT*\n';
        }
        contentStream += 'ET\n';

        List<String> objects = new List<String>{
            '<< /Type /Catalog /Pages 2 0 R >>',
            '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
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

    private static List<String> buildPdfLines(String source) {
        String normalized = String.isBlank(source) ? '' : source.replace('\r\n', '\n').replace('\r', '\n');
        List<String> lines = new List<String>();
        for (String rawLine : normalized.split('\n')) {
            addWrappedPdfLine(lines, rawLine);
            if (lines.size() >= 52) {
                break;
            }
        }
        if (lines.isEmpty()) {
            lines.add('');
        }
        return lines;
    }

    private static void addWrappedPdfLine(List<String> lines, String rawLine) {
        final Integer maxLineLength = 90;
        String remaining = rawLine == null ? '' : rawLine.replace('\t', ' ');
        if (remaining.length() == 0) {
            lines.add('');
            return;
        }

        while (remaining.length() > maxLineLength && lines.size() < 52) {
            lines.add(remaining.substring(0, maxLineLength));
            remaining = remaining.substring(maxLineLength);
        }
        if (lines.size() < 52) {
            lines.add(remaining);
        }
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
