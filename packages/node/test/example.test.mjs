import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import { test } from 'node:test';
import { UaePassError } from '@alkhajeh/uaepass-server';
import { createExampleServer } from '../example/server.mjs';

async function listen(t, getUserInfoFromCode) {
  const server = createExampleServer({ getUserInfoFromCode });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    const closed = once(server, 'close');
    server.close();
    await closed;
  });
  return `http://127.0.0.1:${server.address().port}/auth/uaepass`;
}

function post(endpoint, body, headers) {
  return fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

test('the local endpoint exchanges a code and returns only a success flag', { timeout: 5000 }, async (t) => {
  const getUserInfoFromCode = t.mock.fn(async (code) => {
    if (code === 'fixture-timeout') throw new UaePassError('timeout', 'token');
    return { uuid: 'fixture-profile-id' };
  });
  const endpoint = await listen(t, getUserInfoFromCode);

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
  const endpoint = await listen(t, getUserInfoFromCode);

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
