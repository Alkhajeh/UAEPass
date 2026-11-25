import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createUaePassClient, UaePassError } from '../dist/index.js';

const config = {
  environment: 'staging',
  clientId: 'fixture-client',
  clientSecret: 'fixture-secret',
  redirectUri: 'https://EXAMPLE.test:443/callback?app=demo%20app',
};
const token = {
  access_token: 'opaque-fixture-token',
  token_type: 'Bearer',
  expires_in: 3600,
  scope: 'profile   extra',
};
const code = 'code+opaque/fixture';

function mockFetch(t, implementation) {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'fetch');
  const mock = t.mock.fn(implementation);
  Object.defineProperty(globalThis, 'fetch', { configurable: true, writable: true, value: mock });
  t.after(() => Object.defineProperty(globalThis, 'fetch', original));
  return mock;
}

test('exchanges a code and fetches the profile using the documented wire format', async (t) => {
  const profile = { uuid: 'resident-id', sub: 'provider/sub', userType: 'SOP3' };
  const fetch = mockFetch(t, async (url, init) => {
    assert.equal(init.redirect, 'manual');
    assert.equal(url.origin, 'https://stg-id.uaepass.ae');
    if (init.method === 'POST') {
      assert.equal(url.pathname, '/idshub/token');
      assert.deepEqual(Object.fromEntries(url.searchParams), {
        grant_type: 'authorization_code',
        code,
        redirect_uri: config.redirectUri,
      });
      assert.equal(init.headers.Authorization, 'Basic Zml4dHVyZS1jbGllbnQ6Zml4dHVyZS1zZWNyZXQ=');
      assert.equal(init.headers['Content-Type'], 'multipart/form-data; charset=UTF-8');
      return Response.json(token);
    }
    assert.equal(init.method, 'GET');
    assert.equal(url.pathname, '/idshub/userinfo');
    assert.equal(url.search, '');
    assert.equal(init.headers.Authorization, 'Bearer opaque-fixture-token');
    return Response.json(profile);
  });

  assert.deepEqual(await createUaePassClient(config).getUserInfoFromCode(code), profile);
  assert.deepEqual(fetch.mock.calls.map(({ arguments: [url] }) => url.pathname), [
    '/idshub/token', '/idshub/userinfo',
  ]);
});

test('returns an opaque token, expiry in seconds and granted scopes', async (t) => {
  mockFetch(t, async (url) => {
    assert.equal(url.origin, 'https://id.uaepass.ae');
    return Response.json({ ...token, id_token: 'unused-id-token' });
  });
  const client = createUaePassClient({ ...config, environment: 'production' });
  assert.deepEqual(await client.exchangeAuthorizationCode(code), {
    accessToken: token.access_token,
    expiresInSeconds: 3600,
    scopes: ['profile', 'extra'],
  });
});

test('supports visitor and subject-only profiles with scope-dependent attributes', async (t) => {
  const visitor = {
    uuid: 'visitor-id', sub: 'visitor-sub', userType: 'SOP3',
    profileType: '2', unifiedID: 'approved-id', email: null, amr: ['example'],
  };
  const subjectOnly = { sub: 'opaque-id', fullnameEN: 'Fixture User' };
  const profiles = [visitor, subjectOnly];
  mockFetch(t, async (url) => {
    assert.equal(url.origin, 'https://id.uaepass.ae');
    return Response.json(profiles.shift());
  });
  const client = createUaePassClient({ ...config, environment: 'production' });
  const { email: _email, ...expectedVisitor } = visitor;
  assert.deepEqual(await client.getUserInfo(token.access_token), expectedVisitor);
  assert.deepEqual(await client.getUserInfo(token.access_token), subjectOnly);
});

test('reports safe provider failures and attempts the token exchange once', async (t) => {
  const cases = [
    [400, { error: 'invalid_grant', error_description: 'expiredCode' }, 'invalid_grant'],
    [400, { error: 'invalid_grant', error_description: 'redirectUriMismatch' }, 'redirect_mismatch'],
    [401, { error: 'invalid_client', debug: config.clientSecret }, 'invalid_client'],
    [503, 'Not JSON', 'unavailable'],
    [302, '', 'invalid_response'],
    [200, 'Not JSON', 'invalid_response'],
    [200, { ...token, expires_in: '3600' }, 'invalid_response'],
  ];
  let response;
  const fetch = mockFetch(t, async () => response);
  for (const [status, body, expectedCode] of cases) {
    response = typeof body === 'string'
      ? new Response(body, { status })
      : Response.json(body, { status });
    const previousCalls = fetch.mock.callCount();
    await assert.rejects(createUaePassClient(config).getUserInfoFromCode(code), (error) => {
      assert.ok(error instanceof UaePassError);
      assert.equal(error.code, expectedCode);
      assert.equal(error.operation, 'token');
      assert.equal(error.status, status);
      assert.equal(error.cause, undefined);
      const text = error.stack + JSON.stringify(error);
      for (const value of [config.clientSecret, config.redirectUri, token.access_token, code]) {
        assert.equal(text.includes(value), false);
      }
      return true;
    });
    assert.equal(fetch.mock.callCount(), previousCalls + 1);
  }
});

test('reports timeout without retrying or exposing transport errors', async (t) => {
  const signal = AbortSignal.abort(new DOMException('fixture timeout', 'TimeoutError'));
  t.mock.method(AbortSignal, 'timeout', () => signal);
  const fetch = mockFetch(t, async () => {
    throw new Error(`transport details can contain ${code}`);
  });
  await assert.rejects(createUaePassClient(config).exchangeAuthorizationCode(code), {
    code: 'timeout',
    operation: 'token',
    message: 'The UAE PASS request timed out.',
  });
  assert.equal(fetch.mock.callCount(), 1);
});

test('rejects malformed profile data and invalid configuration', async (t) => {
  mockFetch(t, async () => Response.json({ email: 'fixture@example.test' }));
  await assert.rejects(createUaePassClient(config).getUserInfo(token.access_token), {
    code: 'invalid_response',
    operation: 'userinfo',
  });
  assert.throws(() => createUaePassClient({ ...config, environment: 'custom' }), TypeError);
  assert.throws(() => createUaePassClient({ ...config, redirectUri: 'http://example.test' }), TypeError);
});
