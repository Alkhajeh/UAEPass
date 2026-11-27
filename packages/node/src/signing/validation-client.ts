import { Buffer } from 'node:buffer';
import { DOMParser, type Element } from '@xmldom/xmldom';

import { UaePassBaseError } from '../errors.js';
import {
  assertEnvironment,
  classifyStatus,
  decodeUtf8,
  discardBody,
  documentTransferTimeoutMs,
  isPdf,
  isXmlText,
  mediaType,
  origins,
  readBoundedBytes,
  send,
} from '../internal/provider.js';
import type { UaePassEnvironment } from '../types.js';

const gatewayPath = '/trustedx-gw/SoapGateway';
const soap = 'http://schemas.xmlsoap.org/soap/envelope/';
const security = 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd';
const passwordType = 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText';
const dss = 'http://www.docs.oasis-open.org/dss/2004/06/oasis-dss-1.0-core-schema-wd-27.xsd';
const trustedX = 'http://www.safelayer.com/TWS';
const resultPrefix = 'urn:oasis:names:tc:dss:1.0:';
const signerIdentityFormat = 'urn:oasis:names:tc:SAML:1.1:nameid-format:X509SubjectName';
const maxLtvResponseBytes = 48 * 1024 * 1024;
// Every PDF decoded from a bounded Base64 LTV response must fit a verification request.
const maxValidationPdfBytes = (maxLtvResponseBytes / 4) * 3;
const maxVerificationBytes = 128 * 1024;
const xmlMediaTypes = new Set(['text/xml', 'application/xml', 'application/soap+xml']);
const xmlEntities: Readonly<Record<string, string>> = {
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;', '\r': '&#13;',
};

export interface UaePassSigningValidationConfig {
  readonly environment: UaePassEnvironment;
  readonly clientId: string;
  readonly clientSecret: string;
}

export interface UaePassVerifiedPdfSignature {
  readonly signatureFieldName: string;
  /** Certificate subject returned by UAE PASS. It can contain personal data. */
  readonly signerSubject?: string;
}

export interface UaePassFinalizeSignedPdfOptions {
  readonly expectedSignatureFieldName: string;
  /** Match the certificate subject against the expected authenticated signer. */
  readonly matchSigner: (signerSubject: string) => boolean | Promise<boolean>;
}

export interface UaePassFinalizedPdf {
  readonly pdf: Uint8Array;
  readonly signature: UaePassVerifiedPdfSignature & { readonly signerSubject: string };
}

export interface UaePassSigningValidationClient {
  applyLongTermValidation(pdf: Uint8Array, signatureFieldName: string): Promise<Uint8Array>;
  verifySignedPdf(pdf: Uint8Array): Promise<UaePassVerifiedPdfSignature>;
  finalizeSignedPdf(pdf: Uint8Array, options: UaePassFinalizeSignedPdfOptions): Promise<UaePassFinalizedPdf>;
}

const errorMessages = {
  invalid_client: 'UAE PASS rejected the signing validation client credentials.',
  invalid_response: 'UAE PASS returned an unexpected signing SOAP response.',
  rejected: 'UAE PASS did not complete the signing SOAP operation.',
  verification_failed: 'UAE PASS did not verify the requested PDF signature.',
  signer_unverified: 'The verified signature could not be matched to the expected signer.',
  signer_match_failed: 'The signer-matching callback could not complete.',
  unavailable: 'The UAE PASS signing validation service is unavailable.',
  timeout: 'The UAE PASS signing SOAP request timed out.',
} as const;

export type UaePassSigningValidationErrorCode = keyof typeof errorMessages;
type SoapOperation = 'ltv' | 'verify';
export type UaePassSigningValidationOperation = SoapOperation | 'match_signer';

export class UaePassSigningValidationError
  extends UaePassBaseError<UaePassSigningValidationErrorCode, UaePassSigningValidationOperation> {
  constructor(code: UaePassSigningValidationErrorCode, operation: UaePassSigningValidationOperation, status?: number) {
    super(code, operation, errorMessages[code], status);
    this.name = 'UaePassSigningValidationError';
  }
}

