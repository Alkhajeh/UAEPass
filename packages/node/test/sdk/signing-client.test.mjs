import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import {
  createUaePassSigningClient,
  UaePassSignatureAppearance,
  UaePassSignatureLevel,
  UaePassSigningError,
} from '@alkhajeh/uaepass-server';

const config = {
  environment: 'staging',
  clientId: 'fixture-signing-client',
  clientSecret: 'fixture-signing-secret',
  finishCallbackUrl: 'https://EXAMPLE.test:443/signing/return?app=demo%20app',
};
const origin = 'https://stg-id.uaepass.ae';
const base = '/trustedx-resources/esignsp/v2';
const processId = 'sp_fixture-123';
const documentId = 'dc_fixture-456';
const approvalUrl = `${origin}${base}/ui?signerProcessId=${processId}`;
const documentUrl = `${origin}${base}/documents/${documentId}`;
const accessToken = 'fixture-signing-token';
const pdf = new Uint8Array(Buffer.from('%PDF-1.5\n% synthetic PDF transport fixture\n%%EOF\n'));
const signedPdf = new Uint8Array(Buffer.from('%PDF-1.5\n% synthetic signed payload\n%%EOF\n'));
const createInput = {
  pdf,
  filename: 'document.pdf',
  signatureField: {
    name: 'Sign1',
    location: { page: 'last', rectangle: { x: 0, y: 10, width: 300, height: 90 } },
  },
};
const tokenResponse = { access_token: accessToken, token_type: 'Bearer', expires_in: 600 };
const processResponse = {
  id: processId,
  tasks: { pending: [{ type: 'UserBrowserTask', url: approvalUrl }] },
  documents: [{ url: documentUrl }],
};

test('runs the documented qualified PDF signing requests and preserves binary PDF bytes', async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch', async (url, init) => {
    assert.equal(init.redirect, 'manual');
    assert.equal(url.origin, origin);
    if (url.pathname === '/trustedx-authserver/oauth/main-as/token') {
      assert.equal(init.method, 'POST');
      assert.deepEqual(Object.fromEntries(url.searchParams), {
        grant_type: 'client_credentials',
        scope: 'urn:safelayer:eidas:sign:process:document',
      });
      const credentials = Buffer.from(`${config.clientId}:${config.clientSecret}`).toString('base64');
      assert.equal(init.headers.Authorization, `Basic ${credentials}`);
      assert.equal(init.headers['Content-Type'], 'text/plain');
      assert.equal(init.body, undefined);
      return Response.json(tokenResponse);
    }
    assert.equal(init.headers.Authorization, `Bearer ${accessToken}`);
    assert.equal(url.search, '');
    if (url.pathname === `${base}/signer_processes`) {
      assert.equal(init.method, 'POST');
      const request = new Request(url, init);
      assert.match(request.headers.get('Content-Type'), /^multipart\/form-data; boundary=/);
      const form = await request.formData();
      assert.deepEqual([...form.keys()], ['process', 'document']);
      const process = JSON.parse(form.get('process'));
      assert.deepEqual(process.ui_locales, ['en_US']);
      assert.equal(process.finish_callback_url, config.finishCallbackUrl);
      assert.equal(process.process_type, 'urn:safelayer:eidas:processes:document:sign:esigp');
      assert.deepEqual(process.labels, [['digitalid', 'server', 'qualified']]);
      assert.equal(process.signer.signature_policy_id, 'urn:safelayer:eidas:policies:sign:document:pdf');
      assert.equal(process.signer.parameters.type, 'pades-baseline');
      const field = process.signer.parameters.signature_field;
      assert.equal(field.name, 'Sign1');
      assert.deepEqual(field.location, {
        page: { number: 'last' },
        rectangle: createInput.signatureField.location.rectangle,
      });
      assert.equal(Object.hasOwn(field, 'appearance'), false);
      assert.equal(process.views.document_agreement.skip_server_id, 'false');
      assert.equal(process.timestamp.provider_id, 'urn:uae:tws:generation:policy:digitalid');
      const document = form.get('document');
      assert.equal(document.name, createInput.filename);
      assert.equal(document.type, 'application/pdf');
      assert.deepEqual(new Uint8Array(await document.arrayBuffer()), pdf);
      return Response.json(processResponse, { status: 201 });
    }
    if (url.pathname === `${base}/signer_processes/${processId}/result`) {
      assert.equal(init.method, 'GET');
      return Response.json({ status: 'finished', details: { message: 'Provider data' } });
    }
    if (url.pathname === `${base}/documents/${documentId}/content`) {
      assert.equal(init.method, 'GET');
      assert.equal(init.headers.Accept, 'application/pdf');
      return new Response(signedPdf, { headers: { 'Content-Type': 'application/pdf' } });
    }
    assert.equal(url.pathname, `${base}/signer_processes/${processId}`);
    assert.equal(init.method, 'DELETE');
    return new Response(null, { status: 204 });
  });

  const signing = createUaePassSigningClient(config);
  assert.deepEqual(await signing.getAccessToken(), { accessToken, expiresInSeconds: 600 });
  assert.deepEqual(await signing.createProcess(createInput, accessToken), {
    approvalUrl, documentId, processId,
  });
  assert.deepEqual(await signing.getProcessResult(processId, accessToken), { status: 'finished' });
  assert.deepEqual(await signing.downloadSignedPdf(documentId, accessToken), signedPdf);
  assert.equal(await signing.deleteProcess(processId, accessToken), undefined);
  assert.equal(fetch.mock.callCount(), 5);
});

