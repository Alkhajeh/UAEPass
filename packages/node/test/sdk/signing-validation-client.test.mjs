import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import {
  createUaePassSigningClient,
  createUaePassSigningValidationClient,
  UaePassSigningValidationError,
} from '@alkhajeh/uaepass-server';
const stagingGatewayUrl = 'https://stg-id.uaepass.ae/trustedx-gw/SoapGateway';
const config = {
  environment: 'staging',
  clientId: 'fixture<client',
  clientSecret: 'fixture&secret',
};
const signatureFieldName = 'FixtureSign';
const pdf = Buffer.from('%PDF-1.7\nsigned fixture\n%%EOF');
const finalPdf = Buffer.from('%PDF-1.7\nupdated signed fixture\n%%EOF');
const expectedSigner = 'CN=Fixture Signer,serialNumber=784000000000000,C=AE';
const namespace = 'http://www.docs.oasis-open.org/dss/2004/06/oasis-dss-1.0-core-schema-wd-27.xsd';
const soapNamespace = 'http://schemas.xmlsoap.org/soap/envelope/';
const signerFormat = 'urn:oasis:names:tc:SAML:1.1:nameid-format:X509SubjectName';
const resultMajor = '<dss:ResultMajor>urn:oasis:names:tc:dss:1.0:resultmajor:Success</dss:ResultMajor>';
const resultMinor = '<dss:ResultMinor>urn:oasis:names:tc:dss:1.0:resultminor:ValidSignature_OnAllDocuments</dss:ResultMinor>';

function envelope(body) {
  return `<soap:Envelope xmlns:soap="${soapNamespace}" xmlns:dss="${namespace}" xmlns:css="http://www.safelayer.com/TWS"><soap:Body>${body}</soap:Body></soap:Envelope>`;
}

function response(xml) {
  return new Response(xml, { headers: { 'Content-Type': 'text/xml; charset=utf-8' } });
}

function updateResponse(encodedPdf = finalPdf.toString('base64')) {
  return envelope(`<dss:VerifyResponse>
    <dss:Result>${resultMajor}</dss:Result>
    <dss:OptionalOutputs>
      <dss:DocumentWithSignature><dss:XMLData><dss:Base64Data MimeType="application/pdf">
        ${encodedPdf}
      </dss:Base64Data></dss:XMLData></dss:DocumentWithSignature>
    </dss:OptionalOutputs>
  </dss:VerifyResponse>`);
}

function verificationResponse() {
  return envelope(`<dss:VerifyResponse>
    <dss:Result>${resultMajor}${resultMinor}</dss:Result>
    <dss:OptionalOutputs>
      <dss:SignerIdentity Format="${signerFormat}">${expectedSigner}</dss:SignerIdentity>
      <css:VerifyingPolicy><css:Identifier>urn:uae:tws:verification:policy:digitalid</css:Identifier></css:VerifyingPolicy>
      <css:ValidationPolicy><css:Identifier>urn:uae:tws:validation:policy:digitalid</css:Identifier></css:ValidationPolicy>
      <css:PdfFieldLabel>${signatureFieldName}</css:PdfFieldLabel>
      <css:NumberPdfSignatures>1</css:NumberPdfSignatures>
    </dss:OptionalOutputs>
  </dss:VerifyResponse>`);
}

function mockGateway(t, updateXml = updateResponse(), verificationXml = verificationResponse()) {
  return t.mock.method(globalThis, 'fetch', async (_url, init) => {
    const action = new Headers(init.headers).get('SOAPAction');
    assert.ok(action === 'Update' || action === 'Verify');
    return response(action === 'Update' ? updateXml : verificationXml);
  });
}

