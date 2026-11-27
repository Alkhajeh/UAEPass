import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import {
  createUaePassClient,
  createUaePassSigningClient,
  createUaePassSigningValidationClient,
  UaePassBaseError,
  UaePassError,
  UaePassSigningError,
  UaePassSigningValidationError,
} from '@alkhajeh/uaepass-server';

const accessToken = 'fixture-shared-token';
const pdf = new Uint8Array(Buffer.from('%PDF-1.7\nshared fixture\n%%EOF\n'));
const authConfig = {
  environment: 'staging',
  clientId: 'fixture-client',
  clientSecret: 'fixture-secret',
  redirectUri: 'https://example.test/callback',
};
const signingConfig = {
  environment: 'staging',
  clientId: 'fixture-signing-client',
  clientSecret: 'fixture-secret',
  finishCallbackUrl: 'https://example.test/signing/finish',
};
const validationConfig = { environment: 'staging', clientId: 'fixture-client', clientSecret: 'fixture-secret' };
const createInput = { pdf, filename: 'document.pdf', signatureField: { name: 'Sign1' } };

// One call per operation.
const calls = {
  'auth token': () => createUaePassClient(authConfig).exchangeAuthorizationCode('code'),
  'auth userinfo': () => createUaePassClient(authConfig).getUserInfo(accessToken),
  'signing token': () => createUaePassSigningClient(signingConfig).getAccessToken(),
  'signing create': () => createUaePassSigningClient(signingConfig).createProcess(createInput, accessToken),
  'signing result': () => createUaePassSigningClient(signingConfig).getProcessResult('sp_1', accessToken),
  'validation verify': () => createUaePassSigningValidationClient(validationConfig).verifySignedPdf(pdf),
};

test('every client error shares the base class and keeps its serialized shape', () => {
  const errors = [
    [new UaePassError('timeout', 'token'), 'UaePassError'],
    [new UaePassSigningError('rejected', 'create', 400), 'UaePassSigningError'],
    [new UaePassSigningValidationError('rejected', 'ltv', 200), 'UaePassSigningValidationError'],
  ];
  for (const [error, name] of errors) {
    assert.ok(error instanceof UaePassBaseError);
    assert.ok(error instanceof Error);
    assert.equal(error.name, name);
    assert.ok('status' in error);
    assert.deepEqual(Object.keys(error), ['code', 'operation', 'status', 'name']);
  }
  assert.equal(JSON.stringify(errors[0][0]), '{"code":"timeout","operation":"token","name":"UaePassError"}');
  assert.equal(JSON.stringify(errors[1][0]),
    '{"code":"rejected","operation":"create","status":400,"name":"UaePassSigningError"}');
});

test('maps unexpected provider statuses consistently across clients', async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch');
  const allUnavailable = Object.fromEntries(Object.keys(calls).map((name) => [name, 'unavailable']));
  const expectations = [
    [302, {
      'auth token': 'invalid_response', 'auth userinfo': 'invalid_response', 'signing token': 'invalid_response',
      'signing result': 'invalid_response', 'validation verify': 'invalid_response',
    }],
    [401, {
      'auth token': 'invalid_client', 'auth userinfo': 'rejected', 'signing token': 'invalid_client',
      'signing result': 'invalid_token', 'validation verify': 'invalid_client',
    }],
    [429, allUnavailable],
    [503, allUnavailable],
    [200, { 'signing create': 'invalid_response' }],
  ];
  for (const [status, codes] of expectations) {
    fetch.mock.mockImplementation(async () =>
      new Response(null, { status, headers: status === 302 ? { Location: '/' } : {} }));
    for (const [name, code] of Object.entries(codes)) {
      await assert.rejects(calls[name](), (error) => {
        assert.ok(error instanceof UaePassBaseError, name);
        assert.equal(error.code, code, `${name} ${status}`);
        assert.equal(error.status, status, name);
        return true;
      });
    }
  }
});

test('reports a timeout that happens while reading the response body', async (t) => {
  const bodies = {
    'auth token': 'application/json',
    'signing token': 'application/json',
    'validation verify': 'text/xml',
  };
  const fetch = t.mock.method(globalThis, 'fetch');
  const timeout = t.mock.method(AbortSignal, 'timeout');
  for (const [name, contentType] of Object.entries(bodies)) {
    const controller = new AbortController();
    timeout.mock.mockImplementation(() => controller.signal);
    fetch.mock.mockImplementation(async () => new Response(new ReadableStream({
      pull(stream) {
        controller.abort();
        stream.error(new Error('aborted'));
      },
    }), { headers: { 'Content-Type': contentType } }));
    await assert.rejects(calls[name](), { code: 'timeout', status: 200 }, name);
  }
});

test('reads the global fetch when a request is sent', async (t) => {
  const client = createUaePassSigningClient(signingConfig);
  const fetch = t.mock.method(globalThis, 'fetch', async () => new Response(null, { status: 503 }));
  await assert.rejects(client.getAccessToken(), { code: 'unavailable' });
  assert.equal(fetch.mock.callCount(), 1);
});

test('validates the environment the same way for every client', () => {
  for (const [create, config] of [
    [createUaePassClient, authConfig],
    [createUaePassSigningClient, signingConfig],
    [createUaePassSigningValidationClient, validationConfig],
  ]) {
    assert.throws(() => create({ ...config, environment: 'custom' }),
      { name: 'TypeError', message: 'Choose a UAE PASS environment.' });
  }
});
