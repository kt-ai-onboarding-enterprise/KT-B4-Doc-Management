#!/usr/bin/env node

const API_VERSION = process.env.SF_API_VERSION || 'v66.0';
const INSTANCE_URL = trimTrailingSlash(process.env.SF_INSTANCE_URL || '');
const ACCESS_TOKEN = process.env.SF_ACCESS_TOKEN || '';

const requestDocumentTool = {
  name: 'kt_request_document',
  description:
    'Create a KT_Document_Request__c checklist row for an onboarding record, optionally resolving a KT_DocumentTemplate__c by template id or template name.',
  inputSchema: {
    type: 'object',
    additionalProperties: false,
    required: ['onboardingId'],
    properties: {
      onboardingId: {
        type: 'string',
        description: 'Salesforce Id of the KT_Onboarding__c record.'
      },
      templateId: {
        type: 'string',
        description: 'Optional Salesforce Id of the KT_DocumentTemplate__c record.'
      },
      templateName: {
        type: 'string',
        description: 'Optional exact Template_Name__c value. Used only when templateId is not supplied.'
      },
      documentDirection: {
        type: 'string',
        enum: ['Outbound', 'Inbound', 'Both'],
        default: 'Inbound'
      },
      status: {
        type: 'string',
        enum: ['Not Started', 'In Progress', 'Awaiting Signature', 'Complete', 'Waived', 'Rejected'],
        default: 'Not Started'
      },
      isRequired: {
        type: 'boolean',
        default: true
      },
      dueDate: {
        type: 'string',
        description: 'Optional due date in YYYY-MM-DD format.'
      },
      waiverReason: {
        type: 'string',
        description: 'Optional waiver reason when status is Waived.'
      }
    }
  }
};

const uploadDocumentTool = {
  name: 'kt_upload_document',
  description:
    'Upload a base64 document to Salesforce Files, create a KT_DocumentVault__c entry, and optionally complete a KT_Document_Request__c row.',
  inputSchema: {
    type: 'object',
    additionalProperties: false,
    required: ['onboardingId', 'fileName', 'contentBase64'],
    properties: {
      onboardingId: {
        type: 'string',
        description: 'Salesforce Id of the KT_Onboarding__c record.'
      },
      documentRequestId: {
        type: 'string',
        description: 'Optional KT_Document_Request__c Id to link and mark Complete.'
      },
      fileName: {
        type: 'string',
        description: 'Original file name, including extension.'
      },
      contentBase64: {
        type: 'string',
        description: 'Base64-encoded file bytes.'
      },
      documentType: {
        type: 'string',
        default: 'Uploaded',
        enum: ['Generated', 'Uploaded', 'External', 'Contract', 'Certificate', 'Identity Document', 'Compliance Record']
      },
      vaultStatus: {
        type: 'string',
        default: 'Draft'
      },
      ocrStatus: {
        type: 'string',
        default: 'Pending',
        enum: ['Not Required', 'Pending', 'Processing', 'Review Required', 'Accepted', 'Failed']
      },
      signatureStatus: {
        type: 'string',
        default: 'Not Required',
        enum: ['Not Required', 'Pending', 'Partially Signed', 'Fully Signed', 'Expired', 'Delegated']
      },
      regulatoryTag: {
        type: 'string'
      }
    }
  }
};

const getDocumentVaultTool = {
  name: 'kt_get_document_vault',
  description:
    'Return KT_DocumentVault__c rows for an onboarding record, with optional Salesforce File version history.',
  inputSchema: {
    type: 'object',
    additionalProperties: false,
    required: ['onboardingId'],
    properties: {
      onboardingId: {
        type: 'string',
        description: 'Salesforce Id of the KT_Onboarding__c record.'
      },
      includeVersionHistory: {
        type: 'boolean',
        default: false
      },
      includeSignatureRequests: {
        type: 'boolean',
        default: true
      },
      includeOcrJobs: {
        type: 'boolean',
        default: true
      }
    }
  }
};