test('requests the explicit signing level and rejects unsupported levels before sending', async (t) => {
  const sentLabels = [];
  const fetch = t.mock.method(globalThis, 'fetch', async (_, init) => {
    sentLabels.push(JSON.parse(init.body.get('process')).labels);
    return Response.json(processResponse, { status: 201 });
  });
  const signing = createUaePassSigningClient(config);
  await signing.createProcess({ ...createInput, signatureLevel: UaePassSignatureLevel.Advanced }, accessToken);
  await signing.createProcess({ ...createInput, signatureLevel: UaePassSignatureLevel.Qualified }, accessToken);
  assert.deepEqual(sentLabels, [[['digitalid', 'server', 'advanced']], [['digitalid', 'server', 'qualified']]]);

  for (const signatureLevel of ['auto', '', null]) {
    await assert.rejects(signing.createProcess({ ...createInput, signatureLevel }, accessToken), {
      name: 'TypeError', message: /supported UAE PASS signature level/,
    });
  }
  assert.equal(fetch.mock.callCount(), 2);
});

test('sets the hosted signing locale while preserving the signature appearance', async (t) => {
  const requests = [];
  const fetch = t.mock.method(globalThis, 'fetch', async (_, init) => {
    requests.push(JSON.parse(init.body.get('process')));
    return Response.json(processResponse, { status: 201 });
  });
  const signing = createUaePassSigningClient(config);
  const input = {
    ...createInput,
    signatureField: { ...createInput.signatureField, appearance: UaePassSignatureAppearance.SignerAndDateTime },
  };
  await signing.createProcess({ ...input, locale: 'en' }, accessToken);
  await signing.createProcess({ ...input, locale: 'ar' }, accessToken);
  assert.deepEqual(requests.map((request) => request.ui_locales), [['en_US'], ['ar_AE']]);
  assert.deepEqual(requests[1].signer, requests[0].signer);

  for (const locale of ['ar_AE', 'fr', '', null]) {
    await assert.rejects(signing.createProcess({ ...input, locale }, accessToken), {
      name: 'TypeError', message: /supported UAE PASS signing locale/,
    });
  }
  assert.equal(fetch.mock.callCount(), 2);
});

test('omits unspecified signature options and serializes the explicit appearance presets', async (t) => {
  assert.deepEqual(UaePassSignatureAppearance, {
    DateTimeOnly: 'date-time-only',
    SignerAndDateTime: 'signer-and-date-time',
    Hidden: 'hidden',
  });

  let field;
  t.mock.method(globalThis, 'fetch', async (_, init) => {
    field = JSON.parse(init.body.get('process')).signer.parameters.signature_field;
    return Response.json(processResponse, { status: 201 });
  });
  const signing = createUaePassSigningClient(config);
  const name = createInput.signatureField.name;
  await signing.createProcess({ ...createInput, signatureField: { name } }, accessToken);
  assert.deepEqual(field, { name });

  const date = { type: 'date', title: 'Signature Date: ' };
  const subject = { type: 'subject', title: 'Signer Name: ' };
  for (const [appearance, expected] of [
    [UaePassSignatureAppearance.DateTimeOnly, { signature_details: { details: [date] } }],
    [UaePassSignatureAppearance.SignerAndDateTime, { signature_details: { details: [subject, date] } }],
    [UaePassSignatureAppearance.Hidden, {}],
  ]) {
    await signing.createProcess({ ...createInput, signatureField: { name, appearance } }, accessToken);
    assert.deepEqual(field, { name, appearance: expected });
  }
});