test('sends the documented SOAP requests and returns the updated PDF and signer evidence', async (t) => {
  const fetch = mockGateway(t);
  const validation = createUaePassSigningValidationClient(config);
  const updatedPdf = await validation.applyLongTermValidation(pdf, signatureFieldName);
  assert.deepEqual(updatedPdf, finalPdf);
  assert.deepEqual(await validation.verifySignedPdf(updatedPdf), {
    signatureFieldName, signerSubject: expectedSigner,
  });

  assert.equal(fetch.mock.callCount(), 2);
  const [[updateUrl, update], [verifyUrl, verify]] = fetch.mock.calls.map((call) => call.arguments);
  for (const [url, request] of [[updateUrl, update], [verifyUrl, verify]]) {
    assert.equal(url.href, stagingGatewayUrl);
    assert.equal(request.method, 'POST');
    assert.equal(request.redirect, 'manual');
    assert.equal(request.headers.TwsAuthN, 'urn:safelayer:tws:policies:authentication:oauth:clients');
    assert.ok(request.body.includes('soap:actor="http://schemas.xmlsoap.org/soap/actor/next"'));
    assert.match(request.body, /<wsse:Username>fixture&lt;client<\/wsse:Username>/);
    assert.match(request.body, />fixture&amp;secret<\/wsse:Password>/);
  }
  assert.equal(update.headers.SOAPAction, 'Update');
  assert.ok(update.body.includes(`>${pdf.toString('base64')}</dss:Base64Data>`));
  assert.ok(update.body.includes(`<css:PdfFieldLabel>${signatureFieldName}</css:PdfFieldLabel>`));
  assert.equal(verify.headers.SOAPAction, 'Verify');
  assert.ok(verify.body.includes(`>${finalPdf.toString('base64')}</dss:Base64Data>`));
  assert.match(verify.body, /<css:ReturnSignerIdentity binary="true"\/>/);
});

test('requires PDF bytes before calling the gateway', async (t) => {
  const fetch = mockGateway(t);
  const validation = createUaePassSigningValidationClient(config);
  const invalidPdf = Buffer.from('not a PDF');
  await assert.rejects(() => validation.applyLongTermValidation(invalidPdf, signatureFieldName), /signed PDF/);
  await assert.rejects(() => validation.verifySignedPdf(invalidPdf), /signed PDF/);
  assert.equal(fetch.mock.callCount(), 0);
});

test('downloads, finalizes, and verifies a PDF that grows beyond the original upload limit', async (t) => {
  const timeout = t.mock.method(AbortSignal, 'timeout');
  const originalPdf = Buffer.alloc(10 * 1024 * 1024);
  pdf.copy(originalPdf);
  const signedPdf = Buffer.concat([originalPdf, Buffer.from('\n% fixture signature\n%%EOF')]);
  const ltvPdf = Buffer.concat([signedPdf, Buffer.from('\n% fixture LTV data\n%%EOF')]);
  const origin = new URL(stagingGatewayUrl).origin;
  const signingPath = '/trustedx-resources/esignsp/v2';
  const processId = 'sp_fixture';
  const documentId = 'dc_fixture';
  const approvalUrl = `${origin}${signingPath}/ui?signerProcessId=${processId}`;
  const fetch = t.mock.method(globalThis, 'fetch', async (url, init) => {
    if (url.pathname.endsWith('/signer_processes')) {
      assert.equal(init.body.get('document').size, originalPdf.byteLength);
      return Response.json({
        id: processId,
        tasks: { pending: [{ type: 'UserBrowserTask', url: approvalUrl }] },
        documents: [{ id: documentId }],
      }, { status: 201 });
    }
    if (url.pathname === `${signingPath}/signer_processes/${processId}/result`) {
      return Response.json({ status: 'finished' });
    }
    if (url.pathname === `${signingPath}/documents/${documentId}/content`) {
      return new Response(signedPdf, { headers: { 'Content-Type': 'application/pdf' } });
    }
    assert.equal(url.href, stagingGatewayUrl);
    if (init.headers.SOAPAction === 'Update') {
      assert.ok(init.body.includes(`>${signedPdf.toString('base64')}</dss:Base64Data>`));
      return response(updateResponse(ltvPdf.toString('base64')));
    }
    assert.equal(init.headers.SOAPAction, 'Verify');
    assert.ok(init.body.includes(`>${ltvPdf.toString('base64')}</dss:Base64Data>`));
    return response(verificationResponse());
  });

  const signing = createUaePassSigningClient({ ...config, finishCallbackUrl: 'https://example.test/signing' });
  const validation = createUaePassSigningValidationClient(config);
  const accessToken = 'fixture-signing-token';
  const process = await signing.createProcess({
    pdf: originalPdf, filename: 'fixture.pdf', signatureField: { name: signatureFieldName },
  }, accessToken);
  assert.deepEqual(await signing.getProcessResult(process.processId, accessToken), { status: 'finished' });
  const downloaded = await signing.downloadSignedPdf(process.documentId, accessToken);
  assert.equal(Buffer.compare(downloaded, signedPdf), 0);
  const finalized = await validation.finalizeSignedPdf(downloaded, {
    expectedSignatureFieldName: signatureFieldName,
    matchSigner: (subject) => subject === expectedSigner,
  });
  assert.equal(Buffer.compare(finalized.pdf, ltvPdf), 0);
  assert.deepEqual(finalized.signature, { signatureFieldName, signerSubject: expectedSigner });
  assert.equal(fetch.mock.callCount(), 5);
  assert.deepEqual(timeout.mock.calls.map(({ arguments: [ms] }) => ms), [60_000, 15_000, 60_000, 60_000, 60_000]);
});