const dispatchSigningTool = {
  name: 'kt_dispatch_signing',
  description:
    'Create a KT_Signature_Request__c and child KT_Signer__c rows for a vault document. Provider API send remains handled by Salesforce services or configured provider workflows.',
  inputSchema: {
    type: 'object',
    additionalProperties: false,
    required: ['vaultEntryId', 'signers'],
    properties: {
      vaultEntryId: {
        type: 'string',
        description: 'Salesforce Id of the KT_DocumentVault__c record.'
      },
      onboardingId: {
        type: 'string',
        description: 'Optional KT_Onboarding__c Id. When absent, it is resolved from the vault entry.'
      },
      signingProvider: {
        type: 'string',
        enum: ['KT Sign', 'DocuSign', 'Adobe Sign'],
        default: 'KT Sign'
      },
      signingOrder: {
        type: 'string',
        enum: ['Sequential', 'Parallel'],
        default: 'Sequential'
      },
      expiryDays: {
        type: 'number',
        default: 7
      },
      externalEnvelopeId: {
        type: 'string',
        description: 'Optional provider envelope/agreement id when already created.'
      },
      signers: {
        type: 'array',
        minItems: 1,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'email'],
          properties: {
            name: { type: 'string' },
            email: { type: 'string' },
            role: {
              type: 'string',
              default: 'Onboardee',
              enum: ['Onboardee', 'HR Admin', 'Hiring Manager', 'Legal Counsel', 'Compliance Officer']
            },
            order: { type: 'number' }
          }
        }
      }
    }
  }
};

let buffer = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  let separatorIndex;
  while ((separatorIndex = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, separatorIndex).trim();
    buffer = buffer.slice(separatorIndex + 1);
    if (line.length > 0) {
      handleLine(line);
    }
  }
});

async function handleLine(line) {
  let request;
  try {
    request = JSON.parse(line);
  } catch (error) {
    writeError(null, -32700, 'Parse error', error.message);
    return;
  }

  try {
    if (request.method === 'initialize') {
      writeResult(request.id, {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'kt-b4-document-tools', version: '1.0.0' }
      });
      return;
    }

    if (request.method === 'notifications/initialized') {
      return;
    }

    if (request.method === 'tools/list') {
      writeResult(request.id, {
        tools: [requestDocumentTool, uploadDocumentTool, getDocumentVaultTool, dispatchSigningTool]
      });
      return;
    }

    if (request.method === 'tools/call') {
      const toolName = request.params?.name;
      if (toolName === 'kt_request_document') {
        const result = await ktRequestDocument(request.params?.arguments || {});
        writeResult(request.id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
          structuredContent: result
        });
        return;
      }
      if (toolName === 'kt_upload_document') {
        const result = await ktUploadDocument(request.params?.arguments || {});
        writeResult(request.id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
          structuredContent: result
        });
        return;
      }
      if (toolName === 'kt_get_document_vault') {
        const result = await ktGetDocumentVault(request.params?.arguments || {});
        writeResult(request.id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
          structuredContent: result
        });
        return;
      }
      if (toolName === 'kt_dispatch_signing') {
        const result = await ktDispatchSigning(request.params?.arguments || {});
        writeResult(request.id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
          structuredContent: result
        });
        return;
      }
      {
        writeError(request.id, -32602, `Unknown tool: ${toolName}`);
        return;
      }
    }

    writeError(request.id, -32601, `Method not found: ${request.method}`);
  } catch (error) {
    writeError(request.id, -32000, error.message);
  }
}

async function ktRequestDocument(args) {
  ensureSalesforceConfig();
  validateSalesforceId(args.onboardingId, 'onboardingId');

  let templateId = args.templateId;
  if (templateId) {
    validateSalesforceId(templateId, 'templateId');
  } else if (args.templateName) {
    templateId = await resolveTemplateId(args.templateName);
  }

  const fields = {
    KT_Onboarding__c: args.onboardingId,
    Status__c: args.status || 'Not Started',
    Document_Direction__c: args.documentDirection || 'Inbound',
    Is_Required__c: args.isRequired !== false
  };
  if (templateId) {
    fields.Document_Template__c = templateId;
  }
  if (args.dueDate) {
    validateDate(args.dueDate, 'dueDate');
    fields.Due_Date__c = args.dueDate;
  }
  if (args.waiverReason) {
    fields.Waiver_Reason__c = args.waiverReason;
  }

  const createResponse = await salesforceFetch('/sobjects/KT_Document_Request__c', {
    method: 'POST',
    body: JSON.stringify(fields)
  });

  return {
    success: true,
    documentRequestId: createResponse.id,
    onboardingId: args.onboardingId,
    templateId: templateId || null,
    status: fields.Status__c,
    documentDirection: fields.Document_Direction__c,
    isRequired: fields.Is_Required__c
  };
}

