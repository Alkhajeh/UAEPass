import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  createUaePassClient, UaePassError, UaePassGender, UaePassProfileType, UaePassUserType,
} from '@alkhajeh/uaepass-server';

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

test('exchanges a code and fetches the profile using the documented wire format', async (t) => {
  const profile = { uuid: 'resident-id', sub: 'provider/sub', userType: 'SOP3' };
  const fetch = t.mock.method(globalThis, 'fetch', async (url, init) => {
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
  const accessToken = 'fixture+/_~.-=';
  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(url.origin, 'https://id.uaepass.ae');
    return Response.json({ ...token, access_token: accessToken, id_token: 'unused-id-token' });
  });
  const client = createUaePassClient({ ...config, environment: 'production' });
  assert.deepEqual(await client.exchangeAuthorizationCode(code), {
    accessToken,
    expiresInSeconds: 3600,
    scopes: ['profile', 'extra'],
  });
});

test('exchanges HTTP localhost redirects only in staging', async (t) => {
  const redirectUri = 'http://localhost:8000';
  const fetch = t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(url.origin, 'https://stg-id.uaepass.ae');
    assert.equal(url.pathname, '/idshub/token');
    assert.equal(url.searchParams.get('redirect_uri'), redirectUri);
    return Response.json(token);
  });
  const client = createUaePassClient({ ...config, redirectUri });
  await client.exchangeAuthorizationCode(code);
  assert.equal(fetch.mock.callCount(), 1);

  assert.throws(() => createUaePassClient({ ...config, environment: 'production', redirectUri }), TypeError);
  for (const invalid of ['http://service.example', 'http://localhost.example', 'http://127.0.0.1:8000']) {
    assert.throws(() => createUaePassClient({ ...config, redirectUri: invalid }), TypeError);
  }
});

test('rejects malformed bearer tokens at the exchange and User Info boundaries', async (t) => {
  const malformed = 'fixture\u0100token';
  const fetch = t.mock.method(globalThis, 'fetch', async () =>
    Response.json({ ...token, access_token: malformed }));
  const client = createUaePassClient(config);

  await assert.rejects(client.getUserInfoFromCode(code), {
    code: 'invalid_response',
    operation: 'token',
    status: 200,
  });
  await assert.rejects(client.getUserInfo(malformed), TypeError);
  assert.equal(fetch.mock.callCount(), 1);
});

test('exports known profile constants with provider values', () => {
  assert.deepEqual(UaePassUserType, { SOP1: 'SOP1', SOP2: 'SOP2', SOP3: 'SOP3' });
  assert.deepEqual(UaePassProfileType, { CitizenOrResident: '1', Visitor: '2' });
  assert.deepEqual(UaePassGender, { Male: 'Male', Female: 'Female' });
});

test('preserves unrecognized user type, profile type, and gender strings', async (t) => {
  const profile = { uuid: 'fixture-id', userType: 'SOP4', profileType: '3', gender: 'Unspecified' };
  t.mock.method(globalThis, 'fetch', async () => Response.json(profile));
  assert.deepEqual(await createUaePassClient(config).getUserInfo(token.access_token), profile);
});

test('preserves optional claims from basic, resident, visitor and subject-only profiles', async (t) => {
  const basic = { uuid: 'basic-id', userType: 'SOP1', firstnameEN: 'Fixture' };
  const resident = {
    uuid: 'resident-id',
    sub: 'provider/resident',
    userType: 'SOP3',
    firstnameEN: 'Fixture',
    firstnameAR: 'اسم',
    lastnameEN: 'Resident',
    lastnameAR: 'لقب',
    titleEN: 'Dr.',
    titleAR: 'د.',
    nationalityEN: 'ARE',
    nationalityAR: 'الإمارات',
    gender: 'Female',
    idType: 'ID',
    spuuid: 'smartpass-id',
    acr: 'high-assurance',
    amr: ['example-method'],
    customClaim: { approved: true },
  };
  const visitor = {
    uuid: 'visitor-id', sub: 'visitor-sub', userType: 'SOP3',
    profileType: '2', unifiedID: 'visitor-unified-id', email: null,
  };
  const subjectOnly = {
    sub: 'opaque-id', fullnameEN: 'Fixture User',
    unifiedId: 'other-unified-id', amr: null,
  };
  const profiles = [basic, resident, visitor, subjectOnly];
  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(url.origin, 'https://id.uaepass.ae');
    return Response.json(profiles.shift());
  });
  const client = createUaePassClient({ ...config, environment: 'production' });
  const { email: _email, ...expectedVisitor } = visitor;
  const { amr: _amr, ...expectedSubjectOnly } = subjectOnly;
  assert.deepEqual(await client.getUserInfo(token.access_token), basic);
  assert.deepEqual(await client.getUserInfo(token.access_token), resident);
  assert.deepEqual(await client.getUserInfo(token.access_token), expectedVisitor);
  assert.deepEqual(await client.getUserInfo(token.access_token), expectedSubjectOnly);
});

