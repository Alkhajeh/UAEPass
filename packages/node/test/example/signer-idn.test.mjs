import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import { matchesSignerIdn, normalizeSignerIdn } from '../../example/signing/signer-idn.mjs';

const expectedIdn = '784-0000-0000000-0';
const signerIdn = '784000000000000';
const subjectIdn = Buffer.from(signerIdn).toString('hex');
const signerSubject = 'CN=Fixture Signer+OID.2.5.4.5=#130F' + subjectIdn + ',C=AE';

test('matches a DER-encoded certificate serial number to the authenticated IDN', () => {
  assert.equal(normalizeSignerIdn(expectedIdn), signerIdn);
  assert.equal(matchesSignerIdn(signerSubject, expectedIdn), true);
});

test('matches a textual serial number when another subject value contains an escaped comma', () => {
  const subject = 'CN=Fixture\\, Signer,serialNumber=784-0000-0000000-0,C=AE';
  assert.equal(matchesSignerIdn(subject, expectedIdn), true);
});

test('rejects missing, mismatched, and ambiguous signer identities', () => {
  for (const subject of [
    'CN=Fixture Signer,serialNumber=784000000000001',
    'CN=' + signerIdn,
    'CN=Fixture\\,serialNumber=' + signerIdn + ',C=AE',
    signerSubject + ',serialNumber=' + signerIdn,
    undefined,
  ]) {
    assert.equal(matchesSignerIdn(subject, expectedIdn), false);
  }
  assert.equal(matchesSignerIdn(signerSubject, undefined), false);
  assert.equal(matchesSignerIdn(signerSubject, 'fixture-non-idn'), false);
});
