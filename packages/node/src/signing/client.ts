import { Blob, Buffer } from 'node:buffer';

import {
  documentTransferTimeoutMs,
  isBearerToken,
  isBearerTokenResponse,
  isNonemptyString,
  isPdf,
  isRecord,
  isXmlText,
  origins,
  parseCallbackUrl,
  parseProviderUrl,
  readBoundedBytes,
  readProviderJson,
} from '../internal/provider.js';

const scope = 'urn:safelayer:eidas:sign:process:document';
const signingPath = '/trustedx-resources/esignsp/v2';
const processPath = `${signingPath}/signer_processes`;
const documentsPath = `${signingPath}/documents`;
const pdfType = 'application/pdf';
const defaultMaxUploadPdfBytes = 10 * 1024 * 1024;
// Leave room for the signature to grow before sending the PDF as Base64 to the SOAP gateway.
const maxAllowedUploadPdfBytes = 20 * 1024 * 1024;
const maxSignedPdfResponseBytes = 32 * 1024 * 1024;

export interface UaePassSigningConfig {
  readonly environment: keyof typeof origins;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly finishCallbackUrl: string;
  /** Maximum size in bytes of the original PDF passed to createProcess(). Defaults to 10 MiB and can be set up to 20 MiB. */
  readonly maxUploadPdfBytes?: number;
}

export interface UaePassSigningToken {
  readonly accessToken: string;
  readonly expiresInSeconds: number;
}

export const UaePassSignatureLevel = {
  Qualified: 'qualified',
  Advanced: 'advanced',
} as const;

export type UaePassSignatureLevel = (typeof UaePassSignatureLevel)[keyof typeof UaePassSignatureLevel];

export const UaePassSignatureAppearance = {
  DateTimeOnly: 'date-time-only',
  SignerAndDateTime: 'signer-and-date-time',
  Hidden: 'hidden',
} as const;

export type UaePassSignatureAppearance =
  (typeof UaePassSignatureAppearance)[keyof typeof UaePassSignatureAppearance];

export interface UaePassCreateSigningProcessInput {
  readonly pdf: Uint8Array;
  readonly filename: string;
  /** The UAE PASS signing level to request. Defaults to qualified. */
  readonly signatureLevel?: UaePassSignatureLevel;
  readonly signatureField: {
    readonly name: string;
    readonly location?: {
      readonly page: 'last' | number;
      readonly rectangle: {
        readonly x: number;
        readonly y: number;
        readonly width: number;
        readonly height: number;
      };
    };
    readonly appearance?: UaePassSignatureAppearance;
  };
}

const dateDetail = { type: 'date', title: 'Signature Date: ' };
const signatureAppearances = {
  [UaePassSignatureAppearance.DateTimeOnly]: { signature_details: { details: [dateDetail] } },
  [UaePassSignatureAppearance.SignerAndDateTime]: {
    signature_details: { details: [{ type: 'subject', title: 'Signer Name: ' }, dateDetail] },
  },
  [UaePassSignatureAppearance.Hidden]: {},
};

export interface UaePassSigningProcess {
  readonly processId: string;
  readonly documentId: string;
  readonly approvalUrl: string;
}

const signingStatuses = ['finished', 'failed', 'failed_documents', 'canceled'] as const;
export type UaePassSigningStatus = (typeof signingStatuses)[number];

export interface UaePassSigningResult {
  readonly status: UaePassSigningStatus;
}

export interface UaePassSigningClient {
  getAccessToken(): Promise<UaePassSigningToken>;
  createProcess(
    input: UaePassCreateSigningProcessInput,
    accessToken: string,
  ): Promise<UaePassSigningProcess>;
  getProcessResult(processId: string, accessToken: string): Promise<UaePassSigningResult>;
  downloadSignedPdf(documentId: string, accessToken: string): Promise<Uint8Array>;
  deleteProcess(processId: string, accessToken: string): Promise<void>;
}

