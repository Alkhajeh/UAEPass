import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { UaePassError } from '@alkhajeh/uaepass-server';
import { createExampleServer } from '../example/server.mjs';

test('the local endpoint exchanges a code and returns only a success flag', { timeout: 5000 }, async (t) => {
  const getUserInfoFromCode = t.mock.fn(async (code) => {
    if (code === 'fixture-timeout') throw new UaePassError('timeout', 'token');
    return { uuid: 'fixture-profile-id' };
  });
  const server = createExampleServer({ getUserInfoFromCode });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    const closed = once(server, 'close');
    server.close();
    await closed;
  });

  const endpoint = `http://127.0.0.1:${server.address().port}/auth/uaepass`;
  const post = (body) => fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  const success = await post({ code: 'fixture-code' });
  assert.equal(success.status, 200);
  assert.equal(success.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await success.json(), { ok: true });

  const missingCode = await post({});
  assert.equal(missingCode.status, 400);
  assert.deepEqual(await missingCode.json(), { ok: false });

  const timeout = await post({ code: 'fixture-timeout' });
  assert.equal(timeout.status, 504);
  assert.deepEqual(await timeout.json(), { ok: false });
  assert.deepEqual(getUserInfoFromCode.mock.calls.map(({ arguments: args }) => args), [
    ['fixture-code'],
    ['fixture-timeout'],
  ]);
});
