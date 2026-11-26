# Node staging demo

The demo uses one loopback server on port 8787 for standalone browser signing and for the Flutter example's code exchange and signing. From a source checkout, run these commands in `packages/node`. Copy the environment template on first setup.

```sh
npm ci
cp example/.env.example example/.env
```

Use the public UAE PASS sandbox credentials in the template. [Public staging credentials](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/testing-credentials-for-poc)

If using the code-exchange route, set `UAEPASS_REDIRECT_URI` in `example/.env` to the exact redirect URI used by your client. Start the server with `npm run example`, which builds the SDK first. The server checks for missing variables at startup and logs only sanitized error fields, never codes, tokens, or profile data.

## Layout

| File | Purpose |
| --- | --- |
| `main.mjs` | Reads the environment, creates the SDK clients, and starts the server. |
| `server.mjs` | `createExampleServer()` and its routes for the browser demo, the Flutter signing API, and the code exchange. |
| `signing-jobs.mjs` | The signing workflow: create the process, check the result, finalize and verify the PDF, and clean up. |
| `store.mjs` | In-memory session and transaction store with expiry. A production backend would use a shared store. |
| `views.mjs` | HTML pages, rendered with an escaping `html` template tag. |
| `http.mjs` | Small request and response helpers. |
| `config.mjs` | Ports, routes, lifetimes, and the sample document. |
| `signer-idn.mjs` | Matches the signing certificate subject to the signed-in Emirates ID. |

## Browser signing demo

The standalone browser demo uses Qualified signing. Use a staging UAE PASS SOP3 account with a verified Emirates ID and a qualified certificate. The demo signs a synthetic PDF on loopback and uses `SignerAndDateTime` in the reserved box on the last page. The visible stamp may include the staging Emirates ID number. [Create a qualified staging certificate](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/upgrade-staging-uae-pass-account)

The signing demo uses `UAEPASS_CLIENT_ID` and `UAEPASS_CLIENT_SECRET` for sign-in. It uses `UAEPASS_SIGNING_CLIENT_ID` and `UAEPASS_SIGNING_CLIENT_SECRET` for REST signing, LTV, and signature verification.

The signing flow uses `http://localhost:8787/signing/auth/callback` and `http://localhost:8787/signing/finish` for its callbacks. The SDK selects the standard staging gateway. The demo calls `finalizeSignedPdf()` with a staging matcher that compares the certificate subject's serial-number attribute to the authenticated profile's `idn`. Use the identity mapping UAE PASS approves for your production integration. [SOAP gateway documentation](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/verification-api-integration/integration-web-service-details)

Open `http://localhost:8787/signing`. Sign in, review the PDF, and choose **Sign with UAE PASS**. Complete approvals and enter any certificate password in UAE PASS. A download becomes available after LTV and signer verification succeed. The demo keeps short-lived local state and attempts pending cleanup for a stored PDF when its session expires.

## Code-exchange demo

After your client validates the callback, send the code promptly to `POST http://127.0.0.1:8787/auth/uaepass` with `Content-Type: application/json` and a JSON body of `{"code":"…"}`. HTTP `200` with `{"ok":true}` confirms a successful exchange and profile fetch.

The same loopback server lets the Flutter example use either Qualified or Advanced signing. The Flutter example sends a fresh authorization code for each signing transaction. The server exchanges the code once and binds the expected signer to that transaction. Checking the result and fetching the verified PDF require the transaction's expiring bearer credential. On Android and iOS, Flutter intercepts the finish URL. On web, the finish route redirects back to Flutter for the authenticated result check. [Flutter signing setup](../../flutter/example/README.md#sign-a-sample-document)
