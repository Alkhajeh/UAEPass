import { Buffer } from 'node:buffer';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { cookieName, maxJsonBodyBytes, routes } from './config.mjs';

/** A 32-character base64url value with 192 bits of entropy. */
export const nonce = () => randomBytes(24).toString('base64url');

const nonceShape = /^[A-Za-z0-9_-]{32}$/;
const sessionCookie = new RegExp('(?:^|;\\s*)' + cookieName + '=([A-Za-z0-9_-]{32})(?:;|$)');

/** Returns a query value only when it appears exactly once and is not empty. */
export function singleQuery(url, name) {
  const values = url.searchParams.getAll(name);
  return values.length === 1 && values[0] ? values[0] : undefined;
}

export function matchingNonce(expected, incoming) {
  return typeof expected === 'string' && typeof incoming === 'string' &&
    nonceShape.test(incoming) &&
    timingSafeEqual(Buffer.from(expected), Buffer.from(incoming));
}

export function mediaType(request) {
  return request.headers['content-type']?.split(';')[0].trim().toLowerCase();
}

export function readSessionId(request) {
  return request.headers.cookie?.match(sessionCookie)?.[1];
}

export function setSessionCookie(response, id, lifetimeSeconds) {
  response.setHeader('Set-Cookie',
    cookieName + '=' + id + '; Path=' + routes.root + '; HttpOnly; SameSite=Lax; Max-Age=' + lifetimeSeconds);
}

/** Reads a bounded JSON body and returns its non-empty `code` string, or null. */
export async function readCode(request) {
  request.setEncoding('utf8');
  let body = '';
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    body += chunk;
    if (Buffer.byteLength(body) > maxJsonBodyBytes) {
      request.resume();
      return null;
    }
  }
  try {
    const input = JSON.parse(body);
    return typeof input?.code === 'string' && input.code.trim() ? input.code : null;
  } catch {
    return null;
  }
}

export function redirect(response, location) {
  response.writeHead(303, { Location: location }).end();
}

export function json(response, status, payload) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  }).end(JSON.stringify(payload));
}

export function pdfResponse(response, pdf, disposition, filename) {
  response.writeHead(200, {
    'Content-Type': 'application/pdf',
    'Content-Length': pdf.byteLength,
    'Content-Disposition': disposition + '; filename="' + filename + '"',
  }).end(pdf);
}

export function setPageSecurityHeaders(response) {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Content-Security-Policy',
    "default-src 'none'; style-src 'unsafe-inline'; frame-src 'self'; frame-ancestors 'self'; " +
    "form-action 'self' https://stg-id.uaepass.ae https://stg-ids.uaepass.ae https://stg.uaepass.ae; base-uri 'none'");
}
