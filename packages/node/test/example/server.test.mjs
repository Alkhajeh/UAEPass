import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { once } from 'node:events';
import { request } from 'node:http';
import { test } from 'node:test';
import { UaePassError, UaePassSigningValidationError } from '@alkhajeh/uaepass-server';
import { createExampleServer } from '../../example/server.mjs';

const origin = 'http://localhost:8787';
const approvalUrl = 'https://stg-id.uaepass.ae/trustedx-resources/esignsp/v2/ui?signerProcessId=fixture-process';
const profile = { uuid: 'fixture-uuid', userType: 'SOP3', idn: '784-1900-0000000-0' };
const unverifiedPdf = Buffer.from('%PDF-1.7\nunverified fixture');
const verifiedPdf = Buffer.from('%PDF-1.7\nverified fixture');
const signerSubject = 'CN=Fixture Signer,serialNumber=' + profile.idn.replaceAll('-', '') + ',C=AE';
const finalized = { pdf: verifiedPdf, signature: { signatureFieldName: 'Sign1', signerSubject } };

async function listen(t, overrides = {}) {
  const authClient = {
    getUserInfoFromCode: t.mock.fn(async () => profile),
    ...overrides.authClient,
  };
  const exchangeClient = {
    getUserInfoFromCode: t.mock.fn(async () => profile),
    ...overrides.exchangeClient,
  };
  const signingClient = {
    getAccessToken: t.mock.fn(async () => ({ accessToken: 'fixture-token', expiresInSeconds: 600 })),
    createProcess: t.mock.fn(async () => ({
      processId: 'fixture-process', documentId: 'fixture-pdf', approvalUrl,
    })),
    getProcessResult: t.mock.fn(async () => ({ status: 'finished' })),
    downloadSignedPdf: t.mock.fn(async () => unverifiedPdf),
    deleteProcess: t.mock.fn(async () => {}),
    ...overrides.signingClient,
  };
  const finalizeSignedPdf = t.mock.fn(overrides.finalizeSignedPdf ?? (async (_pdf, { matchSigner }) => {
    if (!await matchSigner(signerSubject)) {
      throw new UaePassSigningValidationError('signer_unverified', 'match_signer');
    }
    return finalized;
  }));
  const server = await createExampleServer({
    authClient, exchangeClient, signingClient, validationClient: { finalizeSignedPdf },
    clientId: 'fixture-client', origin,
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    const closed = once(server, 'close');
    server.close();
    await closed;
  });

  function send(path, { method = 'GET', cookie, headers = {} } = {}) {
    return new Promise((resolve, reject) => {
      const outgoing = request(`http://127.0.0.1:${server.address().port}${path}`, {
        method,
        signal: AbortSignal.timeout(2000),
        headers: {
          Host: new URL(origin).host,
          ...(method === 'POST' ? { Origin: origin } : {}),
          ...(cookie ? { Cookie: cookie } : {}),
          ...headers,
        },
      }, async (incoming) => {
        try {
          const chunks = [];
          for await (const chunk of incoming) chunks.push(chunk);
          resolve({ status: incoming.statusCode, headers: incoming.headers, body: Buffer.concat(chunks) });
        } catch (error) {
          reject(error);
        }
      });
      outgoing.on('error', reject);
      outgoing.end();
    });
  }

  const exchangeUrl = `http://127.0.0.1:${server.address().port}/auth/uaepass`;
  return { send, exchangeUrl, authClient, signingClient, finalizeSignedPdf };
}