const errorMessages = {
  invalid_client: 'UAE PASS rejected the signing client credentials.',
  invalid_token: 'UAE PASS rejected the signing access token.',
  invalid_response: 'UAE PASS returned an unexpected signing response.',
  rejected: 'UAE PASS rejected the signing request.',
  unavailable: 'The UAE PASS signing service is unavailable.',
  timeout: 'The UAE PASS signing request timed out.',
} as const;

export type UaePassSigningErrorCode = keyof typeof errorMessages;
export type UaePassSigningOperation = 'token' | 'create' | 'result' | 'download' | 'delete';

export class UaePassSigningError extends Error {
  constructor(
    readonly code: UaePassSigningErrorCode,
    readonly operation: UaePassSigningOperation,
    readonly status?: number,
  ) {
    super(errorMessages[code]);
    this.name = 'UaePassSigningError';
  }
}

function isId(value: unknown): value is string {
  return typeof value === 'string' && /^[a-zA-Z0-9_-]+$/.test(value);
}

function isSigningStatus(value: unknown): value is UaePassSigningStatus {
  return signingStatuses.some((status) => status === value);
}

function parseDocumentId(data: unknown, origin: string): string | undefined {
  if (!isRecord(data)) return undefined;
  let id = data.id;
  if (id !== undefined && !isId(id)) return undefined;
  for (const key of ['url', 'content'] as const) {
    if (data[key] === undefined) continue;
    const url = parseProviderUrl(data[key]);
    if (url?.origin !== origin || url.search || !url.pathname.startsWith(`${documentsPath}/`)) {
      return undefined;
    }
    const suffix = key === 'content' ? '/content' : '';
    if (suffix && !url.pathname.endsWith(suffix)) return undefined;
    const urlId = url.pathname.slice(documentsPath.length + 1, url.pathname.length - suffix.length);
    if (!isId(urlId) || (id !== undefined && id !== urlId)) return undefined;
    id = urlId;
  }
  return isId(id) ? id : undefined;
}

function parseSigningProcess(data: unknown, origin: string): UaePassSigningProcess | undefined {
  if (
    !isRecord(data) || !isId(data.id) || !isRecord(data.tasks) ||
    !Array.isArray(data.tasks.pending) || !Array.isArray(data.documents) ||
    data.documents.length !== 1
  ) {
    return undefined;
  }
  const pending: unknown[] = data.tasks.pending;
  const tasks = pending.filter((task): task is Record<string, unknown> =>
    isRecord(task) && task.type === 'UserBrowserTask');
  if (tasks.length !== 1) return undefined;
  const approvalUrl = parseProviderUrl(tasks[0].url);
  if (approvalUrl?.origin !== origin || approvalUrl.pathname !== `${signingPath}/ui`) {
    return undefined;
  }
  const ids = approvalUrl.searchParams.getAll('signerProcessId');
  if (ids.length !== 1 || ids[0] !== data.id) return undefined;
  const documentId = parseDocumentId(data.documents[0], origin);
  if (!documentId) return undefined;
  return { processId: data.id, documentId, approvalUrl: approvalUrl.href };
}

function bearerHeader(accessToken: string): string {
  if (!isBearerToken(accessToken)) throw new TypeError('Provide a valid UAE PASS signing token.');
  return `Bearer ${accessToken}`;
}

function rejectionCode(operation: UaePassSigningOperation, status: number): UaePassSigningErrorCode {
  if (status === 429 || status >= 500) return 'unavailable';
  if (status === 401) return operation === 'token' ? 'invalid_client' : 'invalid_token';
  if (status >= 400) return 'rejected';
  return 'invalid_response';
}

