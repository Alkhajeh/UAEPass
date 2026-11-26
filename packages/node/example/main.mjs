import {
  createUaePassClient,
  createUaePassSigningClient,
  createUaePassSigningValidationClient,
} from '@alkhajeh/uaepass-server';
import { defaultOrigin, loopbackHost, port, routes } from './config.mjs';
import { createExampleServer } from './server.mjs';

const required = [
  'UAEPASS_CLIENT_ID',
  'UAEPASS_CLIENT_SECRET',
  'UAEPASS_REDIRECT_URI',
  'UAEPASS_SIGNING_CLIENT_ID',
  'UAEPASS_SIGNING_CLIENT_SECRET',
];
const missing = required.filter((name) => !process.env[name]?.trim());
if (missing.length) {
  console.error('Missing ' + missing.join(', ') + '. Copy example/.env.example to example/.env.');
  process.exit(1);
}

const env = process.env;
const authConfig = {
  environment: 'staging',
  clientId: env.UAEPASS_CLIENT_ID,
  clientSecret: env.UAEPASS_CLIENT_SECRET,
};
const signingConfig = {
  environment: 'staging',
  clientId: env.UAEPASS_SIGNING_CLIENT_ID,
  clientSecret: env.UAEPASS_SIGNING_CLIENT_SECRET,
};

// Logs only sanitized SDK error fields. Never log authorization codes, tokens, or profiles.
function logError(error, context) {
  const { name = 'Error', code, operation, status } = error ?? {};
  const details = [code, operation, status].filter((value) => value !== undefined).join(' ');
  console.error('[' + context + '] ' + name + (details ? ': ' + details : ''));
}

const server = await createExampleServer({
  clientId: authConfig.clientId,
  authClient: createUaePassClient({ ...authConfig, redirectUri: defaultOrigin + routes.callback }),
  exchangeClient: createUaePassClient({ ...authConfig, redirectUri: env.UAEPASS_REDIRECT_URI }),
  signingClient: createUaePassSigningClient({ ...signingConfig, finishCallbackUrl: defaultOrigin + routes.finish }),
  validationClient: createUaePassSigningValidationClient(signingConfig),
  onError: logError,
});

server.on('error', (error) => {
  console.error(error.code === 'EADDRINUSE' ? 'Port ' + port + ' is already in use.' : error.message);
  process.exit(1);
});

function stop() {
  server.close();
  // Requests to UAE PASS can be slow. Do not wait for them indefinitely.
  setTimeout(() => server.closeAllConnections(), 5_000).unref();
}
process.once('SIGINT', stop);
process.once('SIGTERM', stop);

server.listen(port, loopbackHost, () => {
  console.log('UAE PASS staging demo at ' + defaultOrigin + routes.root);
  console.log('Code exchange at http://' + loopbackHost + ':' + port + routes.exchange);
});