function post(endpoint, body, headers) {
  return fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

test('one listener serves browser signing and exchanges codes with only a success flag', { timeout: 5000 }, async (t) => {
  const getUserInfoFromCode = t.mock.fn(async (code) => {
    if (code === 'fixture-timeout') throw new UaePassError('timeout', 'token');
    return { uuid: 'fixture-profile-id' };
  });
  const { exchangeUrl: endpoint, send } = await listen(t, { exchangeClient: { getUserInfoFromCode } });
  const signingPage = await send('/signing');
  assert.equal(signingPage.status, 200);

  const success = await post(endpoint, { code: 'fixture-code' });
  assert.equal(success.status, 200);
  assert.equal(success.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await success.json(), { ok: true });

  const missingCode = await post(endpoint, {});
  assert.equal(missingCode.status, 400);
  assert.deepEqual(await missingCode.json(), { ok: false });

  const timeout = await post(endpoint, { code: 'fixture-timeout' });
  assert.equal(timeout.status, 504);
  assert.deepEqual(await timeout.json(), { ok: false });

  const web = await post(endpoint, { code: 'fixture-web-code' }, {
    Origin: 'https://example.test',
  });
  assert.equal(web.status, 200);
  assert.equal(web.headers.has('access-control-allow-origin'), false);
  assert.deepEqual(await web.json(), { ok: true });
  assert.deepEqual(getUserInfoFromCode.mock.calls.map(({ arguments: args }) => args), [
    ['fixture-code'],
    ['fixture-timeout'],
    ['fixture-web-code'],
  ]);
});

test('the local endpoint rejects a non-loopback Host', { timeout: 5000 }, async (t) => {
  const getUserInfoFromCode = t.mock.fn(async () => ({ uuid: 'fixture-profile-id' }));
  const { exchangeUrl: endpoint } = await listen(t, { exchangeClient: { getUserInfoFromCode } });

  const wrongHost = request(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Host: 'example.test',
    },
  });
  const response = once(wrongHost, 'response');
  wrongHost.end(JSON.stringify({ code: 'fixture-rejected-code' }));
  const [rejectedHost] = await response;
  assert.equal(rejectedHost.statusCode, 403);
  rejectedHost.resume();
  assert.equal(getUserInfoFromCode.mock.callCount(), 0);
});

function sessionCookie(response) {
  const values = response.headers['set-cookie'];
  assert.ok(values?.length);
  const session = values.find((value) => /^[^=;]+=[^;]+;/.test(value) && !/Max-Age=0\b/i.test(value));
  assert.ok(session);
  assert.match(session, /\bHttpOnly\b/i);
  assert.match(session, /\bSameSite=Lax\b/i);
  return session.split(';')[0];
}

function callbackUrl(state, code) {
  const query = new URLSearchParams({ state, code });
  return `/signing/auth/callback?${query}`;
}

async function beginLogin(send) {
  const login = await send('/signing/login', { method: 'POST' });
  const authorize = new URL(login.headers.location);
  assert.equal(authorize.origin, 'https://stg-id.uaepass.ae');
  assert.equal(authorize.searchParams.get('redirect_uri'), `${origin}/signing/auth/callback`);
  const state = authorize.searchParams.get('state');
  assert.ok(state);
  return { state, cookie: sessionCookie(login) };
}

async function signIn(send, code = 'fixture-code') {
  const { state, cookie } = await beginLogin(send);
  const callback = await send(callbackUrl(state, code), { cookie });
  assert.equal(callback.headers.location, '/signing');
  const authenticatedCookie = sessionCookie(callback);
  assert.notEqual(authenticatedCookie, cookie);
  return { authenticatedCookie, callback, state, cookie };
}

function start(send, cookie) {
  return send('/signing/start', { method: 'POST', cookie });
}

function finish(send, cookie, processId = 'fixture-process', status = 'finished') {
  const params = new URLSearchParams({ signer_process_id: processId, status });
  return send(`/signing/finish?${params}`, { cookie });
}

function download(send, cookie) {
  return send('/signing/download.pdf', { cookie });
}

test('the signing demo validates OAuth state, exchanges once, and rejects foreign browser origins', { timeout: 5000 }, async (t) => {
  const { send, authClient, signingClient } = await listen(t);
  const home = await send('/signing');
  assert.equal(home.headers['referrer-policy'], 'same-origin');
  const foreignHost = await send('/signing', { headers: { Host: 'foreign.test' } });
  assert.equal(foreignHost.status, 403);
  const foreignOrigin = await send('/signing/login', {
    method: 'POST', headers: { Origin: 'https://foreign.test' },
  });
  assert.equal(foreignOrigin.status, 403);

  const attemptedLogin = await beginLogin(send);
  await send(callbackUrl('wrong-state', 'unused-code'), { cookie: attemptedLogin.cookie });
  await send(callbackUrl(attemptedLogin.state, 'unused-code'));
  assert.equal(authClient.getUserInfoFromCode.mock.callCount(), 0);

  const { authenticatedCookie, callback, state, cookie } = await signIn(send);
  assert.equal(callback.headers['cache-control'], 'no-store');
  assert.equal(callback.headers['referrer-policy'], 'no-referrer');
  await send(callbackUrl(state, 'fixture-code'), { cookie });
  assert.deepEqual(authClient.getUserInfoFromCode.mock.calls.map(({ arguments: args }) => args), [['fixture-code']]);

  const unauthorizedStart = await send('/signing/start', {
    method: 'POST', cookie: authenticatedCookie, headers: { Origin: 'https://foreign.test' },
  });
  assert.equal(unauthorizedStart.status, 403);
  assert.equal(signingClient.createProcess.mock.callCount(), 0);
});