test('a legacy gatewayUrl field cannot change the destination of SOAP requests', async (t) => {
  const fetch = mockGateway(t);
  const validation = createUaePassSigningValidationClient({
    ...config, gatewayUrl: 'https://qa-id.uaepass.ae/trustedx-gw/SoapGateway',
  });
  await validation.verifySignedPdf(finalPdf);
  assert.equal(fetch.mock.callCount(), 1);
  assert.equal(fetch.mock.calls[0].arguments[0].href, stagingGatewayUrl);
});

test('rejects unexpected verification results', async (t) => {
  const valid = verificationResponse();
  const failures = {
    'unsupported identity format': valid.replace(signerFormat, 'other-signer-format'),
    'multiple signatures': valid.replace('>1</css:NumberPdfSignatures>', '>2</css:NumberPdfSignatures>'),
    'wrong provider policy': valid.replace('urn:uae:tws:validation:policy:digitalid', 'other-policy'),
    'ambiguous result': valid.replace(resultMajor, resultMajor.repeat(2)),
  };

  for (const [name, xml] of Object.entries(failures)) {
    await t.test(name, async (subtest) => {
      mockGateway(subtest, updateResponse(), xml);
      const validation = createUaePassSigningValidationClient(config);
      await assert.rejects(() => validation.verifySignedPdf(finalPdf), /unexpected signing SOAP response|did not verify/);
    });
  }
});

test('rejects malformed SOAP and invalid PDF results', async (t) => {
  const valid = updateResponse();
  const failures = {
    'DTD': `<!DOCTYPE soap:Envelope [<!ENTITY fixture "data">]>${valid}`,
    'malformed XML': valid.replace('</dss:VerifyResponse>', '</dss:SignResponse>'),
    'untrusted namespace': valid.replace(namespace, 'https://example.test/dss'),
    'noncanonical base64': updateResponse(`${finalPdf.toString('base64')}!`),
    'wrong media type': valid.replace('application/pdf', 'text/plain'),
    'not PDF bytes': updateResponse(Buffer.from('wrong document bytes').toString('base64')),
  };

  for (const [name, xml] of Object.entries(failures)) {
    await t.test(name, async (subtest) => {
      const fetch = mockGateway(subtest, xml);
      const validation = createUaePassSigningValidationClient(config);
      await assert.rejects(() => validation.applyLongTermValidation(pdf, signatureFieldName), /unexpected signing SOAP response/);
      assert.equal(fetch.mock.callCount(), 1);
    });
  }
});

test('cancels oversized LTV and verification responses before buffering them', async (t) => {
  let canceled = 0;
  const responseLimits = { Update: 48 * 1024 * 1024, Verify: 128 * 1024 };
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    const body = new ReadableStream({ cancel: () => { canceled++; } });
    return new Response(body, {
      headers: {
        'Content-Type': 'text/xml',
        'Content-Length': String(responseLimits[init.headers.SOAPAction] + 1),
      },
    });
  });
  const validation = createUaePassSigningValidationClient(config);
  await assert.rejects(() => validation.applyLongTermValidation(pdf, signatureFieldName), {
    code: 'invalid_response', operation: 'ltv', status: 200,
  });
  await assert.rejects(() => validation.verifySignedPdf(pdf), {
    code: 'invalid_response', operation: 'verify', status: 200,
  });
  assert.equal(canceled, 2);
});

test('reports sanitized provider transport failures without retrying', async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => {
    throw new Error('raw transport response with confidential request metadata');
  });
  const validation = createUaePassSigningValidationClient(config);
  await assert.rejects(() => validation.applyLongTermValidation(pdf, signatureFieldName), (error) => {
    assert.ok(error instanceof UaePassSigningValidationError);
    assert.equal(error.code, 'unavailable');
    assert.equal(error.operation, 'ltv');
    assert.equal(error.cause, undefined);
    assert.doesNotMatch(error.message, /confidential/);
    return true;
  });
  assert.equal(fetch.mock.callCount(), 1);
});

