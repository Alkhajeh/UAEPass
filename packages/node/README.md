# UAE PASS for Node.js

Use this server-only client to exchange a UAE PASS authorization code and fetch the authenticated user's profile. It requires Node.js 22 or later and uses ES module imports.

## Install

From your server project's directory, run the following command.

```sh
npm install @alkhajeh/uaepass-server
```

## Use in your server

For web sign-in, generate a one-time `state` and bind it to the originating browser session. Verify and consume it at the callback before calling the SDK. In the Flutter flow, the plugin validates `state` before handing the authorization code to the app. [OAuth security guidance](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1)

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

Exchange the validated code promptly using the exact registered redirect URI from the authorization request. Keep the client secret, access tokens, and provider profile on the backend. Keep `Authorization` headers and authorization codes out of logs and traces, including codes in callback and token request URLs. The host application owns account linking, eligibility, and sessions. [UAE PASS token API](https://docs.uaepass.ae/feature-guides/authentication/web-application/2.-obtaining-the-access-token)

- `getUserInfoFromCode(code)` exchanges the code and returns the profile.
- `exchangeAuthorizationCode(code)` returns `accessToken`, `expiresInSeconds`, and optional `scopes`.
- `getUserInfo(accessToken)` fetches the profile using a token already held by the backend.

Provider failures throw `UaePassError` with a stable `code`, an `operation`, and an HTTP `status` when available. The client makes one exchange attempt. If the code expires or the exchange times out, start a fresh sign-in. A `userinfo` failure from `getUserInfoFromCode` means the code has already been exchanged. To retry User Info independently, use the two separate methods and reuse the access token from the successful exchange.

## Profile attributes

`UaePassUserInfo` keeps the provider's field names and exposes additional fields as `unknown`. Field availability depends on the user's profile and your approved scopes. For account linking, use `uuid` as the UAE PASS identifier. [UAE PASS Attributes List](https://docs.uaepass.ae/resources/attributes-list) · [UAE PASS account linking](https://docs.uaepass.ae/feature-guides/authentication/user-linking)

Use `UaePassUserType`, `UaePassProfileType`, and `UaePassGender` to compare known values, for example `profile.profileType === UaePassProfileType.Visitor`. The SDK preserves unfamiliar strings. An omitted `profileType` leaves the profile category unspecified. [UAE PASS User Info API](https://docs.uaepass.ae/feature-guides/authentication/web-application/3.-obtaining-authenticated-user-information-from-the-access-token)

## Development checks

From this directory, run:

```sh
npm ci
npm test
npm pack --dry-run
```

For a local install check, run `npm pack` and install the generated `.tgz` file from your server project.

For a live exchange with the sample backend, see **Verify the local backend** in `packages/flutter/example/README.md`. [UAEPass repository](https://github.com/Alkhajeh/UAEPass)