test('the signing demo distinguishes documented OAuth cancellations from other callback failures', { timeout: 5000 }, async (t) => {
  const { send, authClient } = await listen(t);
  for (const [fields, notice] of [
    [['error=cancelledOnApp'], 'canceled'],
    [['error=access_denied'], 'canceled'],
    [['error=server_error', 'error_description=sensitive-provider-detail'], 'error'],
    [['error=access_denied', 'code=unexpected-code'], 'error'],
    [[], 'error'],
  ]) {
    const { state, cookie } = await beginLogin(send);
    const returned = await send('/signing/auth/callback?' + ['state=' + state, ...fields].join('&'), { cookie });
    assert.equal(returned.headers.location, '/signing?notice=' + notice);
  }
  assert.equal(authClient.getUserInfoFromCode.mock.callCount(), 0);
});

test('the signing demo confirms the provider result and publishes only the finalized PDF', { timeout: 5000 }, async (t) => {
  const otherProfile = { ...profile, uuid: 'fixture-other-uuid', idn: '784-1900-0000000-1' };
  const { send, signingClient, finalizeSignedPdf } = await listen(t, {
    authClient: { getUserInfoFromCode: async (code) => code === 'fixture-other-code' ? otherProfile : profile },
  });
  const { authenticatedCookie: owner } = await signIn(send);
  const { authenticatedCookie: other } = await signIn(send, 'fixture-other-code');
  assert.notEqual(owner, other);

  const review = await send('/signing/review.pdf', { cookie: owner });
  assert.equal(review.status, 200);
  assert.match(review.headers['content-type'], /^application\/pdf\b/);
  assert.notEqual((await download(send, owner)).status, 200);

  const started = await start(send, owner);
  assert.equal(started.headers.location, approvalUrl);
  const [[input, token]] = signingClient.createProcess.mock.calls.map(({ arguments: args }) => args);
  assert.deepEqual(Buffer.from(input.pdf), review.body);
  assert.equal(token, 'fixture-token');

  await finish(send, other);
  await finish(send, owner, 'wrong-process');
  assert.equal(signingClient.getProcessResult.mock.callCount(), 0);

  const returned = await finish(send, owner, 'fixture-process', 'canceled');
  assert.equal(returned.headers.location, '/signing');
  assert.deepEqual(signingClient.getProcessResult.mock.calls[0].arguments, ['fixture-process', 'fixture-token']);
  assert.deepEqual(signingClient.downloadSignedPdf.mock.calls[0].arguments, ['fixture-pdf', 'fixture-token']);
  const [signedPdf, options] = finalizeSignedPdf.mock.calls[0].arguments;
  assert.deepEqual(signedPdf, unverifiedPdf);
  assert.equal(options.expectedSignatureFieldName, input.signatureField.name);
  assert.equal(options.matchSigner(signerSubject), true);
  assert.equal(options.matchSigner(signerSubject.replace(profile.idn.replaceAll('-', ''),
    otherProfile.idn.replaceAll('-', ''))), false);

  await finish(send, owner);
  assert.equal(signingClient.getProcessResult.mock.callCount(), 1);
  assert.equal(finalizeSignedPdf.mock.callCount(), 1);
  assert.equal(signingClient.deleteProcess.mock.callCount(), 1);
  const signed = await download(send, owner);
  assert.equal(signed.status, 200);
  assert.match(signed.headers['content-type'], /^application\/pdf\b/);
  assert.match(signed.headers['content-disposition'], /^attachment\b/);
  assert.deepEqual(signed.body, verifiedPdf);
  assert.notEqual((await download(send, other)).status, 200);
});