test('requires matching hosted approval and document references for one PDF', async (t) => {
  let payload = {
    ...processResponse,
    documents: [{ id: documentId, url: documentUrl, content: `${documentUrl}/content` }],
  };
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    assert.equal(url.pathname, `${base}/signer_processes`);
    const process = JSON.parse(init.body.get('process'));
    assert.equal(process.signer.parameters.signature_field.location.page.number, '1');
    return Response.json(payload, { status: 201 });
  });
  const signing = createUaePassSigningClient(config);
  const signatureField = {
    ...createInput.signatureField,
    location: { ...createInput.signatureField.location, page: 1 },
  };
  const input = { ...createInput, signatureField };
  assert.equal((await signing.createProcess(input, accessToken)).documentId, documentId);

  for (const url of [
    approvalUrl.replace(origin, 'https://evil.example'),
    approvalUrl.replace('stg-id.', 'id.'),
    approvalUrl.replace('/ui?', '/other?'),
    approvalUrl.replace(processId, 'sp_other'),
    approvalUrl + '\u0000',
    `${approvalUrl}&signerProcessId=${processId}`,
    `${approvalUrl}#fragment`,
  ]) {
    payload = { ...processResponse, tasks: { pending: [{ type: 'UserBrowserTask', url }] } };
    await assert.rejects(signing.createProcess(input, accessToken), {
      code: 'invalid_response', operation: 'create', status: 201,
    });
  }
  for (const documents of [
    [{ id: documentId }],
    [{ content: `${documentUrl}/content` }],
    [{ id: documentId, content: `${documentUrl}/content` }],
  ]) {
    payload = { ...processResponse, documents };
    assert.equal((await signing.createProcess(input, accessToken)).documentId, documentId);
  }
  for (const documents of [
    [],
    [{}],
    [{ id: 'dc other' }],
    [{ id: 42, url: documentUrl }],
    [{ url: `${documentUrl}/content` }],
    [{ content: documentUrl }],
    [{ content: `${documentUrl}/content/` }],
    [{ id: documentId, content: `${origin}${base}/documents/dc_other/content` }],
    [...processResponse.documents, ...processResponse.documents],
    [{ id: 'dc_other', url: documentUrl }],
    [{ url: documentUrl, content: `${origin}${base}/documents/dc_other/content` }],
    [{ id: documentId, url: documentUrl.replace(origin, 'https://evil.example') }],
    [{ url: `${documentUrl}/extra` }],
    [{ url: `${documentUrl}?extra=1` }],
    [{ url: `${origin}${base}/documents/%2F` }],
  ]) {
    payload = { ...processResponse, documents };
    await assert.rejects(signing.createProcess(input, accessToken), {
      code: 'invalid_response', operation: 'create', status: 201,
    });
  }
});

test('reports terminal result statuses and rejects unknown status values', async (t) => {
  const statuses = ['finished', 'failed', 'failed_documents', 'canceled', 'unknown'];
  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(url.origin, 'https://id.uaepass.ae');
    return Response.json({ status: statuses.shift(), details: { message: accessToken } });
  });
  const signing = createUaePassSigningClient({ ...config, environment: 'production' });
  for (const status of statuses.slice(0, -1)) {
    assert.deepEqual(await signing.getProcessResult(processId, accessToken), { status });
  }
  await assert.rejects(signing.getProcessResult(processId, accessToken), {
    code: 'invalid_response', operation: 'result', status: 200,
  });
});

