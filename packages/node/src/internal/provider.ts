import { Buffer } from 'node:buffer';

import type { UaePassEnvironment } from '../types.js';

const pdfHeader = Buffer.from('%PDF-');
const maxJsonBytes = 256 * 1024;
const utf8 = new TextDecoder('utf-8', { fatal: true });

export const tokenTimeoutMs = 5_000;
export const apiTimeoutMs = 15_000;
export const documentTransferTimeoutMs = 60_000;

export const origins: Readonly<Record<UaePassEnvironment, string>> = {
  staging: 'https://stg-id.uaepass.ae',
  production: 'https://id.uaepass.ae',
};

export function assertEnvironment(value: unknown): asserts value is UaePassEnvironment {
  if (value !== 'staging' && value !== 'production') {
    throw new TypeError('Choose a UAE PASS environment.');
  }
}

export type TransportFailure = 'timeout' | 'unavailable';

/**
 * Sends a provider request that never follows redirects and aborts after `timeoutMs`.
 * Returns the timeout signal so callers can tell a timed-out body read from a malformed one.
 */
export async function send(
  url: URL,
  init: RequestInit,
  timeoutMs: number,
  toError: (code: TransportFailure) => Error,
): Promise<{ response: Response; signal: AbortSignal }> {
  const signal = AbortSignal.timeout(timeoutMs);
  try {
    const response = await fetch(url, { ...init, redirect: 'manual', signal });
    return { response, signal };
  } catch {
    throw toError(signal.aborted ? 'timeout' : 'unavailable');
  }
}

/** Maps an unexpected HTTP status to an error code. */
export function classifyStatus<Unauthorized extends string>(
  status: number,
  unauthorized: Unauthorized,
): Unauthorized | 'unavailable' | 'rejected' | 'invalid_response' {
  if (status === 429 || status >= 500) return 'unavailable';
  if (status === 401) return unauthorized;
  if (status >= 400) return 'rejected';
  return 'invalid_response';
}

export function discardBody(response: Response): void {
  void response.body?.cancel().catch(() => {});
}

/** Returns the lowercase media type of the response without parameters. */
export function mediaType(response: Response): string | undefined {
  return response.headers.get('content-type')?.split(';')[0]?.trim().toLowerCase();
}

export function decodeUtf8(bytes: Uint8Array): string {
  return utf8.decode(bytes);
}

export function isNonemptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export function isBearerToken(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9._~+/-]+=*$/.test(value);
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function isBearerTokenResponse(data: unknown): data is {
  access_token: string;
  expires_in: number;
  scope?: unknown;
} {
  return isRecord(data) && isBearerToken(data.access_token) &&
    typeof data.token_type === 'string' && data.token_type.toLowerCase() === 'bearer' &&
    typeof data.expires_in === 'number' && Number.isSafeInteger(data.expires_in) && data.expires_in > 0;
}

export function parseProviderUrl(value: unknown): URL | undefined {
  if (typeof value !== 'string' || /[\s\\#\u0000-\u001f\u007f]/.test(value) || !URL.canParse(value)) return undefined;
  const url = new URL(value);
  return url.username || url.password ? undefined : url;
}

export function parseCallbackUrl(value: unknown, environment: UaePassEnvironment): URL | undefined {
  if (typeof value !== 'string' || !/^https?:\/\/[^/]/.test(value)) return undefined;
  const url = parseProviderUrl(value);
  if (url && (url.protocol === 'https:' || (environment === 'staging' && url.hostname === 'localhost'))) {
    return url;
  }
  return undefined;
}

export function isPdf(value: unknown): value is Uint8Array {
  return value instanceof Uint8Array && pdfHeader.every((byte, index) => value[index] === byte);
}

export function isXmlText(value: unknown): value is string {
  return typeof value === 'string' && value.trim() !== '' &&
    !/[^\t\n\r\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/u.test(value);
}

export async function readBoundedBytes(response: Response, limit: number): Promise<Uint8Array> {
  if (Number(response.headers.get('content-length')) > limit) {
    discardBody(response);
    throw new RangeError('The UAE PASS response is too large.');
  }
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        void reader.cancel().catch(() => {});
        throw new RangeError('The UAE PASS response is too large.');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export async function readProviderJson(response: Response): Promise<unknown> {
  const bytes = await readBoundedBytes(response, maxJsonBytes);
  return JSON.parse(decodeUtf8(bytes));
}
