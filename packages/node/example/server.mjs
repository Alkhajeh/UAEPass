import { createHash, timingSafeEqual } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { UaePassError, UaePassSignatureLevel } from '@alkhajeh/uaepass-server';
import {
  authLifetimeSeconds, defaultOrigin, flutterWebOrigin, loginCancellationErrors, loopbackHost, maxEntries,
  routes, sampleDocument, sessionLifetimeSeconds, signedFilename, stagingOrigin, sweepIntervalMs,
} from './config.mjs';
import {
  json, matchingNonce, mediaType, nonce, pdfResponse, readCode, readSessionId, redirect,
  setPageSecurityHeaders, setSessionCookie, singleQuery,
} from './http.mjs';
import { appStatus, createSigningJobs, eligible, signingProfile } from './signing-jobs.mjs';
import { ExpiringStore } from './store.mjs';
import { backLink, homePage, html, page } from './views.mjs';

const appTransactionPath = /^\/signing\/app\/transactions\/([A-Za-z0-9_-]{32})(?:\/(check|pdf))?$/;
const bearerToken = /^Bearer ([A-Za-z0-9_-]{32})$/i;
const signatureLevels = new Set(Object.values(UaePassSignatureLevel));

/**
 * Creates the staging demo server. It is not listening yet; call `listen()` on the result.
 *
 * @param {object} options
 * @param {{ getUserInfoFromCode(code: string): Promise<object> }} options.authClient
 *   Exchanges codes from the browser demo's own sign-in.
 * @param {{ getUserInfoFromCode(code: string): Promise<object> }} options.exchangeClient
 *   Exchanges codes sent by the Flutter example, using the Flutter redirect URI.
 * @param {object} options.signingClient From `createUaePassSigningClient()`.
 * @param {object} options.validationClient From `createUaePassSigningValidationClient()`.
 * @param {string} options.clientId The public client ID used to start browser sign-in.
 * @param {string} [options.origin] The browser origin, `http://localhost:<port>`.
 * @param {(error: unknown, context: string) => void} [options.onError]
 *   Called with unexpected failures. Log only sanitized fields, never codes or tokens.
 */