test('validates signing configuration, request inputs, and binary responses', async (t) => {
  let response;
  const fetch = t.mock.method(globalThis, 'fetch', async () => response);
  const localhost = 'http://localhost:8000/signing/return';
  assert.doesNotThrow(() => createUaePassSigningClient({ ...config, finishCallbackUrl: localhost }));
  assert.throws(() =>
    createUaePassSigningClient({ ...config, environment: 'production', finishCallbackUrl: localhost }),
  TypeError);
  for (const finishCallbackUrl of [
    'http://localhost.example/return',
    'https:///service.example/return',
    'https://service.example\\return',
    'https://service.example/return\u0000',
    'https://user@service.example/return',
    'https://service.example/return#fragment',
    'https://service.example/return?signer_process_id=123',
    'https://service.example/return?status=finished',
  ]) {
    assert.throws(() => createUaePassSigningClient({ ...config, finishCallbackUrl }), TypeError);
  }
  const signing = createUaePassSigningClient(config);
  await assert.rejects(signing.getProcessResult('..', accessToken), TypeError);
  await assert.rejects(signing.downloadSignedPdf('id/../other', accessToken), TypeError);
  await assert.rejects(signing.deleteProcess(processId, 'invalid token'), TypeError);
  await assert.rejects(signing.createProcess({ ...createInput, pdf: new Uint8Array() }, accessToken), TypeError);
  const oversizedPdf = new Uint8Array(10 * 1024 * 1024 + 1);
  oversizedPdf.set(Buffer.from('%PDF-'));
  await assert.rejects(signing.createProcess({ ...createInput, pdf: oversizedPdf }, accessToken), {
    name: 'TypeError', message: 'Provide an original PDF up to 10485760 bytes.',
  });
  await assert.rejects(signing.createProcess({ ...createInput, filename: '../file' }, accessToken), TypeError);
  for (const name of ['Invalid\uFFFE', 'Invalid\uD800']) {
    const signatureField = { ...createInput.signatureField, name };
    await assert.rejects(signing.createProcess({ ...createInput, signatureField }, accessToken), {
      name: 'TypeError', message: /signature field name/,
    });
  }
  assert.equal(fetch.mock.callCount(), 0);

  response = Response.json(tokenResponse, { status: 200 });
  await assert.rejects(signing.downloadSignedPdf(documentId, accessToken), {
    code: 'invalid_response', operation: 'download', status: 200,
  });
  response = new Response('not a PDF', { headers: { 'Content-Type': 'application/pdf' } });
  await assert.rejects(signing.downloadSignedPdf(documentId, accessToken), {
    code: 'invalid_response', operation: 'download', status: 200,
  });
  response = Response.json({ ...tokenResponse, expires_in: 0 });
  await assert.rejects(signing.getAccessToken(), {
    code: 'invalid_response', operation: 'token', status: 200,
  });
});

test('lets callers raise or lower the original PDF upload limit up to 20 MiB', async (t) => {
  const maximum = 20 * 1024 * 1024;
  const fetch = t.mock.method(globalThis, 'fetch', async (_url, init) => {
    assert.equal(init.body.get('document').size, maximum);
    return Response.json(processResponse, { status: 201 });
  });
  const largerPdf = new Uint8Array(maximum);
  largerPdf.set(pdf);

  const smallerLimit = pdf.byteLength - 1;
  const smaller = createUaePassSigningClient({ ...config, maxUploadPdfBytes: smallerLimit });
  await assert.rejects(smaller.createProcess(createInput, accessToken), {
    name: 'TypeError', message: `Provide an original PDF up to ${smallerLimit} bytes.`,
  });
  assert.equal(fetch.mock.callCount(), 0);

  const larger = createUaePassSigningClient({ ...config, maxUploadPdfBytes: maximum });
  await larger.createProcess({ ...createInput, pdf: largerPdf }, accessToken);
  assert.equal(fetch.mock.callCount(), 1);

  for (const maxUploadPdfBytes of [0, -1, 1.5, Infinity, NaN, maximum + 1, '10485760', null]) {
    assert.throws(() => createUaePassSigningClient({ ...config, maxUploadPdfBytes }), {
      name: 'TypeError', message: `Provide maxUploadPdfBytes as a whole number from 1 to ${maximum} bytes.`,
    });
  }
});