test('omits blank identity claims and requires a nonblank identifier', async (t) => {
  const profiles = [
    { uuid: '  ', sub: 'opaque/subject' },
    { uuid: 'opaque-uuid', sub: '' },
    { uuid: '', sub: '  ' },
  ];
  t.mock.method(globalThis, 'fetch', async () => Response.json(profiles.shift()));
  const client = createUaePassClient(config);

  assert.deepEqual(await client.getUserInfo(token.access_token), { sub: 'opaque/subject' });
  assert.deepEqual(await client.getUserInfo(token.access_token), { uuid: 'opaque-uuid' });
  await assert.rejects(client.getUserInfo(token.access_token), {
    code: 'invalid_response',
    operation: 'userinfo',
  });
});

test('reports safe provider failures and attempts the token exchange once', async (t) => {
  const cases = [
    [400, { error: 'invalid_grant', error_description: 'expiredCode' }, 'invalid_grant'],
    [400, { error: 'invalid_grant', error_description: 'redirectUriMismatch' }, 'redirect_mismatch'],
    [400, { error: 'Invalid_basic_header_authentication' }, 'invalid_client'],
    [400, { error_description: 'invalidHttpBasicAuthenticationToken' }, 'invalid_client'],
    [401, { error: 'invalid_client', debug: config.clientSecret }, 'invalid_client'],
    [503, 'Not JSON', 'unavailable'],
    [302, '', 'invalid_response'],
    [200, 'Not JSON', 'invalid_response'],
    [200, { ...token, expires_in: '3600' }, 'invalid_response'],
  ];
  let response;
  const fetch = t.mock.method(globalThis, 'fetch', async () => response);
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
  const fetch = t.mock.method(globalThis, 'fetch', async () => {
    throw new Error(`transport details can contain ${code}`);
  });
  await assert.rejects(createUaePassClient(config).exchangeAuthorizationCode(code), {
    code: 'timeout',
    operation: 'token',
    message: 'The UAE PASS request timed out.',
  });
  assert.equal(fetch.mock.callCount(), 1);
});

test('bounds token and profile responses and cancels oversized bodies', async (t) => {
  const limit = 256 * 1024;
  let canceled = 0;
  const advertised = new ReadableStream({ cancel() { canceled++; } });
  const streamed = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(limit));
      controller.enqueue(new Uint8Array(1));
    },
    cancel() { canceled++; },
  });
  const responses = [
    new Response(advertised, { headers: { 'Content-Length': String(limit + 1) } }),
    new Response(streamed),
  ];
  const fetch = t.mock.method(globalThis, 'fetch', async () => responses.shift());
  const client = createUaePassClient(config);
  await assert.rejects(client.exchangeAuthorizationCode(code), {
    code: 'invalid_response', operation: 'token', status: 200,
  });
  await assert.rejects(client.getUserInfo(token.access_token), {
    code: 'invalid_response', operation: 'userinfo', status: 200,
  });
  assert.equal(canceled, 2);
  assert.equal(fetch.mock.callCount(), 2);
});

test('rejects malformed profile data and invalid configuration', async (t) => {
  const profiles = [
    { email: 'fixture@example.test' },
    { sub: 'opaque-id', firstnameEN: 42 },
    { sub: 'opaque-id', amr: 'example-method' },
    { sub: 'opaque-id', amr: ['example-method', 42] },
  ];
  t.mock.method(globalThis, 'fetch', async () => Response.json(profiles.shift()));
  const client = createUaePassClient(config);
  for (let i = profiles.length; i > 0; i--) {
    await assert.rejects(client.getUserInfo(token.access_token), {
      code: 'invalid_response',
      operation: 'userinfo',
    });
  }
  assert.throws(() => createUaePassClient({ ...config, environment: 'custom' }), TypeError);
  for (const redirectUri of [
    'http://example.test',
    'https:///example.test/callback',
    'https://example.test\\callback',
    'https://example.test/callback\u0000',
  ]) {
    assert.throws(() => createUaePassClient({ ...config, redirectUri }), TypeError);
  }
});