async function ktUploadDocument(args) {
  ensureSalesforceConfig();
  validateSalesforceId(args.onboardingId, 'onboardingId');
  if (args.documentRequestId) {
    validateSalesforceId(args.documentRequestId, 'documentRequestId');
  }
  if (!args.fileName || !String(args.fileName).trim()) {
    throw new Error('fileName is required.');
  }
  if (!isBase64(args.contentBase64)) {
    throw new Error('contentBase64 must be valid base64.');
  }

  const contentVersion = await salesforceFetch('/sobjects/ContentVersion', {
    method: 'POST',
    body: JSON.stringify({
      Title: fileTitle(args.fileName),
      PathOnClient: args.fileName,
      VersionData: args.contentBase64
    })
  });

  const contentRecord = await salesforceFetch(
    '/query?q=' +
      encodeURIComponent(
        `SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = '${contentVersion.id}' LIMIT 1`
      ),
    { method: 'GET' }
  );
  const contentDocumentId = contentRecord.records?.[0]?.ContentDocumentId;
  if (!contentDocumentId) {
    throw new Error('ContentVersion was created but ContentDocumentId was not returned.');
  }

  const vaultFields = {
    KT_Onboarding__c: args.onboardingId,
    Document_Name__c: args.fileName,
    Content_Document_Id__c: contentDocumentId,
    Document_Type__c: args.documentType || 'Uploaded',
    Status__c: args.vaultStatus || 'Draft',
    OCR_Status__c: args.ocrStatus || 'Pending',
    Signature_Status__c: args.signatureStatus || 'Not Required',
    Version_Number__c: 1,
    Upload_Timestamp__c: new Date().toISOString()
  };
  if (args.documentRequestId) {
    vaultFields.Document_Request__c = args.documentRequestId;
  }
  if (args.regulatoryTag) {
    vaultFields.Regulatory_Tag__c = args.regulatoryTag;
  }

  const vaultResponse = await salesforceFetch('/sobjects/KT_DocumentVault__c', {
    method: 'POST',
    body: JSON.stringify(vaultFields)
  });

  if (args.documentRequestId) {
    await salesforceFetch(`/sobjects/KT_Document_Request__c/${args.documentRequestId}`, {
      method: 'PATCH',
      body: JSON.stringify({
        Status__c: 'Complete',
        Completed_Date__c: new Date().toISOString(),
        Document_Vault_Entry__c: vaultResponse.id
      })
    });
  }

  return {
    success: true,
    onboardingId: args.onboardingId,
    documentRequestId: args.documentRequestId || null,
    contentVersionId: contentVersion.id,
    contentDocumentId,
    vaultEntryId: vaultResponse.id,
    fileName: args.fileName
  };
}