test('rejects unsupported appearances and incomplete or invalid placements before sending a request', async (t) => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => Response.json(processResponse, { status: 201 }));
  const signing = createUaePassSigningClient(config);
  const { name, location } = createInput.signatureField;
  for (const appearance of ['', 'unknown', 'constructor', {}, null]) {
    await assert.rejects(signing.createProcess({ ...createInput, signatureField: { name, appearance } }, accessToken), {
      name: 'TypeError', message: /supported signature appearance/,
    });
  }
  for (const invalidLocation of [
    null,
    { page: 1 },
    { rectangle: location.rectangle },
    { ...location, page: 'first' },
    { ...location, page: 0 },
    { ...location, page: 1.5 },
    { ...location, page: Number.MAX_SAFE_INTEGER + 1 },
    { ...location, rectangle: { ...location.rectangle, width: 0 } },
    { ...location, rectangle: { ...location.rectangle, height: -1 } },
    { ...location, rectangle: { ...location.rectangle, x: Infinity } },
  ]) {
    const signatureField = { name, location: invalidLocation };
    await assert.rejects(signing.createProcess({ ...createInput, signatureField }, accessToken), {
      name: 'TypeError', message: /signature location/,
    });
  }
  assert.equal(fetch.mock.callCount(), 0);
});

test('cancels PDF downloads that exceed the response limit', async (t) => {
  const limit = 32 * 1024 * 1024;
  let canceled = 0;
  const headers = { 'Content-Type': 'application/pdf' };
  const advertised = new ReadableStream({ cancel: () => { canceled++; } });
  const chunk = new Uint8Array(1024 * 1024);
  const streamed = new ReadableStream({
    pull(controller) { controller.enqueue(chunk); },
    cancel() { canceled++; },
  });
  const responses = [
    new Response(advertised, { headers: { ...headers, 'Content-Length': String(limit + 1) } }),
    new Response(streamed, { headers }),
  ];
  t.mock.method(globalThis, 'fetch', async () => responses.shift());
  const signing = createUaePassSigningClient(config);
  for (let i = 0; i < 2; i++) {
    await assert.rejects(signing.downloadSignedPdf(documentId, accessToken), {
      code: 'invalid_response', operation: 'download', status: 200,
    });
  }
  assert.equal(canceled, 2);
});

test('rejects malformed or oversized signing JSON responses', async (t) => {
  const responses = [
    new Response('not JSON'),
    Response.json({ ...tokenResponse, oversized: 'x'.repeat(256 * 1024) }),
  ];
  t.mock.method(globalThis, 'fetch', async () => responses.shift());
  const signing = createUaePassSigningClient(config);
  for (let i = 0; i < 2; i++) {
    await assert.rejects(signing.getAccessToken(), {
      code: 'invalid_response', operation: 'token', status: 200,
    });
  }
});

test('sanitizes provider and transport failures and does not retry a request', async (t) => {
  let response;
  const fetch = t.mock.method(globalThis, 'fetch', async () => response);
  const signing = createUaePassSigningClient(config);
  const getToken = () => signing.getAccessToken();
  const create = () => signing.createProcess(createInput, accessToken);
  for (const [call, status, code] of [
    [getToken, 401, 'invalid_client'],
    [create, 401, 'invalid_token'],
    [create, 403, 'rejected'],
    [create, 302, 'invalid_response'],
    [create, 429, 'unavailable'],
    [create, 502, 'unavailable'],
  ]) {
    response = Response.json({ debug: config.clientSecret }, { status });
    const previous = fetch.mock.callCount();
    await assert.rejects(call(), (error) => {
      assert.ok(error instanceof UaePassSigningError);
      assert.equal(error.code, code);
      assert.equal(error.status, status);
      assert.equal(error.operation, call === getToken ? 'token' : 'create');
      assert.equal(error.cause, undefined);
      for (const secret of [config.clientSecret, accessToken, config.finishCallbackUrl]) {
        assert.equal((error.stack + JSON.stringify(error)).includes(secret), false);
      }
      return true;
    });
    assert.equal(fetch.mock.callCount(), previous + 1);
  }

  t.mock.method(AbortSignal, 'timeout', () => AbortSignal.abort());
  fetch.mock.mockImplementation(async () => { throw new Error(accessToken); });
  await assert.rejects(create(), (error) => {
    assert.equal(error.code, 'timeout');
    assert.equal(error.operation, 'create');
    assert.equal(error.cause, undefined);
    assert.equal(error.stack.includes(accessToken), false);
    return true;
  });
  assert.equal(fetch.mock.callCount(), 7);
});