async function request(
  operation: UaePassSigningOperation,
  url: URL,
  init: RequestInit,
  expectedStatus: number,
): Promise<{ response: Response; signal: AbortSignal }> {
  const sendsOrReceivesPdf = operation === 'create' || operation === 'download';
  const signal = AbortSignal.timeout(sendsOrReceivesPdf ? documentTransferTimeoutMs : 15_000);
  let response: Response;
  try {
    response = await fetch(url, { ...init, redirect: 'manual', signal });
  } catch {
    throw new UaePassSigningError(signal.aborted ? 'timeout' : 'unavailable', operation);
  }
  if (response.status !== expectedStatus) {
    void response.body?.cancel().catch(() => {});
    throw new UaePassSigningError(rejectionCode(operation, response.status), operation, response.status);
  }
  return { response, signal };
}

async function readBody<T>(
  operation: UaePassSigningOperation,
  { response, signal }: { response: Response; signal: AbortSignal },
  read: (response: Response) => Promise<T>,
): Promise<T> {
  try {
    return await read(response);
  } catch {
    throw new UaePassSigningError(
      signal.aborted ? 'timeout' : 'invalid_response', operation, response.status,
    );
  }
}

function serializeSignatureLocation(location: UaePassCreateSigningProcessInput['signatureField']['location']) {
  if (location === undefined) return undefined;
  const message = 'Provide a signature location with a PDF page and a valid rectangle.';
  if (!isRecord(location) || !isRecord(location.rectangle)) throw new TypeError(message);
  const { page, rectangle: { x, y, width, height } } = location;
  if (
    (page !== 'last' && (!Number.isSafeInteger(page) || page <= 0)) ||
    ![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0
  ) {
    throw new TypeError(message);
  }
  return { page: { number: String(page) }, rectangle: { x, y, width, height } };
}

function createProcessForm(
  input: UaePassCreateSigningProcessInput,
  finishCallbackUrl: string,
  maxUploadPdfBytes: number,
): FormData {
  const { pdf, filename, signatureField, signatureLevel = UaePassSignatureLevel.Qualified } = input;
  if (!isPdf(pdf) || !isNonemptyString(filename) || /[\u0000-\u001f\u007f/\\]/.test(filename)) {
    throw new TypeError('Provide PDF bytes and a valid document filename.');
  }
  if (pdf.byteLength > maxUploadPdfBytes) {
    throw new TypeError(`Provide an original PDF up to ${maxUploadPdfBytes} bytes.`);
  }
  if (signatureLevel !== UaePassSignatureLevel.Qualified && signatureLevel !== UaePassSignatureLevel.Advanced) {
    throw new TypeError('Choose a supported UAE PASS signature level.');
  }
  if (!isRecord(signatureField) || !isXmlText(signatureField.name) || /[\u0000-\u001f\u007f]/.test(signatureField.name)) {
    throw new TypeError('Provide a valid signature field name.');
  }
  const { name, appearance } = signatureField;
  if (appearance !== undefined && (typeof appearance !== 'string' || !Object.hasOwn(signatureAppearances, appearance))) {
    throw new TypeError('Choose a supported signature appearance.');
  }
  const location = serializeSignatureLocation(signatureField.location);

  const process = {
    process_type: 'urn:safelayer:eidas:processes:document:sign:esigp',
    labels: [['digitalid', 'server', signatureLevel]],
    signer: {
      signature_policy_id: 'urn:safelayer:eidas:policies:sign:document:pdf',
      parameters: {
        type: 'pades-baseline',
        signature_field: {
          name,
          ...(location === undefined ? {} : { location }),
          ...(appearance === undefined ? {} : { appearance: signatureAppearances[appearance] }),
        },
      },
    },
    ui_locales: ['en_US'],
    finish_callback_url: finishCallbackUrl,
    views: { document_agreement: { skip_server_id: 'false' } },
    timestamp: { provider_id: 'urn:uae:tws:generation:policy:digitalid' },
  };
  const form = new FormData();
  form.set('process', JSON.stringify(process));
  form.set('document', new Blob([pdf], { type: pdfType }), filename);
  return form;
}

export function createUaePassSigningClient(config: UaePassSigningConfig): UaePassSigningClient {
  const { environment, clientId, clientSecret, finishCallbackUrl, maxUploadPdfBytes = defaultMaxUploadPdfBytes } = config;
  if (environment !== 'staging' && environment !== 'production') {
    throw new TypeError('Choose a UAE PASS environment.');
  }
  if (!isNonemptyString(clientId) || clientId.includes(':') || !isNonemptyString(clientSecret)) {
    throw new TypeError('Provide valid UAE PASS signing client credentials.');
  }
  const callback = parseCallbackUrl(finishCallbackUrl, environment);
  if (!callback || ['signer_process_id', 'status'].some((key) => callback.searchParams.has(key))) {
    throw new TypeError('Provide the HTTPS signing finish callback URL or use HTTP localhost in staging.');
  }
  if (!Number.isSafeInteger(maxUploadPdfBytes) || maxUploadPdfBytes <= 0 ||
      maxUploadPdfBytes > maxAllowedUploadPdfBytes) {
    throw new TypeError(`Provide maxUploadPdfBytes as a whole number from 1 to ${maxAllowedUploadPdfBytes} bytes.`);
  }

  const origin = origins[environment];
  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');

  return {
    async getAccessToken() {
      const url = new URL('/trustedx-authserver/oauth/main-as/token', origin);
      url.search = new URLSearchParams({ grant_type: 'client_credentials', scope }).toString();
      const result = await request('token', url, {
        method: 'POST',
        headers: { Authorization: `Basic ${basic}`, 'Content-Type': 'text/plain' },
      }, 200);
      const data = await readBody('token', result, readProviderJson);
      if (!isBearerTokenResponse(data)) {
        throw new UaePassSigningError('invalid_response', 'token', result.response.status);
      }
      return { accessToken: data.access_token, expiresInSeconds: data.expires_in };
    },

    async createProcess(input, accessToken) {
      const result = await request('create', new URL(processPath, origin), {
        method: 'POST',
        headers: { Authorization: bearerHeader(accessToken), 'Cache-Control': 'no-cache' },
        body: createProcessForm(input, finishCallbackUrl, maxUploadPdfBytes),
      }, 201);
      const data = await readBody('create', result, readProviderJson);
      const process = parseSigningProcess(data, origin);
      if (!process) throw new UaePassSigningError('invalid_response', 'create', result.response.status);
      return process;
    },

    async getProcessResult(processId, accessToken) {
      if (!isId(processId)) throw new TypeError('Provide a valid UAE PASS signing process ID.');
      const result = await request('result', new URL(`${processPath}/${processId}/result`, origin), {
        method: 'GET',
        headers: { Authorization: bearerHeader(accessToken) },
      }, 200);
      const data = await readBody('result', result, readProviderJson);
      if (!isRecord(data) || !isSigningStatus(data.status)) {
        throw new UaePassSigningError('invalid_response', 'result', result.response.status);
      }
      return { status: data.status };
    },

    async downloadSignedPdf(documentId, accessToken) {
      if (!isId(documentId)) throw new TypeError('Provide a valid UAE PASS signing document ID.');
      const result = await request('download', new URL(`${documentsPath}/${documentId}/content`, origin), {
        method: 'GET',
        headers: { Authorization: bearerHeader(accessToken), Accept: pdfType },
      }, 200);
      const contentType = result.response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
      if (contentType !== pdfType) {
        void result.response.body?.cancel().catch(() => {});
        throw new UaePassSigningError('invalid_response', 'download', result.response.status);
      }
      const bytes = await readBody('download', result, (response) => readBoundedBytes(response, maxSignedPdfResponseBytes));
      if (!isPdf(bytes)) throw new UaePassSigningError('invalid_response', 'download', result.response.status);
      return bytes;
    },

    async deleteProcess(processId, accessToken) {
      if (!isId(processId)) throw new TypeError('Provide a valid UAE PASS signing process ID.');
      await request('delete', new URL(`${processPath}/${processId}`, origin), {
        method: 'DELETE',
        headers: { Authorization: bearerHeader(accessToken) },
      }, 204);
    },
  };
}