test('reports a declined update returned in a successful HTTP response', async (t) => {
  const update = updateResponse().replace('resultmajor:Success', 'resultmajor:RequesterError');
  const fetch = mockGateway(t, update);
  const validation = createUaePassSigningValidationClient(config);
  await assert.rejects(() => validation.applyLongTermValidation(pdf, signatureFieldName), {
    name: 'UaePassSigningValidationError', code: 'rejected', operation: 'ltv', status: 200,
  });
  assert.equal(fetch.mock.callCount(), 1);
});

test('exports independent SOAP operations with fixed gateway URLs and typed results', async (t) => {
  const staging = createUaePassSigningValidationClient(config);
  const production = createUaePassSigningValidationClient({ ...config, environment: 'production' });

  const label = ' Fixture & Sign\r ';
  const fetch = mockGateway(t, updateResponse(),
    verificationResponse().replace(signatureFieldName, ' Fixture &amp; Sign&#13; '));
  assert.deepEqual(await staging.applyLongTermValidation(pdf, label), finalPdf);
  assert.equal(fetch.mock.callCount(), 1);
  const [stageUrl, update] = fetch.mock.calls[0].arguments;
  assert.equal(stageUrl.href, stagingGatewayUrl);
  assert.match(update.body, /<css:PdfFieldLabel> Fixture &amp; Sign&#13; <\/css:PdfFieldLabel>/);
  assert.deepEqual(await production.verifySignedPdf(finalPdf), {
    signatureFieldName: label, signerSubject: expectedSigner,
  });
  assert.equal(fetch.mock.callCount(), 2);
  const [productionUrl, verify] = fetch.mock.calls[1].arguments;
  assert.equal(productionUrl.href, 'https://id.uaepass.ae/trustedx-gw/SoapGateway');
  assert.equal(verify.headers.SOAPAction, 'Verify');
});

test('treats certificate identity as optional evidence and classifies an unsuccessful signature', async (t) => {
  const validation = createUaePassSigningValidationClient(config);
  const withoutIdentity = verificationResponse().replace(/<dss:SignerIdentity[^>]*>.*?<\/dss:SignerIdentity>/, '');
  const invalid = withoutIdentity.replace('ValidSignature_OnAllDocuments', 'InvalidSignature');
  const replies = [withoutIdentity, invalid];
  t.mock.method(globalThis, 'fetch', async () => response(replies.shift()));
  assert.deepEqual(await validation.verifySignedPdf(finalPdf), { signatureFieldName });
  await assert.rejects(() => validation.verifySignedPdf(finalPdf), {
    name: 'UaePassSigningValidationError', code: 'verification_failed', operation: 'verify', status: 200,
  });
});

test('rejects HTTP redirects without forwarding SOAP credentials or document bytes', async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch', async (_url, init) => {
    assert.equal(init.redirect, 'manual');
    return Response.redirect('https://example.test/other-gateway', 307);
  });
  const validation = createUaePassSigningValidationClient(config);
  await assert.rejects(() => validation.verifySignedPdf(finalPdf), {
    name: 'UaePassSigningValidationError', code: 'invalid_response', operation: 'verify', status: 307,
  });
  assert.equal(fetch.mock.callCount(), 1);
});

test('finalizes the LTV bytes after verification and a successful signer match', async (t) => {
  for (const asynchronous of [false, true]) {
    await t.test(asynchronous ? 'async matcher' : 'sync matcher', async (subtest) => {
      const fetch = mockGateway(subtest);
      const { finalizeSignedPdf } = createUaePassSigningValidationClient(config);
      const matchSigner = subtest.mock.fn((subject) => {
        assert.equal(fetch.mock.callCount(), 2);
        assert.equal(subject, expectedSigner);
        return asynchronous ? Promise.resolve(true) : true;
      });

      const result = await finalizeSignedPdf(pdf, {
        expectedSignatureFieldName: signatureFieldName, matchSigner,
      });
      assert.deepEqual(result, { pdf: finalPdf, signature: { signatureFieldName, signerSubject: expectedSigner } });
      const [[, update], [, verify]] = fetch.mock.calls.map(({ arguments: args }) => args);
      assert.equal(update.headers.SOAPAction, 'Update');
      assert.equal(verify.headers.SOAPAction, 'Verify');
      assert.ok(verify.body.includes(finalPdf.toString('base64')));
      assert.equal(matchSigner.mock.callCount(), 1);
    });
  }
});

