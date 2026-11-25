# UAE PASS for Node.js

Use this server-only client to exchange a UAE PASS authorization code and fetch the authenticated user's profile. It requires Node.js 22 or later. The package is available for local evaluation.

```ts
import { createUaePassClient } from '@alkhajeh/uaepass-server';

const uaepass = createUaePassClient({
  environment: 'staging',
  clientId: serverConfig.clientId,
  clientSecret: serverConfig.clientSecret,
  redirectUri: serverConfig.redirectUri,
});

const profile = await uaepass.getUserInfoFromCode(code);
```

Exchange the code as soon as the app receives it. Use the exact redirect URI registered with UAE PASS and used to request the code. Keep the client secret, access tokens, and provider profile on the backend. The host application validates its sign-in attempt and applies its own account linking, eligibility, and session rules. [UAE PASS token API](https://docs.uaepass.ae/feature-guides/authentication/web-application/2.-obtaining-the-access-token)

- `getUserInfoFromCode(code)` exchanges the code and returns the profile.
- `exchangeAuthorizationCode(code)` returns `accessToken`, `expiresInSeconds`, and `scopes` when supplied.
- `getUserInfo(accessToken)` fetches the profile using a token already held by the backend. Common fields are typed and additional provider attributes are available as `unknown`. `uuid` and `sub` are distinct, opaque identifiers. [UAE PASS profile API](https://docs.uaepass.ae/feature-guides/authentication/web-application/3.-obtaining-authenticated-user-information-from-the-access-token)

Provider failures throw `UaePassError` with a stable `code`, an `operation`, and an HTTP `status` when available. The client makes one exchange attempt. After an expired code or an exchange timeout, start a fresh sign-in.

## Local evaluation

From this directory, run:

```sh
npm ci
npm test
npm pack --dry-run
npm pack
```

Install the generated tarball with `npm install /path/to/alkhajeh-uaepass-server-0.1.0.tgz` in your Node project.

For a live exchange with the sample backend, open `packages/flutter/example/README.md` and follow **Verify the local backend**. [UAEPass repository](https://github.com/Alkhajeh/UAEPass)
