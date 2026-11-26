import { UaePassSignatureAppearance } from '@alkhajeh/uaepass-server';

// Network
export const stagingOrigin = 'https://stg-id.uaepass.ae';
export const loopbackHost = '127.0.0.1';
export const port = 8787;
export const defaultOrigin = 'http://localhost:' + port;
export const flutterWebOrigin = 'http://localhost:8000';

// Routes
export const routes = Object.freeze({
  exchange: '/auth/uaepass',
  root: '/signing',
  login: '/signing/login',
  callback: '/signing/auth/callback',
  finish: '/signing/finish',
  start: '/signing/start',
  check: '/signing/check',
  review: '/signing/review.pdf',
  download: '/signing/download.pdf',
  app: '/signing/app',
});

// Sessions
export const cookieName = 'uaepass_signing_session';
export const authLifetimeSeconds = 10 * 60;
export const sessionLifetimeSeconds = 60 * 60;
export const maxEntries = 100;
export const sweepIntervalMs = 60_000;
export const maxJsonBodyBytes = 4096;

// OAuth errors that UAE PASS documents as a user cancellation.
export const loginCancellationErrors = new Set(['invalid_request', 'login_required', 'access_denied', 'cancelledOnApp']);

// The synthetic PDF and signature box used by the demo, passed as-is to createProcess().
export const signedFilename = 'signed-staging-test.pdf';
export const sampleDocument = Object.freeze({
  filename: 'staging-test.pdf',
  signatureField: {
    name: 'Sign1',
    location: { page: 'last', rectangle: { x: 72, y: 72, width: 320, height: 96 } },
    appearance: UaePassSignatureAppearance.SignerAndDateTime,
  },
});
