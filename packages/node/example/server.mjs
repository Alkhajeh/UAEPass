import { Buffer } from 'node:buffer';
import { randomBytes, timingSafeEqual } from 'node:crypto';
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
  signatureField: { name: 'Sign1', page: 'last', rectangle: { x: 72, y: 72, width: 320, height: 96 } },
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

function eligible(profile) {
  return profile?.userType === 'SOP3' && typeof profile.uuid === 'string' &&
    profile.uuid.trim() !== '' && normalizeSignerIdn(profile.idn) !== undefined;
}

function redirect(response, location) {
  response.writeHead(303, { Location: location }).end();
}

function exchangeReply(response, status) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  }).end(JSON.stringify({ ok: status === 200 }));
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
      form(login, 'Start a new signing session'));
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
  const back = '<p><a href="' + root + '">Return to signing</a></p>';

  function discard(id, session) {
    sessions.delete(id);
    if (session.job?.pdfPath) void rm(session.job.pdfPath, { force: true }).catch(() => {});
  }

  function expireSession(id, session) {
    const job = session.job;
    if (job?.busy) return;
    if (!job?.cleanupPending) return discard(id, session);
    // Make one last attempt to remove the provider copy of a verified, stored PDF.
    job.busy = true;
    void cleanup(job).finally(() => discard(id, session));
  }

  const sweep = setInterval(() => {
    for (const [id, session] of sessions) {
      if (session.expiresAt <= Date.now()) expireSession(id, session);
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

  const server = createServer(async (request, response) => {
    if (request.url === exchange) return exchangeCode(request, response, exchangeClient);

    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; frame-src 'self'; frame-ancestors 'self'; " +
      "form-action 'self' https://stg-id.uaepass.ae https://stg-ids.uaepass.ae https://stg.uaepass.ae; base-uri 'none'");
    if (request.headers.host !== base.host ||
      (request.method === 'POST' && request.headers.origin !== origin)) {
      return response.writeHead(403).end();
    }
    try {
      const url = new URL(request.url, origin);
      if (url.origin !== origin) return response.writeHead(403).end();
      const id = request.headers.cookie?.match(/(?:^|;\s*)uaepass_signing_session=([A-Za-z0-9_-]{32})(?:;|$)/)?.[1];
      let session = sessions.get(id);
      if (session?.expiresAt <= Date.now()) {
        expireSession(id, session);
        session = undefined;
      }
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
        if (session) discard(id, session);
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
        const signer = { uuid: profile.uuid, idn: profile.idn, userType: profile.userType };
        sessions.set(newId, { profile: signer, expiresAt: Date.now() + sessionLifetime * 1000 });
        setSession(response, newId, sessionLifetime);
        return redirect(response, root);
      }
      if (route === 'GET ' + review && eligible(session?.profile)) {
        return pdfResponse(response, pdf, 'inline', document.filename);
      }
      if (route === 'POST ' + start && eligible(session?.profile)) {
        const current = session.job;
        if (current?.busy) return redirect(response, root);
        if (current?.state === 'awaiting') return redirect(response, current.process.approvalUrl);
        if (current && current.state !== 'start-failed') return redirect(response, root);
        const job = { state: 'starting', busy: true };
        session.job = job;
        try {
          let token;
          try {
            token = await getToken(job);
          } catch {
            job.state = 'start-failed';
            return redirect(response, root);
          }
          try {
            job.process = await signingClient.createProcess({ ...document, pdf }, token);
          } catch (error) {
            const rejectedBeforeCreation = error?.code === 'invalid_token' ||
              (error?.code === 'rejected' && [400, 403, 413, 415, 422].includes(error.status));
            job.state = rejectedBeforeCreation ? 'start-failed' : 'start-uncertain';
            return redirect(response, root);
          }
          job.state = 'awaiting';
          return redirect(response, job.process.approvalUrl);
        } finally {
          job.busy = false;
        }
      }
      if (route === 'GET ' + finish) {
        if (!session?.job?.process || session.job.process.processId !== singleQuery(url, 'signer_process_id')) {
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