async function ktGetDocumentVault(args) {
  ensureSalesforceConfig();
  validateSalesforceId(args.onboardingId, 'onboardingId');

  const vaultQuery = [
    'SELECT Id, Document_Name__c, Content_Document_Id__c, Document_Type__c, Status__c,',
    'OCR_Status__c, Signature_Status__c, Version_Number__c, Regulatory_Tag__c, Upload_Timestamp__c',
    `FROM KT_DocumentVault__c WHERE KT_Onboarding__c = '${args.onboardingId}'`,
    'ORDER BY CreatedDate ASC'
  ].join(' ');
  const vaultResult = await salesforceFetch('/query?q=' + encodeURIComponent(vaultQuery), { method: 'GET' });
  const vaultEntries = (vaultResult.records || []).map(stripAttributes);

  const contentDocumentIds = vaultEntries
    .map((entry) => entry.Content_Document_Id__c)
    .filter((id) => id && /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(id));

  let versionsByDocumentId = {};
  if (args.includeVersionHistory === true && contentDocumentIds.length > 0) {
    const quotedIds = contentDocumentIds.map((id) => `'${id}'`).join(',');
    const versionQuery = [
      'SELECT Id, ContentDocumentId, Title, VersionNumber, FileType, ContentSize, CreatedDate',
      `FROM ContentVersion WHERE ContentDocumentId IN (${quotedIds})`,
      'ORDER BY ContentDocumentId ASC, VersionNumber DESC'
    ].join(' ');
    const versionResult = await salesforceFetch('/query?q=' + encodeURIComponent(versionQuery), { method: 'GET' });
    versionsByDocumentId = groupBy(versionResult.records || [], 'ContentDocumentId');
  }

  const vaultIds = vaultEntries.map((entry) => entry.Id);
  let signatureRequestsByVaultId = {};
  if (args.includeSignatureRequests !== false && vaultIds.length > 0) {
    const signatureQuery = [
      'SELECT Id, KT_DocumentVault__c, Signing_Provider__c, Status__c, Signing_Order__c,',
      'Total_Signers__c, Completed_Signers__c, Expiry_Date__c, External_Envelope_Id__c, Completed_Document_Id__c',
      `FROM KT_Signature_Request__c WHERE KT_DocumentVault__c IN (${vaultIds.map((id) => `'${id}'`).join(',')})`,
      'ORDER BY CreatedDate ASC'
    ].join(' ');
    const signatureResult = await salesforceFetch('/query?q=' + encodeURIComponent(signatureQuery), { method: 'GET' });
    signatureRequestsByVaultId = groupBy(signatureResult.records || [], 'KT_DocumentVault__c');
  }

  let ocrJobsByVaultId = {};
  if (args.includeOcrJobs !== false && vaultIds.length > 0) {
    const ocrQuery = [
      'SELECT Id, KT_DocumentVault__c, OCR_Provider__c, Job_Id__c, Status__c,',
      'Document_Type_Detected__c, Confidence_Score__c, Retry_Count__c, Reviewed_At__c',
      `FROM KT_OCR_Job__c WHERE KT_DocumentVault__c IN (${vaultIds.map((id) => `'${id}'`).join(',')})`,
      'ORDER BY CreatedDate ASC'
    ].join(' ');
    const ocrResult = await salesforceFetch('/query?q=' + encodeURIComponent(ocrQuery), { method: 'GET' });
    ocrJobsByVaultId = groupBy(ocrResult.records || [], 'KT_DocumentVault__c');
  }

  return {
    onboardingId: args.onboardingId,
    count: vaultEntries.length,
    vaultEntries: vaultEntries.map((entry) => ({
      ...entry,
      versionHistory: versionsByDocumentId[entry.Content_Document_Id__c] || [],
      signatureRequests: signatureRequestsByVaultId[entry.Id] || [],
      ocrJobs: ocrJobsByVaultId[entry.Id] || []
    }))
  };
}

async function ktDispatchSigning(args) {
  ensureSalesforceConfig();
  validateSalesforceId(args.vaultEntryId, 'vaultEntryId');
  if (args.onboardingId) {
    validateSalesforceId(args.onboardingId, 'onboardingId');
  }
  if (!Array.isArray(args.signers) || args.signers.length === 0) {
    throw new Error('signers must include at least one signer.');
  }

  const onboardingId = args.onboardingId || (await resolveVaultOnboardingId(args.vaultEntryId));
  const signingProvider = args.signingProvider || 'KT Sign';
  const signingOrder = args.signingOrder || 'Sequential';
  const expiryDays = Number.isFinite(args.expiryDays) ? args.expiryDays : 7;

  const signatureRequest = await salesforceFetch('/sobjects/KT_Signature_Request__c', {
    method: 'POST',
    body: JSON.stringify({
      KT_DocumentVault__c: args.vaultEntryId,
      KT_Onboarding__c: onboardingId,
      Signing_Provider__c: signingProvider,
      Status__c: args.externalEnvelopeId ? 'Configured' : 'In Progress',
      Signing_Order__c: signingOrder,
      Total_Signers__c: args.signers.length,
      Completed_Signers__c: 0,
      Expiry_Date__c: dateAfterDays(expiryDays),
      External_Envelope_Id__c: args.externalEnvelopeId || null
    })
  });

  const signerIds = [];
  for (let index = 0; index < args.signers.length; index += 1) {
    const signer = args.signers[index];
    validateEmail(signer.email, `signers[${index}].email`);
    const signerResponse = await salesforceFetch('/sobjects/KT_Signer__c', {
      method: 'POST',
      body: JSON.stringify({
        KT_Signature_Request__c: signatureRequest.id,
        Signer_Name__c: signer.name,
        Signer_Email__c: signer.email,
        Signer_Role__c: signer.role || 'Onboardee',
        Signing_Order__c: signer.order || index + 1,
        Status__c: signingProvider === 'KT Sign' ? 'Invitation Sent' : 'Pending'
      })
    });
    signerIds.push(signerResponse.id);
  }

  await salesforceFetch(`/sobjects/KT_DocumentVault__c/${args.vaultEntryId}`, {
    method: 'PATCH',
    body: JSON.stringify({
      Status__c: 'Pending Signature',
      Signature_Status__c: 'Pending'
    })
  });

  return {
    success: true,
    signatureRequestId: signatureRequest.id,
    vaultEntryId: args.vaultEntryId,
    onboardingId,
    signingProvider,
    signingOrder,
    signerIds
  };
}

