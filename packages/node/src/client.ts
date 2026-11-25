import { Buffer } from 'node:buffer';

import { parseUserInfo, type UaePassUserInfo } from './user-info.js';

const origins = {
  staging: 'https://stg-id.uaepass.ae',
  production: 'https://id.uaepass.ae',
} as const;

export interface UaePassConfig {
  readonly environment: keyof typeof origins;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly redirectUri: string;
}

export interface UaePassToken {
  readonly accessToken: string;
  readonly expiresInSeconds: number;
  readonly scopes?: readonly string[];
}

export interface UaePassClient {
  exchangeAuthorizationCode(code: string): Promise<UaePassToken>;
  getUserInfo(accessToken: string): Promise<UaePassUserInfo>;
  getUserInfoFromCode(code: string): Promise<UaePassUserInfo>;
}

const errorMessages = {
  invalid_grant: 'UAE PASS rejected the authorization code.',
  redirect_mismatch: 'UAE PASS rejected the registered redirect URI.',
  invalid_client: 'UAE PASS rejected the server credentials.',
  rejected: 'UAE PASS rejected the request.',
  unavailable: 'UAE PASS is unavailable.',
  timeout: 'The UAE PASS request timed out.',
  invalid_response: 'UAE PASS returned an unexpected response.',
} as const;

export type UaePassErrorCode = keyof typeof errorMessages;
export type UaePassOperation = 'token' | 'userinfo';

export class UaePassError extends Error {
  constructor(
    readonly code: UaePassErrorCode,
    readonly operation: UaePassOperation,
    readonly status?: number,
  ) {
    super(errorMessages[code]);
    this.name = 'UaePassError';
  }
}

function isNonemptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isBearerToken(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9._~+/-]+=*$/.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function rejectionCode(
  operation: UaePassOperation,
  status: number,
  data: unknown,
): UaePassErrorCode {
  if (operation !== 'token') return 'rejected';
  const details = isRecord(data) ? data : undefined;
  const error = typeof details?.error === 'string' ? details.error.toLowerCase() : undefined;
  const description = details?.error_description;
  if (
    status === 401 ||
    error === 'invalid_client' ||
    error === 'invalid_basic_header_authentication' ||
    description === 'invalidHttpBasicAuthenticationToken'
  ) {
    return 'invalid_client';
  }
  if (error === 'invalid_grant') {
    return description === 'redirectUriMismatch'
      ? 'redirect_mismatch'
      : 'invalid_grant';
  }
  return 'rejected';
}

async function request(
  operation: UaePassOperation,
  url: URL,
  init: RequestInit,
): Promise<{ data: unknown; status: number }> {
  const signal = AbortSignal.timeout(5000);
  let response: Response;
  try {
    response = await fetch(url, { ...init, redirect: 'manual', signal });
  } catch {
    throw new UaePassError(signal.aborted ? 'timeout' : 'unavailable', operation);
  }

  const { status } = response;
  if ((status >= 300 && status < 400) || status === 429 || status >= 500) {
    void response.body?.cancel().catch(() => {});
    const code = status >= 400 ? 'unavailable' : 'invalid_response';
    throw new UaePassError(code, operation, status);
  }

  let data: unknown;
  try {
    data = await response.json();
  } catch {
    if (signal.aborted) throw new UaePassError('timeout', operation, status);
    if (response.ok) throw new UaePassError('invalid_response', operation, status);
  }
  if (!response.ok) {
    throw new UaePassError(rejectionCode(operation, status, data), operation, status);
  }
  return { data, status };
}

export function createUaePassClient(config: UaePassConfig): UaePassClient {
  const { environment, clientId, clientSecret, redirectUri } = config;
  if (environment !== 'staging' && environment !== 'production') {
    throw new TypeError('Choose a UAE PASS environment.');
  }
  if (!isNonemptyString(clientId) || clientId.includes(':') || !isNonemptyString(clientSecret)) {
    throw new TypeError('Provide valid UAE PASS client credentials.');
  }
  const redirect = typeof redirectUri === 'string' && URL.canParse(redirectUri)
    ? new URL(redirectUri)
    : null;
  const httpsRedirect = redirect?.protocol === 'https:' && redirectUri.startsWith('https://');
  const stagingLocalhost = environment === 'staging' &&
    redirect?.protocol === 'http:' && redirect.hostname === 'localhost' &&
    redirectUri.startsWith('http://');
  if (
    !redirect || (!httpsRedirect && !stagingLocalhost) || redirect.username || redirect.password ||
    redirectUri.includes('#') || /\s/.test(redirectUri)
  ) {
    throw new TypeError(environment === 'staging'
      ? 'Provide the registered HTTPS redirect URI or a staging HTTP localhost URI.'
      : 'Provide the registered HTTPS redirect URI.');
  }

  const origin = origins[environment];
  const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');

  async function exchangeAuthorizationCode(code: string): Promise<UaePassToken> {
    if (!isNonemptyString(code)) throw new TypeError('Provide an authorization code.');
    const url = new URL('/idshub/token', origin);
    url.search = new URLSearchParams({
      grant_type: 'authorization_code',
      redirect_uri: redirectUri,
      code,
    }).toString();
    const { data, status } = await request('token', url, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${credentials}`,
        'Content-Type': 'multipart/form-data; charset=UTF-8',
      },
    });
    if (
      !isRecord(data) || !isBearerToken(data.access_token) ||
      typeof data.token_type !== 'string' || data.token_type.toLowerCase() !== 'bearer' ||
      typeof data.expires_in !== 'number' || !Number.isSafeInteger(data.expires_in) ||
      data.expires_in <= 0 || (data.scope !== undefined && typeof data.scope !== 'string')
    ) {
      throw new UaePassError('invalid_response', 'token', status);
    }
    return {
      accessToken: data.access_token,
      expiresInSeconds: data.expires_in,
      ...(data.scope === undefined ? {} : { scopes: data.scope.split(/\s+/).filter(Boolean) }),
    };
  }

  async function getUserInfo(accessToken: string): Promise<UaePassUserInfo> {
    if (!isBearerToken(accessToken)) {
      throw new TypeError('Provide a valid UAE PASS access token.');
    }
    const { data, status } = await request('userinfo', new URL('/idshub/userinfo', origin), {
      method: 'GET',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const profile = isRecord(data) ? parseUserInfo(data) : undefined;
    if (!profile) {
      throw new UaePassError('invalid_response', 'userinfo', status);
    }
    return profile;
  }

  return {
    exchangeAuthorizationCode,
    getUserInfo,
    async getUserInfoFromCode(code: string): Promise<UaePassUserInfo> {
      const { accessToken } = await exchangeAuthorizationCode(code);
      return getUserInfo(accessToken);
    },
  };
}