function escapeXml(value: string): string {
  return value.replace(/[&<>"'\r]/g, (character) => xmlEntities[character]);
}

function elements(parent: Element): Element[] {
  return Array.from(parent.childNodes).filter((node): node is Element => node.nodeType === 1);
}

function children(parent: Element, namespace: string, name: string): Element[] {
  return elements(parent).filter((element) => element.namespaceURI === namespace && element.localName === name);
}

function requiredChild(parent: Element, namespace: string, name: string): Element {
  const matches = children(parent, namespace, name);
  if (matches.length !== 1) throw new Error('Unexpected XML element count.');
  return matches[0];
}

function elementText(element: Element): string {
  if (elements(element).length !== 0) throw new Error('Unexpected XML child element.');
  return element.textContent ?? '';
}

function childText(parent: Element, namespace: string, name: string): string {
  return elementText(requiredChild(parent, namespace, name)).trim();
}

async function readXml(response: Response, maxResponseBytes: number): Promise<Element> {
  const contentType = mediaType(response);
  if (!contentType || !xmlMediaTypes.has(contentType)) {
    discardBody(response);
    throw new Error('Unexpected SOAP media type.');
  }
  const xml = decodeUtf8(await readBoundedBytes(response, maxResponseBytes));
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw new Error('Unexpected declaration in signing SOAP.');
  const parser = new DOMParser({ onError: () => { throw new Error('Malformed signing SOAP XML.'); } });
  const { documentElement } = parser.parseFromString(xml, 'application/xml');
  if (!documentElement) throw new Error('Missing SOAP envelope.');
  return documentElement;
}

function soapOutputs(
  envelope: Element,
  operation: SoapOperation,
  status: number,
): Element {
  if (envelope.namespaceURI !== soap || envelope.localName !== 'Envelope') {
    throw new Error('Unexpected SOAP envelope.');
  }
  const body = requiredChild(envelope, soap, 'Body');
  const responses = elements(body);
  const [response] = responses;
  if (responses.length !== 1) throw new Error('Unexpected SOAP body.');
  if (response.namespaceURI === soap && response.localName === 'Fault') {
    throw new UaePassSigningValidationError('rejected', operation, status);
  }
  const responseNames = operation === 'ltv' ? ['VerifyResponse', 'SignResponse'] : ['VerifyResponse'];
  if (response.namespaceURI !== dss || !response.localName || !responseNames.includes(response.localName)) {
    throw new Error('Unexpected SOAP response element.');
  }

  const result = requiredChild(response, dss, 'Result');
  if (childText(result, dss, 'ResultMajor') !== `${resultPrefix}resultmajor:Success`) {
    throw new UaePassSigningValidationError('rejected', operation, status);
  }
  if (operation === 'verify' &&
    childText(result, dss, 'ResultMinor') !== `${resultPrefix}resultminor:ValidSignature_OnAllDocuments`) {
    throw new UaePassSigningValidationError('verification_failed', operation, status);
  }
  return requiredChild(response, dss, 'OptionalOutputs');
}

function updatedPdf(outputs: Element): Uint8Array {
  const document = requiredChild(outputs, dss, 'DocumentWithSignature');
  const data = requiredChild(document, dss, 'XMLData');
  const encoded = requiredChild(data, dss, 'Base64Data');
  if (encoded.getAttribute('MimeType') !== 'application/pdf') throw new Error('Unexpected document media type.');
  const value = elementText(encoded).replace(/[\t\n\r ]/g, '');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new Error('Unexpected PDF encoding.');
  }
  const pdf = Buffer.from(value, 'base64');
  if (!isPdf(pdf) || pdf.toString('base64') !== value) {
    throw new Error('Invalid updated PDF.');
  }
  return pdf;
}

function verifiedSignature(outputs: Element, status: number): UaePassVerifiedPdfSignature {
  const verifyingPolicy = requiredChild(outputs, trustedX, 'VerifyingPolicy');
  const validationPolicy = requiredChild(outputs, trustedX, 'ValidationPolicy');
  if (childText(verifyingPolicy, trustedX, 'Identifier') !== 'urn:uae:tws:verification:policy:digitalid' ||
    childText(validationPolicy, trustedX, 'Identifier') !== 'urn:uae:tws:validation:policy:digitalid' ||
    childText(outputs, trustedX, 'NumberPdfSignatures') !== '1') {
    throw new UaePassSigningValidationError('verification_failed', 'verify', status);
  }
  const signatureFieldName = elementText(requiredChild(outputs, trustedX, 'PdfFieldLabel'));
  if (!isXmlText(signatureFieldName)) throw new Error('Missing PDF signature field.');

  const identities = children(outputs, dss, 'SignerIdentity');
  if (identities.length === 0) return { signatureFieldName };
  const [identity] = identities;
  if (identities.length !== 1 || identity.getAttribute('Format') !== signerIdentityFormat) {
    throw new Error('Unexpected signer identity format.');
  }
  const signerSubject = elementText(identity).trim();
  if (!signerSubject) throw new Error('Missing certificate subject.');
  return { signatureFieldName, signerSubject };
}

function requestBody(
  clientId: string,
  clientSecret: string,
  operation: SoapOperation,
  pdf: Uint8Array,
  optionalInputs: string,
): string {
  const profile = operation === 'ltv'
    ? 'urn:safelayer:tws:dss:1.0:profiles:nonrep:1.0'
    : 'urn:safelayer:tws:dss:1.0:profiles:pdf:1.0:verify';
  return `<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="${soap}" xmlns:wsse="${security}" xmlns:dss="${dss}" xmlns:css="${trustedX}">
  <soap:Header>
    <wsse:Security soap:actor="http://schemas.xmlsoap.org/soap/actor/next" soap:mustUnderstand="1">
      <wsse:UsernameToken>
        <wsse:Username>${escapeXml(clientId)}</wsse:Username>
        <wsse:Password Type="${passwordType}">${escapeXml(clientSecret)}</wsse:Password>
      </wsse:UsernameToken>
    </wsse:Security>
  </soap:Header>
  <soap:Body>
    <dss:VerifyRequest Profile="${profile}">
      <dss:OptionalInputs>${optionalInputs}</dss:OptionalInputs>
      <dss:InputDocuments>
        <dss:Document><dss:Base64Data MimeType="application/pdf">${Buffer.from(pdf).toString('base64')}</dss:Base64Data></dss:Document>
      </dss:InputDocuments>
    </dss:VerifyRequest>
  </soap:Body>
</soap:Envelope>`;
}

export function createUaePassSigningValidationClient(
  config: UaePassSigningValidationConfig,
): UaePassSigningValidationClient {
  const { environment, clientId, clientSecret } = config;
  assertEnvironment(environment);
  if (!isXmlText(clientId) || !isXmlText(clientSecret)) {
    throw new TypeError('Provide UAE PASS SOAP credentials.');
  }
  const gateway = new URL(gatewayPath, origins[environment]);

  async function request<T>(
    operation: SoapOperation,
    pdf: Uint8Array,
    optionalInputs: string,
    responseLimit: number,
    parse: (outputs: Element, status: number) => T,
  ): Promise<T> {
    if (!isPdf(pdf)) {
      throw new TypeError('Provide signed PDF bytes.');
    }
    if (pdf.byteLength > maxValidationPdfBytes) {
      throw new TypeError(`Provide signed PDF bytes up to ${maxValidationPdfBytes} bytes.`);
    }
    const body = requestBody(clientId, clientSecret, operation, pdf, optionalInputs);
    const { response, signal } = await send(gateway, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/xml; charset=utf-8',
        SOAPAction: operation === 'ltv' ? 'Update' : 'Verify',
        TwsAuthN: 'urn:safelayer:tws:policies:authentication:oauth:clients',
      },
      body,
    }, documentTransferTimeoutMs, (code) => new UaePassSigningValidationError(code, operation));
    const { status } = response;
    if (!response.ok) {
      discardBody(response);
      throw new UaePassSigningValidationError(classifyStatus(status, 'invalid_client'), operation, status);
    }
    try {
      const outputs = soapOutputs(await readXml(response, responseLimit), operation, status);
      return parse(outputs, status);
    } catch (error) {
      if (error instanceof UaePassSigningValidationError) throw error;
      throw new UaePassSigningValidationError(signal.aborted ? 'timeout' : 'invalid_response', operation, status);
    }
  }

  async function applyLongTermValidation(pdf: Uint8Array, signatureFieldName: string): Promise<Uint8Array> {
    if (!isXmlText(signatureFieldName)) throw new TypeError('Provide the PDF signature field name.');
    const inputs =
      '<dss:ReturnUpdatedSignature Type="urn:oasis:names:tc:dss:1.0:profiles:XAdES:forms:ES-A"/>' +
      `<css:PdfFieldLabel>${escapeXml(signatureFieldName)}</css:PdfFieldLabel>`;
    return request('ltv', pdf, inputs, maxLtvResponseBytes, updatedPdf);
  }

  async function verifySignedPdf(pdf: Uint8Array): Promise<UaePassVerifiedPdfSignature> {
    return request('verify', pdf, '<css:ReturnSignerIdentity binary="true"/>',
      maxVerificationBytes, verifiedSignature);
  }

  async function finalizeSignedPdf(
    pdf: Uint8Array,
    options: UaePassFinalizeSignedPdfOptions,
  ): Promise<UaePassFinalizedPdf> {
    if (typeof options?.matchSigner !== 'function') throw new TypeError('Provide a signer-matching callback.');
    const { expectedSignatureFieldName, matchSigner } = options;
    const finalizedPdf = await applyLongTermValidation(pdf, expectedSignatureFieldName);
    const signature = await verifySignedPdf(finalizedPdf);
    if (signature.signatureFieldName !== expectedSignatureFieldName) {
      throw new UaePassSigningValidationError('verification_failed', 'verify');
    }
    const { signerSubject } = signature;
    if (signerSubject === undefined) {
      throw new UaePassSigningValidationError('signer_unverified', 'match_signer');
    }
    let matches: boolean;
    try {
      matches = await matchSigner(signerSubject);
    } catch {
      throw new UaePassSigningValidationError('signer_match_failed', 'match_signer');
    }
    if (matches !== true) {
      throw new UaePassSigningValidationError('signer_unverified', 'match_signer');
    }
    return { pdf: finalizedPdf, signature: { ...signature, signerSubject } };
  }

  return { applyLongTermValidation, verifySignedPdf, finalizeSignedPdf };
}
