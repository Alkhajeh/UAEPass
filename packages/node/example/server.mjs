import { Buffer } from 'node:buffer';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdtemp, open, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  createUaePassClient,
  createUaePassSigningClient,
  createUaePassSigningValidationClient,
  UaePassError,
  UaePassSignatureAppearance,
  UaePassSignatureLevel,
  UaePassSigningValidationError,
} from '@alkhajeh/uaepass-server';
import { matchesSignerIdn, normalizeSignerIdn } from './signer-idn.mjs';

const stagingOrigin = 'https://stg-id.uaepass.ae';
const loopbackHost = '127.0.0.1';
const port = 8787;
const defaultOrigin = 'http://localhost:' + port;
const exchange = '/auth/uaepass';
const root = '/signing';
const login = root + '/login';
const callback = root + '/auth/callback';
const finish = root + '/finish';
const start = root + '/start';
const check = root + '/check';
const review = root + '/review.pdf';
const download = root + '/download.pdf';
const app = root + '/app';
const flutterWebOrigin = 'http://localhost:8000';
const cookieName = 'uaepass_signing_session';
const authLifetime = 10 * 60;
const sessionLifetime = 60 * 60;
const loginCancellationErrors = new Set(['invalid_request', 'login_required', 'access_denied', 'cancelledOnApp']);
const terminalMessages = {
  canceled: 'Signing was canceled.',
  failed: 'UAE PASS did not produce a signed PDF.',
  'signature-unverified': 'The signed PDF did not pass signature verification.',
  'signer-unverified': 'The verified signature could not be matched to the signed-in account.',
};
const document = {
  filename: 'staging-test.pdf',
  signatureField: {
    name: 'Sign1',
    location: { page: 'last', rectangle: { x: 72, y: 72, width: 320, height: 96 } },
    appearance: UaePassSignatureAppearance.SignerAndDateTime,
  },
};

const nonce = () => randomBytes(24).toString('base64url');

function singleQuery(url, name) {
  const values = url.searchParams.getAll(name);
  return values.length === 1 && values[0] ? values[0] : undefined;
}

function matchingState(expected, incoming) {
  return typeof expected === 'string' && typeof incoming === 'string' &&
    /^[A-Za-z0-9_-]{32}$/.test(incoming) &&
    timingSafeEqual(Buffer.from(expected), Buffer.from(incoming));
}

function setSession(response, id, lifetime) {
  response.setHeader('Set-Cookie',
    cookieName + '=' + id + '; Path=' + root + '; HttpOnly; SameSite=Lax; Max-Age=' + lifetime);
}

function signingProfile({ uuid, idn, userType }) {
  return { uuid, idn, userType };
}

function eligible(profile, level = UaePassSignatureLevel.Qualified) {
  const eligibleType = profile?.userType === 'SOP3' ||
    (level === UaePassSignatureLevel.Advanced && profile?.userType === 'SOP2');
  return eligibleType && typeof profile.uuid === 'string' &&
    profile.uuid.trim() !== '' && normalizeSignerIdn(profile.idn) !== undefined;
}

function redirect(response, location) {
  response.writeHead(303, { Location: location }).end();
}

function exchangeReply(response, status) {
  json(response, status, { ok: status === 200 });
}

function json(response, status, payload) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  }).end(JSON.stringify(payload));
}

async function readCode(request) {
  request.setEncoding('utf8');
  let body = '';
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    body += chunk;
    if (Buffer.byteLength(body) > 4096) {
      request.resume();
      return null;
    }
  }
  try {
    const input = JSON.parse(body);
    return typeof input?.code === 'string' && input.code.trim() ? input.code : null;
  } catch {
    return null;
  }
}

async function exchangeCode(request, response, exchangeClient) {
  if (request.headers.host !== loopbackHost + ':' + request.socket.localPort) {
    return exchangeReply(response, 403);
  }
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return exchangeReply(response, 405);
  }
  const contentType = request.headers['content-type']?.split(';')[0].trim().toLowerCase();
  if (contentType !== 'application/json') return exchangeReply(response, 415);

  try {
    const code = await readCode(request);
    if (!code) return exchangeReply(response, 400);
    await exchangeClient.getUserInfoFromCode(code);
    exchangeReply(response, 200);
  } catch (error) {
    if (response.destroyed) return;
    if (error instanceof UaePassError) {
      if (error.code === 'invalid_grant') return exchangeReply(response, 400);
      if (error.code === 'timeout') return exchangeReply(response, 504);
    }
    exchangeReply(response, 502);
  }
}