async function resolveVaultOnboardingId(vaultEntryId) {
  const result = await salesforceFetch(
    '/query?q=' +
      encodeURIComponent(`SELECT Id, KT_Onboarding__c FROM KT_DocumentVault__c WHERE Id = '${vaultEntryId}' LIMIT 1`),
    { method: 'GET' }
  );
  const onboardingId = result.records?.[0]?.KT_Onboarding__c;
  if (!onboardingId) {
    throw new Error(`No KT_DocumentVault__c found for vaultEntryId '${vaultEntryId}'.`);
  }
  return onboardingId;
}

async function resolveTemplateId(templateName) {
  const escapedName = String(templateName).replaceAll("'", "\\'");
  const query =
    "SELECT Id, Template_Name__c FROM KT_DocumentTemplate__c WHERE Template_Name__c = '" +
    escapedName +
    "' AND Is_Active__c = true LIMIT 1";
  const result = await salesforceFetch('/query?q=' + encodeURIComponent(query), { method: 'GET' });
  if (!result.records || result.records.length === 0) {
    throw new Error(`No active KT_DocumentTemplate__c found for templateName '${templateName}'.`);
  }
  return result.records[0].Id;
}

async function salesforceFetch(path, options) {
  const response = await fetch(`${INSTANCE_URL}/services/data/${API_VERSION}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${ACCESS_TOKEN}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    }
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`Salesforce API ${response.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

function ensureSalesforceConfig() {
  if (!INSTANCE_URL || !ACCESS_TOKEN) {
    throw new Error('SF_INSTANCE_URL and SF_ACCESS_TOKEN must be set before calling kt_request_document.');
  }
}

function validateSalesforceId(value, fieldName) {
  if (!/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(String(value || ''))) {
    throw new Error(`${fieldName} must be a 15 or 18 character Salesforce Id.`);
  }
}

function validateDate(value, fieldName) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) {
    throw new Error(`${fieldName} must use YYYY-MM-DD format.`);
  }
}

function validateEmail(value, fieldName) {
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(value || ''))) {
    throw new Error(`${fieldName} must be a valid email address.`);
  }
}

function dateAfterDays(days) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + Math.max(0, Math.trunc(days)));
  return date.toISOString().slice(0, 10);
}

function isBase64(value) {
  if (!value || typeof value !== 'string') {
    return false;
  }
  return /^[A-Za-z0-9+/]*={0,2}$/.test(value) && value.length % 4 === 0;
}

function fileTitle(fileName) {
  return String(fileName).replace(/\.[^.]+$/, '').slice(0, 255) || 'Uploaded Document';
}

function stripAttributes(record) {
  const { attributes, ...rest } = record;
  return rest;
}

function groupBy(records, fieldName) {
  return records.reduce((groups, record) => {
    const cleanRecord = stripAttributes(record);
    const key = cleanRecord[fieldName];
    if (!groups[key]) {
      groups[key] = [];
    }
    groups[key].push(cleanRecord);
    return groups;
  }, {});
}

function trimTrailingSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function writeResult(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
}

function writeError(id, code, message, data) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code, message, data } }) + '\n');
}
