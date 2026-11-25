# UAE PASS for Node.js

Server-side TypeScript SDK for UAE PASS sign-in and qualified PDF signing. Requires Node.js 22 or later and ES module imports.

## Install

```sh
npm install @alkhajeh/uaepass-server
```

## Configuration

All clients take `environment` (`staging` or `production`), `clientId`, and `clientSecret`. The SDK selects the UAE PASS endpoints. Your server supplies the credentials and hosts the callback routes.

| Client | Credentials | Additional options |
| --- | --- | --- |
| `createUaePassClient` | Credentials for sign-in | `redirectUri` for the OAuth callback |
| `createUaePassSigningClient` | Credentials for document signing | `finishCallbackUrl` for the hosted approval return |
| `createUaePassSigningValidationClient` | Credentials with access to LTV and verification | Optional `maxPdfBytes` to set a lower PDF size limit |

Use HTTPS for production callbacks. Staging also accepts HTTP on `localhost`. The signing and validation clients can use the same credential pair if UAE PASS enables both services for it.

For production, obtain credentials and register your callback URLs through UAE PASS. Request signing access if your app uses the signing clients. [UAE PASS onboarding](https://docs.uaepass.ae/getting-onboarded-with-uae-pass/onboarding-process-for-uae-pass-service-providers/initiation-phase)

## Sign in and fetch the user profile

Start the UAE PASS authorization flow in your app. In the host callback, validate the OAuth state and exchange the returned code once using the exact redirect URI from the authorization request. [UAE PASS authorization guide](https://docs.uaepass.ae/feature-guides/authentication/web-application/1.-obtaining-the-oauth2-access-code)

```ts
import { createUaePassClient } from '@alkhajeh/uaepass-server';

const uaepass = createUaePassClient({
  environment: 'staging',
  clientId: config.clientId,
  clientSecret: config.clientSecret,
  redirectUri: config.redirectUri,
});

const profile = await uaepass.getUserInfoFromCode(validatedCode);
```

The host links the UAE PASS profile to an application account and creates its own session. Use the profile’s `uuid` for account linking. Available attributes depend on the profile and approved scopes. The SDK preserves provider field names and exports `UaePassUserType`, `UaePassProfileType`, and `UaePassGender` for known values. [UAE PASS account linking](https://docs.uaepass.ae/feature-guides/authentication/user-linking) · [Profile attributes](https://docs.uaepass.ae/resources/attributes-list)

To manage the two calls separately, use `exchangeAuthorizationCode(validatedCode)` and `getUserInfo(accessToken)`. If User Info fails after a successful exchange, reuse the token for a User Info retry. Start a fresh sign-in if the code exchange times out or the code expires.

## Sign a PDF

This flow supports one signer and one PDF. It spans the request that starts signing and a later request that confirms approval. [UAE PASS single-document signing guide](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide)

1. **Prepare the request.** Authenticate the user through UAE PASS, check signing eligibility, and let them review the exact PDF version. Obtain the expected signer identity from that authenticated account using the mapping UAE PASS approved for your integration.

2. **Create the process.** Get a signing access token and submit the PDF. The host supplies `documentBytes` for the version the user reviewed.

   ```ts
   import {
     createUaePassSigningClient,
     createUaePassSigningValidationClient,
   } from '@alkhajeh/uaepass-server';

   const signing = createUaePassSigningClient({
     environment: 'staging',
     clientId: config.signingClientId,
     clientSecret: config.signingClientSecret,
     finishCallbackUrl: config.finishCallbackUrl,
   });

   const validation = createUaePassSigningValidationClient({
     environment: 'staging',
     clientId: config.validationClientId,
     clientSecret: config.validationClientSecret,
   });

   const signatureField = {
     name: 'Sign1',
     page: 'last' as const,
     rectangle: { x: 72, y: 72, width: 320, height: 96 },
   };
   const { accessToken } = await signing.getAccessToken();
   const { processId, documentId, approvalUrl } = await signing.createProcess({
     pdf: documentBytes,
     filename: 'agreement.pdf',
     signatureField,
   }, accessToken);
   ```

   Save the IDs and field name in a durable transaction with the owning account, expected signer, and document version. Redirect the browser to `approvalUrl` after saving the transaction.

3. **Confirm approval on your server.** On return to `finishCallbackUrl`, load the transaction for the signed-in account and check that the callback’s `signer_process_id` matches the saved process ID. The browser return signals when to check. The server response determines whether to proceed.

   ```ts
   const { accessToken: signingAccessToken } = await signing.getAccessToken();
   const { status } = await signing.getProcessResult(transaction.processId, signingAccessToken);
   ```

   Continue after `finished`. Treat `canceled`, `failed`, and `failed_documents` as terminal. Keep the transaction recoverable if the result is temporarily unavailable.

4. **Finalize the signed PDF.** Download the signed PDF, then call `finalizeSignedPdf()` to apply the required Long-Term Validation (LTV), verify the updated bytes through UAE PASS, and match the signer.

   ```ts
   const signedPdf = await signing.downloadSignedPdf(transaction.documentId, signingAccessToken);
   const { pdf: finalPdf, signature } = await validation.finalizeSignedPdf(signedPdf, {
     expectedSignatureFieldName: transaction.signatureFieldName,
     matchSigner: (signerSubject) =>
       matchesExpectedSigner(signerSubject, transaction.expectedSigner),
   });
   ```

   Implement `matchesExpectedSigner` in your backend using the identity mapping approved by UAE PASS for your integration. Bind the expected signer to the authenticated account when you save the transaction. The matcher can return a boolean or a promise. The SDK returns the PDF bytes and `signature` evidence only after the verified field matches and the matcher returns `true`. [LTV API](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/untitled/ltv-configuration/integration-web-services) · [Signature verification API](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/verification-api-integration/integration-web-service-details)

5. **Store the PDF and clean up.** Persist the verified `finalPdf` before calling `signing.deleteProcess(transaction.processId, signingAccessToken)`. Record cleanup progress so it can be retried independently. Check that the requesting account can access the PDF before serving it.

### Limits and failures

- The SDK caps each PDF at 10 MiB throughout signing and validation. If your app accepts uploads, set a lower upload limit before signing to leave room for the signature and LTV data added to the PDF.
- The SDK exposes `UaePassError` for sign-in, `UaePassSigningError` for signing, and `UaePassSigningValidationError` for finalization. Use `code` and `operation` to handle failures. Provider errors can also include HTTP `status`. For finalization, `verification_failed` covers signature or field verification, `signer_unverified` means the evidence was missing or the matcher declined it, and `signer_match_failed` means the matcher threw or rejected.
- `finalizeSignedPdf()` makes one attempt per step. For a resumable workflow, call `applyLongTermValidation()` and save its output as an intermediate artifact. Use `verifySignedPdf()` to verify those exact bytes independently, then check the signature field and match the signer before accepting the PDF.
- Reacquire a signing token when it expires. A timed-out process creation can still have succeeded at UAE PASS. Reconcile that attempt before creating another process.
- Keep credentials and tokens on the server. Keep secrets, authorization codes, tokens, profile data, certificate subjects, and PDF bytes out of logs.

## Try the staging demo

One local server handles Flutter code exchange and browser signing of a synthetic PDF. Browser signing requires a staging SOP3 account with a qualified certificate. [Node demo setup](https://github.com/Alkhajeh/UAEPass/blob/main/packages/node/example/README.md)