function page(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' }).end(
    '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>UAE PASS staging signing</title><style>' +
    'body{background:#f3f6f4;color:#152924;font:1rem/1.6 system-ui,sans-serif;margin:0}' +
    'main{background:white;max-width:48rem;margin:clamp(1rem,5vw,4rem) auto;padding:clamp(1rem,5vw,3rem);border:1px solid #d7e3dd;border-radius:1rem}' +
    'h1{line-height:1.2;margin:0 0 .75rem}a{color:#0b624b}iframe{width:100%;height:25rem;border:1px solid #d7e3dd;border-radius:.5rem}' +
    'button{border:0;border-radius:.5rem;padding:.7rem 1.1rem;background:#075945;color:white;font:inherit;font-weight:600;cursor:pointer}' +
    'form{margin-top:1rem}:focus-visible{outline:3px solid #337ca0;outline-offset:3px}</style>' +
    '<main><h1>UAE PASS staging signing</h1>' + body + '</main></html>');
}

function pdfResponse(response, pdf, disposition, filename) {
  response.writeHead(200, {
    'Content-Type': 'application/pdf',
    'Content-Length': pdf.byteLength,
    'Content-Disposition': disposition + '; filename="' + filename + '"',
  }).end(pdf);
}

function form(route, label) {
  return '<form method="post" action="' + route + '"><button>' + label + '</button></form>';
}

function home(response, session, notice) {
  if (!session?.profile) {
    const message = notice === 'canceled' ? '<p role="status">Sign-in was canceled.</p>' :
      notice === 'error' ? '<p role="status">UAE PASS sign-in could not be completed.</p>' : '';
    return page(response, 200, message + '<p>Sign in to review a synthetic PDF and test qualified signing.</p>' +
      form(login, 'Sign in with UAE PASS'));
  }
  if (!eligible(session.profile)) {
    const message = session.profile.userType === 'SOP2'
      ? 'Your UAE PASS signature is not qualified. Follow the steps in the UAE PASS app to upgrade your account.'
      : 'This account is ineligible. Use an SOP3 staging account with a verified Emirates ID and a qualified certificate.';
    return page(response, 200, '<p>' + message + '</p>' + form(login, 'Sign in again'));
  }
  const job = session.job;
  if (!job) {
    return page(response, 200, '<p>Review the synthetic PDF before continuing to UAE PASS.</p>' +
      '<iframe title="Synthetic PDF for review" src="' + review + '"></iframe>' +
      '<p><a href="' + review + '">Open the sample PDF</a></p>' + form(start, 'Sign with UAE PASS'));
  }
  if (job.state === 'signed') {
    const cleanup = job.cleanupPending ?
      '<p>UAE PASS cleanup is pending.</p>' + form(check, 'Retry cleanup') : '';
    return page(response, 200, '<p role="status">Signed PDF verified.</p><p><a href="' + download +
      '">Download the signed PDF</a></p>' + cleanup + form(login, 'Start a new signing session'));
  }
  if (Object.hasOwn(terminalMessages, job.state)) {
    return page(response, 200, '<p role="status">' + terminalMessages[job.state] + '</p>' +
      (job.state === 'canceled' ? form(start, 'Start again') : form(login, 'Start a new signing session')));
  }
  if (job.state === 'start-failed') {
    return page(response, 200, '<p role="status">UAE PASS is unavailable. Signing has yet to start.</p>' +
      form(start, 'Try again'));
  }
  if (job.state === 'start-uncertain') {
    return page(response, 200, '<p role="status">The signing request could not be confirmed. Reconcile it with UAE PASS before starting again.</p>');
  }
  if (!job.process) return page(response, 200, '<p role="status">Starting the signing request.</p>');
  const message = job.finalizationFailed ? 'The signed PDF could not be verified. Check the result again.' :
    job.resultUnavailable ? 'The signing result is unavailable. Check again after approval.' :
    'Complete or cancel the hosted signing request, then check its result.';
  return page(response, 200, '<p role="status">' + message + '</p>' +
    (job.state === 'awaiting' ? form(start, 'Return to UAE PASS') : '') + form(check, 'Check signing result'));
}