test('the signing demo blocks an ineligible signer and honors a provider cancellation', { timeout: 5000 }, async (t) => {
  const getUserInfoFromCode = t.mock.fn(async (code) => (
    code === 'fixture-ineligible' ? { ...profile, userType: 'SOP1' } : profile
  ));
  const getProcessResult = t.mock.fn(async () => ({ status: 'canceled' }));
  const { send, signingClient, finalizeSignedPdf } = await listen(t, {
    authClient: { getUserInfoFromCode }, signingClient: { getProcessResult },
  });
  const { authenticatedCookie: ineligible } = await signIn(send, 'fixture-ineligible');
  await start(send, ineligible);
  assert.equal(signingClient.getAccessToken.mock.callCount(), 0);
  assert.equal(signingClient.createProcess.mock.callCount(), 0);

  const { authenticatedCookie: owner } = await signIn(send);
  await start(send, owner);
  await finish(send, owner);
  assert.equal(getProcessResult.mock.callCount(), 1);
  assert.equal(signingClient.downloadSignedPdf.mock.callCount(), 0);
  assert.equal(finalizeSignedPdf.mock.callCount(), 0);
  assert.notEqual((await download(send, owner)).status, 200);
  const landing = await send('/signing', { cookie: owner });
  assert.match(landing.body.toString('utf8'), /cancel(?:l)?ed/i);
});

test('the signing demo retries interrupted finalization and cleanup', { timeout: 5000 }, async (t) => {
  let finalizationAttempts = 0;
  let cleanupAttempts = 0;
  const deleteProcess = t.mock.fn(async () => {
    cleanupAttempts += 1;
    if (cleanupAttempts === 1) throw new Error('fixture-cleanup-detail');
  });
  const { send, signingClient, finalizeSignedPdf } = await listen(t, {
    signingClient: { deleteProcess },
    finalizeSignedPdf: async () => {
      finalizationAttempts += 1;
      if (finalizationAttempts === 1) throw new UaePassSigningValidationError('timeout', 'verify');
      return finalized;
    },
  });
  const { authenticatedCookie: owner } = await signIn(send);
  await start(send, owner);
  await finish(send, owner);
  assert.equal(finalizeSignedPdf.mock.callCount(), 1);
  assert.equal(signingClient.deleteProcess.mock.callCount(), 0);
  assert.notEqual((await download(send, owner)).status, 200);
  const beforeRetry = await send('/signing', { cookie: owner });
  assert.doesNotMatch(beforeRetry.body.toString('utf8'), /fixture-(?:token|uuid)|timed out/);

  await send('/signing/check', { method: 'POST', cookie: owner });
  assert.equal(signingClient.deleteProcess.mock.callCount(), 1);
  assert.deepEqual((await download(send, owner)).body, verifiedPdf);
  await send('/signing/check', { method: 'POST', cookie: owner });
  assert.equal(finalizeSignedPdf.mock.callCount(), 2);
  assert.equal(signingClient.createProcess.mock.callCount(), 1);
  assert.equal(signingClient.deleteProcess.mock.callCount(), 2);
  assert.deepEqual((await download(send, owner)).body, verifiedPdf);
});

test('the signing demo blocks downloads and cleanup after definitive finalization failures', { timeout: 5000 }, async (t) => {
  for (const [code, operation, message] of [
    ['signer_unverified', 'match_signer', /could not be matched to the signed-in account/],
    ['verification_failed', 'verify', /did not pass signature verification/],
  ]) {
    await t.test(code, async (subtest) => {
      const { send, signingClient, finalizeSignedPdf } = await listen(subtest, {
        finalizeSignedPdf: async () => { throw new UaePassSigningValidationError(code, operation); },
      });
      const { authenticatedCookie: owner } = await signIn(send);
      await start(send, owner);
      await finish(send, owner);

      const page = await send('/signing', { cookie: owner });
      assert.match(page.body.toString('utf8'), message);
      await finish(send, owner);
      await send('/signing/check', { method: 'POST', cookie: owner });
      assert.equal(signingClient.downloadSignedPdf.mock.callCount(), 1);
      assert.equal(finalizeSignedPdf.mock.callCount(), 1);
      assert.equal((await download(send, owner)).status, 404);
      assert.equal(signingClient.deleteProcess.mock.callCount(), 0);
      const restart = await send('/signing/login', { method: 'POST', cookie: owner });
      assert.equal(new URL(restart.headers.location).pathname, '/idshub/authorize');
    });
  }
});

test('the signing demo makes a final cleanup attempt when the browser session expires', { timeout: 5000 }, async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.now() });
  const retried = Promise.withResolvers();
  let attempts = 0;
  const deleteProcess = t.mock.fn(async () => {
    attempts++;
    if (attempts === 1) throw new Error('fixture cleanup failure');
    retried.resolve();
  });
  const { send } = await listen(t, { signingClient: { deleteProcess } });
  const { authenticatedCookie: owner } = await signIn(send);
  await start(send, owner);
  await finish(send, owner);
  assert.equal(deleteProcess.mock.callCount(), 1);

  t.mock.timers.tick(60 * 60 * 1000);
  assert.equal((await download(send, owner)).status, 404);
  await retried.promise;
  assert.equal((await download(send, owner)).status, 404);
  assert.equal(deleteProcess.mock.callCount(), 2);
});