export async function createExampleServer({
  authClient, exchangeClient, signingClient, validationClient, clientId, origin = defaultOrigin,
  onError = () => {},
}) {
  const base = new URL(origin);
  if (base.protocol !== 'http:' || base.hostname !== 'localhost' || !base.port || base.origin !== origin) {
    throw new TypeError('Use an HTTP localhost origin with an explicit port for the staging demo.');
  }
  const pdf = await readFile(new URL('./staging-test.pdf', import.meta.url));
  const directory = await mkdtemp(join(tmpdir(), 'uaepass-demo-signing-'));
  const jobs = createSigningJobs({ signingClient, validationClient, pdf, directory });
  const sessions = new ExpiringStore({ cleanup: jobs.cleanup });
  const appTransactions = new ExpiringStore({ cleanup: jobs.cleanup });

  const sweep = setInterval(() => {
    sessions.sweep();
    appTransactions.sweep();
  }, sweepIntervalMs).unref();

  const loopbackAuthority = (request) => loopbackHost + ':' + request.socket.localPort;

  // POST /auth/uaepass — the Flutter example's code exchange. Replies with a success flag only.
  async function handleExchange(request, response) {
    const reply = (status) => json(response, status, { ok: status === 200 });
    if (request.headers.host !== loopbackAuthority(request)) return reply(403);
    if (request.method !== 'POST') {
      response.setHeader('Allow', 'POST');
      return reply(405);
    }
    if (mediaType(request) !== 'application/json') return reply(415);

    try {
      const code = await readCode(request);
      if (!code) return reply(400);
      await exchangeClient.getUserInfoFromCode(code);
      reply(200);
    } catch (error) {
      if (response.destroyed) return;
      onError(error, 'exchange');
      if (error instanceof UaePassError) {
        if (error.code === 'invalid_grant') return reply(400);
        if (error.code === 'timeout') return reply(504);
      }
      reply(502);
    }
  }

  // Exchanges the transaction's one-time code in the background and records the signer.
  function authorizeTransaction(transaction, code) {
    transaction.authorization = (async () => {
      try {
        const profile = signingProfile(await exchangeClient.getUserInfoFromCode(code));
        if (eligible(profile, transaction.signatureLevel)) transaction.profile = profile;
        else transaction.authorizationFailed = 'ineligible';
      } catch (error) {
        onError(error, 'app-authorization');
        transaction.authorizationFailed = 'invalid_authorization';
      }
    })().finally(() => { delete transaction.authorization; });
  }

  // PUT /signing/app/transactions/:id — create or resume a Flutter signing transaction.
  async function startAppTransaction(request, response, url, transactionId, tokenHash) {
    const levels = url.searchParams.getAll('level');
    const [requestedLevel] = levels;
    if (levels.length > 1 || (requestedLevel !== undefined && !signatureLevels.has(requestedLevel))) {
      return json(response, 400, { error: 'invalid_level' });
    }
    const locales = url.searchParams.getAll('locale');
    const [requestedLocale] = locales;
    if (locales.length > 1 || (requestedLocale !== undefined && requestedLocale !== 'en' && requestedLocale !== 'ar')) {
      return json(response, 400, { error: 'invalid_locale' });
    }
    let code;
    if (request.headers['content-type'] !== undefined) {
      if (mediaType(request) !== 'application/json') return json(response, 415, { error: 'invalid_authorization' });
      code = await readCode(request);
      if (!code) return json(response, 400, { error: 'invalid_authorization' });
    }
    let transaction = appTransactions.get(transactionId);
    if (transaction && !timingSafeEqual(transaction.tokenHash, tokenHash)) {
      return json(response, 404, { error: 'unavailable' });
    }
    const signatureLevel = transaction?.signatureLevel ?? requestedLevel ?? UaePassSignatureLevel.Qualified;
    if (requestedLevel !== undefined && requestedLevel !== signatureLevel) {
      return json(response, 409, { error: 'level_conflict' });
    }
    const locale = transaction?.locale ?? requestedLocale ?? 'en';
    if (requestedLocale !== undefined && requestedLocale !== locale) {
      return json(response, 409, { error: 'locale_conflict' });
    }
    const surface = singleQuery(url, 'return') === 'web' ? 'web' : 'native';
    if (!transaction) {
      // An expired ID stays reserved until its final cleanup completes.
      if (appTransactions.has(transactionId)) return json(response, 404, { error: 'unavailable' });
      if (!code) return json(response, 404, { error: 'authorization_required' });
      if (appTransactions.size >= maxEntries) return json(response, 503, { error: 'unavailable' });
      transaction = { tokenHash, signatureLevel, locale, surface, expiresAt: Date.now() + sessionLifetimeSeconds * 1000 };
      appTransactions.set(transactionId, transaction);
      authorizeTransaction(transaction, code);
    }
    if (surface !== transaction.surface) return json(response, 409, { error: 'surface_conflict' });
    await transaction.authorization;
    if (transaction.authorizationFailed) {
      const error = transaction.authorizationFailed;
      return json(response, error === 'ineligible' ? 403 : 400, { error });
    }
    if (transaction.job?.state !== 'canceled') {
      transaction.starting ??= jobs.start(transaction, surface, transactionId)
        .finally(() => { delete transaction.starting; });
      await transaction.starting;
    }
    const job = transaction.job;
    if (job.state === 'start-failed' || job.state === 'start-uncertain') {
      return json(response, 502, { error: job.state });
    }
    return json(response, 200, {
      transactionId: job.id,
      status: appStatus(job),
      signatureLevel,
      ...(job.state === 'awaiting' ? {
        approvalUri: job.process.approvalUrl,
        finishCallbackUri: origin + routes.finish,
      } : {}),
    });
  }

  // /signing/app/transactions/:id[/check|/pdf] — the Flutter example's signing API.
  async function handleApp(request, response, url) {
    if ((request.headers.host !== base.host && request.headers.host !== loopbackAuthority(request)) ||
        (request.headers.origin !== undefined && request.headers.origin !== flutterWebOrigin)) {
      return json(response, 403, { error: 'invalid_origin' });
    }
    const match = appTransactionPath.exec(url.pathname);
    if (!match) return json(response, 404, { error: 'unavailable' });
    const [, transactionId, action] = match;
    const token = bearerToken.exec(request.headers.authorization)?.[1];
    if (!token) return json(response, 401, { error: 'missing_transaction_token' });
    const tokenHash = createHash('sha256').update(token).digest();

    if (request.method === 'PUT' && !action) {
      return startAppTransaction(request, response, url, transactionId, tokenHash);
    }
    const transaction = appTransactions.get(transactionId);
    if (!transaction || !timingSafeEqual(transaction.tokenHash, tokenHash)) {
      return json(response, 404, { error: 'unavailable' });
    }
    const job = transaction.job;
    if (job && request.method === 'POST' && action === 'check') {
      await jobs.complete(transaction);
      return json(response, 200, { status: appStatus(job), signatureLevel: transaction.signatureLevel });
    }
    if (job?.state === 'signed' && request.method === 'GET' && action === 'pdf') {
      return pdfResponse(response, await readFile(job.pdfPath), 'attachment', signedFilename);
    }
    return json(response, 404, { error: 'unavailable' });
  }

  const notFound = ({ response }) => page(response, 404, html`<p>This signing page is unavailable.</p>${backLink}`);

  // Browser demo routes, keyed by "METHOD path". Each receives { request, response, url, id, session }.
  const browserRoutes = new Map([
    ['GET /', ({ response }) => redirect(response, routes.root)],

    ['GET ' + routes.root, ({ response, url, session }) => {
      // Form POSTs need the browser's same-origin Origin header.
      response.setHeader('Referrer-Policy', 'same-origin');
      const locale = session?.profile ? session.locale : singleQuery(url, 'locale');
      return homePage(response, session, singleQuery(url, 'notice'), locale === 'ar' ? 'ar' : 'en');
    }],

    ['POST ' + routes.login, ({ response, url, id, session }) => {
      const job = session?.job;
      if (job?.busy || job?.cleanupPending || ['awaiting', 'approved', 'start-uncertain'].includes(job?.state)) {
        return redirect(response, routes.root);
      }
      if (session) sessions.discard(id, session);
      if (sessions.size >= maxEntries) return page(response, 503, html`<p>Too many staging sessions. Try again later.</p>`);
      const newId = nonce();
      const state = nonce();
      const locale = (singleQuery(url, 'locale') ?? (session?.profile ? session.locale : undefined)) === 'ar' ? 'ar' : 'en';
      sessions.set(newId, { state, locale, expiresAt: Date.now() + authLifetimeSeconds * 1000 });
      setSessionCookie(response, newId, authLifetimeSeconds);
      const authorize = new URL('/idshub/authorize', stagingOrigin);
      authorize.search = new URLSearchParams({
        client_id: clientId, redirect_uri: origin + routes.callback, response_type: 'code',
        scope: 'urn:uae:digitalid:profile:general', state, ui_locales: locale,
        acr_values: 'urn:safelayer:tws:policies:authentication:level:low',
      });
      return redirect(response, authorize.href);
    }],

    ['GET ' + routes.callback, async ({ response, url, id, session }) => {
      if (!matchingNonce(session?.state, singleQuery(url, 'state'))) {
        return page(response, 403, html`<p>Sign-in could not be correlated.</p>${backLink}`);
      }
      const { locale } = session;
      const noticeUrl = (notice) => `${routes.root}?${locale === 'ar' ? 'locale=ar&' : ''}notice=${notice}`;
      const code = singleQuery(url, 'code');
      if (!code || url.searchParams.has('error')) {
        sessions.delete(id);
        const cancellation = !url.searchParams.has('code') && loginCancellationErrors.has(singleQuery(url, 'error'));
        return redirect(response, noticeUrl(cancellation ? 'canceled' : 'error'));
      }
      // Consume the state while keeping this session identifiable during the exchange.
      delete session.state;
      let profile;
      try {
        profile = await authClient.getUserInfoFromCode(code);
      } catch (error) {
        onError(error, 'browser-authorization');
      }
      // A newer sign-in replaced this session while the exchange was in flight.
      if (sessions.get(id) !== session) return redirect(response, routes.root);
      sessions.delete(id);
      if (!profile || session.expiresAt <= Date.now()) return redirect(response, noticeUrl('error'));
      const newId = nonce();
      sessions.set(newId, { profile: signingProfile(profile), locale, expiresAt: Date.now() + sessionLifetimeSeconds * 1000 });
      setSessionCookie(response, newId, sessionLifetimeSeconds);
      return redirect(response, routes.root);
    }],

    ['GET ' + routes.review, (context) => {
      if (!eligible(context.session?.profile)) return notFound(context);
      return pdfResponse(context.response, pdf, 'inline', sampleDocument.filename);
    }],

    ['POST ' + routes.start, async (context) => {
      if (!eligible(context.session?.profile)) return notFound(context);
      const job = await jobs.start(context.session, 'browser');
      return redirect(context.response, job.state === 'awaiting' && !job.busy ? job.process.approvalUrl : routes.root);
    }],

    ['GET ' + routes.finish, async ({ response, url, session }) => {
      const processId = singleQuery(url, 'signer_process_id');
      const appTransaction = processId && appTransactions.find((candidate) =>
        candidate.job?.surface === 'web' && candidate.job.process?.processId === processId);
      if (appTransaction) {
        return redirect(response, flutterWebOrigin + '/?signing=return&transaction=' + appTransaction.job.id);
      }
      if (!session?.job?.process || session.job.process.processId !== processId) {
        return page(response, 403, html`<p>The signing return could not be correlated.</p>${backLink}`);
      }
      await jobs.complete(session);
      return redirect(response, routes.root);
    }],

    ['POST ' + routes.check, async (context) => {
      if (!context.session?.job?.process) return notFound(context);
      await jobs.complete(context.session);
      return redirect(context.response, routes.root);
    }],

    ['GET ' + routes.download, async (context) => {
      const job = context.session?.job;
      if (job?.state !== 'signed') return notFound(context);
      return pdfResponse(context.response, await readFile(job.pdfPath), 'attachment', signedFilename);
    }],
  ]);

  const server = createServer(async (request, response) => {
    if (request.url === routes.exchange) return handleExchange(request, response);

    setPageSecurityHeaders(response);
    try {
      const url = new URL(request.url, origin);
      if (url.origin !== origin) return response.writeHead(403).end();
      if (url.pathname.startsWith(routes.app + '/')) return await handleApp(request, response, url);
      if (request.headers.host !== base.host || (request.method === 'POST' && request.headers.origin !== origin)) {
        return response.writeHead(403).end();
      }
      const id = readSessionId(request);
      const context = { request, response, url, id, session: sessions.get(id) };
      const handler = browserRoutes.get(request.method + ' ' + url.pathname) ?? notFound;
      return await handler(context);
    } catch (error) {
      onError(error, 'request');
      if (!response.headersSent && !response.destroyed) {
        return page(response, 502, html`<p>The local signing demo could not complete the request.</p>${backLink}`);
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