async function writeSignedPdf(directory, pdf) {
  const path = join(directory, nonce() + '.pdf');
  const file = await open(path, 'wx', 0o600);
  try {
    try {
      await file.writeFile(pdf);
      await file.sync();
    } finally {
      await file.close();
    }
    return path;
  } catch (error) {
    await rm(path, { force: true }).catch(() => {});
    throw error;
  }
}

export async function createExampleServer({
  authClient, exchangeClient, signingClient, validationClient, clientId, origin = defaultOrigin,
}) {
  const base = new URL(origin);
  if (base.protocol !== 'http:' || base.hostname !== 'localhost' || !base.port || base.origin !== origin) {
    throw new TypeError('Use an HTTP localhost origin with an explicit port for the staging demo.');
  }
  const pdf = await readFile(new URL('./staging-test.pdf', import.meta.url));
  const directory = await mkdtemp(join(tmpdir(), 'uaepass-demo-signing-'));
  const sessions = new Map();
  const appTransactions = new Map();
  const back = '<p><a href="' + root + '">Return to signing</a></p>';

  function discard(store, id, entry) {
    if (store.get(id) === entry) store.delete(id);
    if (entry.job?.pdfPath) void rm(entry.job.pdfPath, { force: true }).catch(() => {});
  }

  function expire(store, id, entry) {
    const job = entry.job;
    if (entry.authorization || job?.busy) return;
    if (!job?.cleanupPending) return discard(store, id, entry);
    // Make one last attempt to remove the provider copy of a verified, stored PDF.
    job.busy = true;
    void cleanup(job).finally(() => discard(store, id, entry));
  }

  const sweep = setInterval(() => {
    for (const store of [sessions, appTransactions]) {
      for (const id of store.keys()) liveEntry(store, id);
    }
  }, 60_000).unref();

  async function getToken(job) {
    if (!job.token || Date.now() >= job.token.validUntil) {
      const { accessToken, expiresInSeconds } = await signingClient.getAccessToken();
      job.token = { accessToken, validUntil: Date.now() + Math.max(0, expiresInSeconds - 15) * 1000 };
    }
    return job.token.accessToken;
  }

  async function withSigningToken(job, action) {
    try {
      return await action(await getToken(job));
    } catch (error) {
      if (error?.code !== 'invalid_token') throw error;
      job.token = undefined;
      return action(await getToken(job));
    }
  }

  async function cleanup(job) {
    try {
      await withSigningToken(job, (token) => signingClient.deleteProcess(job.process.processId, token));
    } catch (error) {
      // A previous attempt may have succeeded before the response was lost.
      if (error?.status !== 404) return;
    }
    job.cleanupPending = false;
    job.token = undefined;
  }

  async function complete(session) {
    const job = session?.job;
    if (!job?.process || job.busy) return;
    job.busy = true;
    const { processId, documentId } = job.process;
    try {
      if (job.state === 'awaiting') {
        let result;
        try {
          result = await withSigningToken(job, (token) => signingClient.getProcessResult(processId, token));
        } catch {
          job.resultUnavailable = true;
          return;
        }
        job.resultUnavailable = false;
        if (result.status !== 'finished') {
          job.state = result.status === 'canceled' ? 'canceled' : 'failed';
          job.token = undefined;
          return;
        }
        job.state = 'approved';
      }
      if (job.state === 'approved') {
        try {
          const signed = await withSigningToken(job, (token) => signingClient.downloadSignedPdf(documentId, token));
          const expectedIdn = session.profile.idn;
          const { pdf: finalizedPdf } = await validationClient.finalizeSignedPdf(signed, {
            expectedSignatureFieldName: document.signatureField.name,
            matchSigner: (signerSubject) => matchesSignerIdn(signerSubject, expectedIdn),
          });
          job.pdfPath = await writeSignedPdf(directory, finalizedPdf);
          job.finalizationFailed = false;
          job.state = 'signed';
          job.cleanupPending = true;
        } catch (error) {
          if (error instanceof UaePassSigningValidationError &&
              (error.code === 'signer_unverified' || error.code === 'verification_failed')) {
            job.state = error.code === 'signer_unverified' ? 'signer-unverified' : 'signature-unverified';
            job.token = undefined;
          } else {
            job.finalizationFailed = true;
          }
          return;
        }
      }
      if (job.cleanupPending) await cleanup(job);
    } finally {
      job.busy = false;
    }
  }

  async function startSigning(session, surface, id = nonce()) {
    const current = session.job;
    if (current && current.state !== 'start-failed' && current.state !== 'canceled') return current;

    const job = { id, surface, state: 'starting', busy: true };
    session.job = job;
    try {
      let token;
      try {
        token = await getToken(job);
      } catch {
        job.state = 'start-failed';
        return job;
      }
      try {
        job.process = await signingClient.createProcess({
          ...document,
          pdf,
          ...(session.signatureLevel ? { signatureLevel: session.signatureLevel } : {}),
        }, token);
      } catch (error) {
        const rejectedBeforeCreation = error?.code === 'invalid_token' ||
          (error?.code === 'rejected' && [400, 403, 413, 415, 422].includes(error.status));
        job.state = rejectedBeforeCreation ? 'start-failed' : 'start-uncertain';
        return job;
      }
      job.state = 'awaiting';
      return job;
    } finally {
      job.busy = false;
    }
  }

  function appStatus(job) {
    switch (job.state) {
      case 'starting': return 'processing';
      case 'awaiting': return 'pending';
      case 'approved': return 'processing';
      case 'signed':
      case 'canceled': return job.state;
      default: return 'failed';
    }
  }

  function liveEntry(store, id) {
    const entry = store.get(id);
    if (entry?.expiresAt <= Date.now()) {
      expire(store, id, entry);
      return undefined;
    }
    return entry;
  }

  async function handleApp(request, response, url) {
    const loopback = loopbackHost + ':' + request.socket.localPort;
    if ((request.headers.host !== base.host && request.headers.host !== loopback) ||
        (request.headers.origin !== undefined && request.headers.origin !== flutterWebOrigin)) {
      return json(response, 403, { error: 'invalid_origin' });
    }
    const match = /^\/signing\/app\/transactions\/([A-Za-z0-9_-]{32})(?:\/(check|pdf))?$/.exec(url.pathname);
    if (!match) return json(response, 404, { error: 'unavailable' });
    const [, transactionId, action] = match;
    const token = /^Bearer ([A-Za-z0-9_-]{32})$/i.exec(request.headers.authorization)?.[1];
    if (!token) return json(response, 401, { error: 'missing_transaction_token' });
    const tokenHash = createHash('sha256').update(token).digest();
    const starting = request.method === 'PUT' && !action;
    const levels = starting ? url.searchParams.getAll('level') : [];
    const [requestedLevel] = levels;
    if (levels.length > 1 || (requestedLevel !== undefined &&
        !Object.values(UaePassSignatureLevel).includes(requestedLevel))) {
      return json(response, 400, { error: 'invalid_level' });
    }
    let code;
    if (starting && request.headers['content-type'] !== undefined) {
      const contentType = request.headers['content-type'].split(';')[0].trim().toLowerCase();
      if (contentType !== 'application/json') return json(response, 415, { error: 'invalid_authorization' });
      code = await readCode(request);
      if (!code) return json(response, 400, { error: 'invalid_authorization' });
    }
    let transaction = liveEntry(appTransactions, transactionId);
    if (transaction && !timingSafeEqual(transaction.tokenHash, tokenHash)) {
      return json(response, 404, { error: 'unavailable' });
    }
    if (starting) {
      const signatureLevel = transaction?.signatureLevel ?? requestedLevel ?? UaePassSignatureLevel.Qualified;
      if (requestedLevel !== undefined && requestedLevel !== signatureLevel) {
        return json(response, 409, { error: 'level_conflict' });
      }
      const surface = singleQuery(url, 'return') === 'web' ? 'web' : 'native';
      if (!transaction) {
        if (appTransactions.has(transactionId)) return json(response, 404, { error: 'unavailable' });
        if (!code) return json(response, 404, { error: 'authorization_required' });
        if (appTransactions.size >= 100) return json(response, 503, { error: 'unavailable' });
        transaction = { tokenHash, signatureLevel, surface, expiresAt: Date.now() + sessionLifetime * 1000 };
        appTransactions.set(transactionId, transaction);
        const entry = transaction;
        entry.authorization = (async () => {
          try {
            const profile = signingProfile(await exchangeClient.getUserInfoFromCode(code));
            if (eligible(profile, signatureLevel)) entry.profile = profile;
            else entry.authorizationFailed = 'ineligible';
          } catch {
            entry.authorizationFailed = 'invalid_authorization';
          }
        })().finally(() => { delete entry.authorization; });
      }
      if (surface !== transaction.surface) return json(response, 409, { error: 'surface_conflict' });
      await transaction.authorization;
      if (transaction.authorizationFailed) {
        const error = transaction.authorizationFailed;
        return json(response, error === 'ineligible' ? 403 : 400, { error });
      }
      if (transaction.job?.state !== 'canceled') {
        transaction.starting ??= startSigning(transaction, surface, transactionId)
          .finally(() => { delete transaction.starting; });
        await transaction.starting;
      }
      const job = transaction.job;
      if (['start-failed', 'start-uncertain'].includes(job.state)) {
        return json(response, 502, { error: job.state });
      }
      return json(response, 200, {
        transactionId: job.id,
        status: appStatus(job),
        signatureLevel,
        ...(job.state === 'awaiting' ? {
          approvalUri: job.process.approvalUrl,
          finishCallbackUri: origin + finish,
        } : {}),
      });
    }
    if (!transaction) return json(response, 404, { error: 'unavailable' });
    const job = transaction?.job;
    if (job && request.method === 'POST' && action === 'check') {
      await complete(transaction);
      return json(response, 200, { status: appStatus(job), signatureLevel: transaction.signatureLevel });
    }
    if (job?.state === 'signed' && request.method === 'GET' && action === 'pdf') {
      const verified = await readFile(job.pdfPath);
      return pdfResponse(response, verified, 'attachment', 'signed-staging-test.pdf');
    }
    return json(response, 404, { error: 'unavailable' });
  }

  const server = createServer(async (request, response) => {
    if (request.url === exchange) {
      return exchangeCode(request, response, exchangeClient);
    }

    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; frame-src 'self'; frame-ancestors 'self'; " +
      "form-action 'self' https://stg-id.uaepass.ae https://stg-ids.uaepass.ae https://stg.uaepass.ae; base-uri 'none'");
    try {
      const url = new URL(request.url, origin);
      if (url.origin !== origin) return response.writeHead(403).end();
      if (url.pathname.startsWith(app + '/')) {
        return await handleApp(request, response, url);
      }
      if (request.headers.host !== base.host ||
          (request.method === 'POST' && request.headers.origin !== origin)) {
        return response.writeHead(403).end();
      }
      const id = request.headers.cookie?.match(/(?:^|;\s*)uaepass_signing_session=([A-Za-z0-9_-]{32})(?:;|$)/)?.[1];
      const session = liveEntry(sessions, id);
      const route = request.method + ' ' + url.pathname;
      if (route === 'GET /') return redirect(response, root);
      if (route === 'GET ' + root) {
        // Form POSTs need the browser's same-origin Origin header.
        response.setHeader('Referrer-Policy', 'same-origin');
        return home(response, session, singleQuery(url, 'notice'));
      }
      if (route === 'POST ' + login) {
        if (session?.job?.busy || session?.job?.cleanupPending ||
            ['awaiting', 'approved', 'start-uncertain'].includes(session?.job?.state)) {
          return redirect(response, root);
        }
        if (session) discard(sessions, id, session);
        if (sessions.size >= 100) return page(response, 503, '<p>Too many staging sessions. Try again later.</p>');
        const newId = nonce();
        const state = nonce();
        sessions.set(newId, { state, expiresAt: Date.now() + authLifetime * 1000 });
        setSession(response, newId, authLifetime);
        const authorize = new URL('/idshub/authorize', stagingOrigin);
        authorize.search = new URLSearchParams({
          client_id: clientId, redirect_uri: origin + callback, response_type: 'code',
          scope: 'urn:uae:digitalid:profile:general', state, ui_locales: 'en',
          acr_values: 'urn:safelayer:tws:policies:authentication:level:low',
        });
        return redirect(response, authorize.href);
      }
      if (route === 'GET ' + callback) {
        if (!matchingState(session?.state, singleQuery(url, 'state'))) {
          return page(response, 403, '<p>Sign-in could not be correlated.</p>' + back);
        }
        const code = singleQuery(url, 'code');
        if (!code || url.searchParams.has('error')) {
          sessions.delete(id);
          const cancellation = !url.searchParams.has('code') && loginCancellationErrors.has(singleQuery(url, 'error'));
          return redirect(response, root + (cancellation ? '?notice=canceled' : '?notice=error'));
        }
        // Consume the state while keeping this session identifiable during the exchange.
        delete session.state;
        let profile;
        try {
          profile = await authClient.getUserInfoFromCode(code);
        } catch {
          profile = undefined;
        }
        if (sessions.get(id) !== session) return redirect(response, root);
        sessions.delete(id);
        if (!profile || session.expiresAt <= Date.now()) {
          return redirect(response, root + '?notice=error');
        }
        const newId = nonce();
        const signer = signingProfile(profile);
        sessions.set(newId, { profile: signer, expiresAt: Date.now() + sessionLifetime * 1000 });
        setSession(response, newId, sessionLifetime);
        return redirect(response, root);
      }
      if (route === 'GET ' + review && eligible(session?.profile)) {
        return pdfResponse(response, pdf, 'inline', document.filename);
      }
      if (route === 'POST ' + start && eligible(session?.profile)) {
        const job = await startSigning(session, 'browser');
        return redirect(response, job.state === 'awaiting' && !job.busy ? job.process.approvalUrl : root);
      }
      if (route === 'GET ' + finish) {
        const processId = singleQuery(url, 'signer_process_id');
        const appTransaction = processId && [...appTransactions.values()].find((candidate) =>
          candidate.expiresAt > Date.now() &&
          candidate.job?.surface === 'web' && candidate.job.process?.processId === processId);
        if (appTransaction) {
          return redirect(response, flutterWebOrigin + '/?signing=return&transaction=' + appTransaction.job.id);
        }
        if (!session?.job?.process || session.job.process.processId !== processId) {
          return page(response, 403, '<p>The signing return could not be correlated.</p>' + back);
        }
        await complete(session);
        return redirect(response, root);
      }
      if (route === 'POST ' + check && session?.job?.process) {
        await complete(session);
        return redirect(response, root);
      }
      if (route === 'GET ' + download && session?.job?.state === 'signed') {
        const verified = await readFile(session.job.pdfPath);
        return pdfResponse(response, verified, 'attachment', 'signed-staging-test.pdf');
      }
      return page(response, 404, '<p>This signing page is unavailable.</p>' + back);
    } catch {
      if (!response.headersSent && !response.destroyed) {
        return page(response, 502, '<p>The local signing demo could not complete the request.</p>' + back);
      }
      response.end();
    }
  });
  server.once('close', () => {
    clearInterval(sweep);
    void rm(directory, { recursive: true, force: true }).catch(() => {});
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.env;
  const redirectUri = defaultOrigin + callback;
  const finishCallbackUrl = defaultOrigin + finish;
  const authConfig = {
    environment: 'staging',
    clientId: env.UAEPASS_CLIENT_ID,
    clientSecret: env.UAEPASS_CLIENT_SECRET,
  };
  const signingCredentials = {
    clientId: env.UAEPASS_SIGNING_CLIENT_ID,
    clientSecret: env.UAEPASS_SIGNING_CLIENT_SECRET,
  };
  const server = await createExampleServer({
    clientId: authConfig.clientId,
    authClient: createUaePassClient({ ...authConfig, redirectUri }),
    exchangeClient: createUaePassClient({ ...authConfig, redirectUri: env.UAEPASS_REDIRECT_URI }),
    signingClient: createUaePassSigningClient({ environment: 'staging', ...signingCredentials, finishCallbackUrl }),
    validationClient: createUaePassSigningValidationClient({ environment: 'staging', ...signingCredentials }),
  });
  function stop() { server.close(); }
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  server.listen(port, loopbackHost, () => console.log('UAE PASS staging demo at ' + defaultOrigin + root));
}