test('the signing demo coalesces overlapping result checks for the same process', { timeout: 5000 }, async (t) => {
  const finalizing = Promise.withResolvers();
  const release = Promise.withResolvers();
  const { send, signingClient, finalizeSignedPdf } = await listen(t, {
    finalizeSignedPdf: async () => {
      finalizing.resolve();
      await release.promise;
      return finalized;
    },
  });
  const { authenticatedCookie: owner } = await signIn(send);
  await start(send, owner);

  const first = finish(send, owner);
  let second;
  try {
    await Promise.race([
      finalizing.promise,
      first.then(() => assert.fail('the finish callback returned before starting finalization')),
    ]);
    assert.notEqual((await download(send, owner)).status, 200);
    second = send('/signing/check', { method: 'POST', cookie: owner });
  } finally {
    release.resolve();
    await Promise.all([first, second]);
  }
  assert.equal(signingClient.getProcessResult.mock.callCount(), 1);
  assert.equal(finalizeSignedPdf.mock.callCount(), 1);
  assert.equal(signingClient.deleteProcess.mock.callCount(), 1);
  assert.deepEqual((await download(send, owner)).body, verifiedPdf);
});

test('the signing demo renews a rejected token during result lookup', { timeout: 5000 }, async (t) => {
  let issued = 0;
  const getAccessToken = t.mock.fn(async () => ({ accessToken: 'fixture-token-' + ++issued, expiresInSeconds: 600 }));
  const getProcessResult = t.mock.fn(async (_processId, token) => {
    if (token === 'fixture-token-1') throw Object.assign(new Error('Rejected token'), { code: 'invalid_token' });
    return { status: 'finished' };
  });
  const { send, signingClient } = await listen(t, { signingClient: { getAccessToken, getProcessResult } });
  const { authenticatedCookie } = await signIn(send);

  await start(send, authenticatedCookie);
  await finish(send, authenticatedCookie);
  assert.equal(getAccessToken.mock.callCount(), 2);
  assert.deepEqual(getProcessResult.mock.calls.map(({ arguments: args }) => args[1]),
    ['fixture-token-1', 'fixture-token-2']);
  assert.deepEqual(signingClient.deleteProcess.mock.calls[0].arguments, ['fixture-process', 'fixture-token-2']);
  assert.deepEqual((await download(send, authenticatedCookie)).body, verifiedPdf);
});

test('the signing demo keeps a pending request recoverable when staging has no result yet', { timeout: 5000 }, async (t) => {
  let finished = false;
  const getProcessResult = t.mock.fn(async () => {
    if (!finished) throw Object.assign(new Error('No result yet'), { code: 'rejected', status: 404 });
    return { status: 'finished' };
  });
  const { send, signingClient } = await listen(t, { signingClient: { getProcessResult } });
  const { authenticatedCookie } = await signIn(send);

  await start(send, authenticatedCookie);
  await send('/signing/check', { method: 'POST', cookie: authenticatedCookie });
  const page = await send('/signing', { cookie: authenticatedCookie });
  assert.match(page.body.toString('utf8'), /Check again after approval/);
  assert.notEqual((await download(send, authenticatedCookie)).status, 200);

  finished = true;
  await finish(send, authenticatedCookie);
  assert.equal(getProcessResult.mock.callCount(), 2);
  assert.equal(signingClient.createProcess.mock.callCount(), 1);
  assert.deepEqual((await download(send, authenticatedCookie)).body, verifiedPdf);
});

test('the signing demo retains an ambiguous creation attempt for reconciliation', { timeout: 5000 }, async (t) => {
  const createProcess = t.mock.fn(async () => {
    throw Object.assign(new Error('fixture-provider-detail'), { code: 'timeout' });
  });
  const { send } = await listen(t, { signingClient: { createProcess } });
  const { authenticatedCookie } = await signIn(send);

  await start(send, authenticatedCookie);
  await start(send, authenticatedCookie);
  await send('/signing/login', { method: 'POST', cookie: authenticatedCookie });
  const page = await send('/signing', { cookie: authenticatedCookie });
  assert.equal(createProcess.mock.callCount(), 1);
  const body = page.body.toString('utf8');
  assert.match(body, /Reconcile it with UAE PASS/);
  assert.doesNotMatch(body, /fixture-provider-detail/);
});