test('validates finalization inputs before making a provider request', async (t) => {
  const fetch = mockGateway(t);
  const matchSigner = t.mock.fn(() => true);
  const options = { expectedSignatureFieldName: signatureFieldName, matchSigner };
  const validation = createUaePassSigningValidationClient(config);
  for (const [input, settings] of [
    [pdf, undefined],
    [pdf, { ...options, matchSigner: true }],
    [pdf, { ...options, expectedSignatureFieldName: '' }],
    [Buffer.from('not a PDF'), options],
  ]) {
    await assert.rejects(() => validation.finalizeSignedPdf(input, settings), TypeError);
  }
  assert.equal(fetch.mock.callCount(), 0);
  assert.equal(matchSigner.mock.callCount(), 0);
});

test('stops finalization on provider failures and preserves the operation and status', async (t) => {
  for (const [action, status, code, operation, requestCount] of [
    ['Update', 401, 'invalid_client', 'ltv', 1],
    ['Verify', 503, 'unavailable', 'verify', 2],
  ]) {
    await t.test(operation, async (subtest) => {
      const fetch = subtest.mock.method(globalThis, 'fetch', async (_url, init) =>
        init.headers.SOAPAction === action ? new Response(null, { status }) : response(updateResponse()));
      const matchSigner = subtest.mock.fn(() => true);
      const validation = createUaePassSigningValidationClient(config);
      await assert.rejects(() => validation.finalizeSignedPdf(pdf, {
        expectedSignatureFieldName: signatureFieldName, matchSigner,
      }), { name: 'UaePassSigningValidationError', code, operation, status });
      assert.equal(fetch.mock.callCount(), requestCount);
      assert.equal(matchSigner.mock.callCount(), 0);
    });
  }
});

test('stops finalization before matching if verification fails or evidence is missing', async (t) => {
  const verified = verificationResponse();
  const cases = [
    ['provider signature failure', verified.replace('ValidSignature_OnAllDocuments', 'InvalidSignature'),
      'verification_failed', 'verify', 200],
    ['field mismatch', verified.replace(signatureFieldName, ' ' + signatureFieldName),
      'verification_failed', 'verify', undefined],
    ['missing signer', verified.replace(/<dss:SignerIdentity[^>]*>.*?<\/dss:SignerIdentity>/, ''),
      'signer_unverified', 'match_signer', undefined],
  ];
  for (const [name, xml, code, operation, status] of cases) {
    await t.test(name, async (subtest) => {
      const fetch = mockGateway(subtest, updateResponse(), xml);
      const matchSigner = subtest.mock.fn(() => true);
      const validation = createUaePassSigningValidationClient(config);
      await assert.rejects(() => validation.finalizeSignedPdf(pdf, {
        expectedSignatureFieldName: signatureFieldName, matchSigner,
      }), { name: 'UaePassSigningValidationError', code, operation, status });
      assert.equal(fetch.mock.callCount(), 2);
      assert.equal(matchSigner.mock.callCount(), 0);
    });
  }
});

test('fails closed on declined matches and sanitizes matcher failures', async (t) => {
  const sensitiveDetail = 'fixture confidential matcher detail';
  const cases = [
    ['false', () => false, 'signer_unverified'],
    ['truthy non-boolean', () => 'yes', 'signer_unverified'],
    ['synchronous throw', () => { throw new Error(sensitiveDetail); }, 'signer_match_failed'],
    ['asynchronous rejection', async () => { throw new Error(sensitiveDetail); }, 'signer_match_failed'],
  ];
  for (const [name, matcher, code] of cases) {
    await t.test(name, async (subtest) => {
      const fetch = mockGateway(subtest);
      const matchSigner = subtest.mock.fn(matcher);
      const validation = createUaePassSigningValidationClient(config);
      await assert.rejects(() => validation.finalizeSignedPdf(pdf, {
        expectedSignatureFieldName: signatureFieldName, matchSigner,
      }), (error) => {
        assert.ok(error instanceof UaePassSigningValidationError);
        assert.equal(error.code, code);
        assert.equal(error.operation, 'match_signer');
        assert.equal(error.status, undefined);
        assert.equal(error.cause, undefined);
        assert.equal('pdf' in error, false);
        assert.equal('signature' in error, false);
        assert.equal(error.stack.includes(sensitiveDetail), false);
        assert.equal(error.stack.includes(expectedSigner), false);
        return true;
      });
      assert.equal(fetch.mock.callCount(), 2);
      assert.deepEqual(matchSigner.mock.calls.map(({ arguments: args }) => args), [[expectedSigner]]);
    });
  }
});
