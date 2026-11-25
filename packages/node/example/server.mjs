import { Buffer } from 'node:buffer';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { createUaePassClient, UaePassError } from '@alkhajeh/uaepass-server';

const host = '127.0.0.1';
const port = 8787;

function reply(response, status) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  response.end(JSON.stringify({ ok: status === 200 }));
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

export function createExampleServer(client) {
  return createServer(async (request, response) => {
    if (request.headers.host !== `${host}:${request.socket.localPort}` || request.headers.origin) {
      return reply(response, 403);
    }
    if (request.url !== '/auth/uaepass') return reply(response, 404);
    if (request.method !== 'POST') {
      response.setHeader('Allow', 'POST');
      return reply(response, 405);
    }
    const contentType = request.headers['content-type']?.split(';')[0].trim().toLowerCase();
    if (contentType !== 'application/json') return reply(response, 415);

    try {
      const code = await readCode(request);
      if (!code) return reply(response, 400);
      await client.getUserInfoFromCode(code);
      reply(response, 200);
    } catch (error) {
      if (response.destroyed) return;
      if (error instanceof UaePassError) {
        if (error.code === 'invalid_grant') return reply(response, 400);
        if (error.code === 'timeout') return reply(response, 504);
      }
      reply(response, 502);
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const client = createUaePassClient({
    environment: 'staging',
    clientId: process.env.UAEPASS_CLIENT_ID,
    clientSecret: process.env.UAEPASS_CLIENT_SECRET,
    redirectUri: process.env.UAEPASS_REDIRECT_URI,
  });
  createExampleServer(client).listen(port, host, () => {
    console.log(`UAE PASS staging example listening on http://${host}:${port}`);
  });
}
