# UAE PASS for Node.js

Server-side TypeScript SDK for UAE PASS sign-in, PDF signing, and signature verification. Requires Node.js 22 or later and ES module imports.

[Sign in](#sign-in) · [Sign a PDF](#sign-a-pdf) · [Verify an existing PDF](#verify-an-existing-pdf)

## Install and configure

```sh
npm install @alkhajeh/uaepass-server
```

Set `environment` explicitly on each client. Use `'staging'` for testing and `'production'` for live integrations. The SDK selects the matching UAE PASS endpoints. Supply the `clientId` and `clientSecret` issued for that environment and handle the callback routes in your application.

| Client | Credentials | Additional configuration |
| --- | --- | --- |
| `createUaePassClient()` | Sign-in | `redirectUri`, where UAE PASS returns the OAuth authorization code |
| `createUaePassSigningClient()` | Document signing | `finishCallbackUrl`, where UAE PASS returns when hosted signing ends, and optional `maxUploadPdfBytes` (default 10 MiB) |
| `createUaePassSigningValidationClient()` | Long-term validation and verification | Common client configuration above |

Use HTTPS for production callbacks. Staging also accepts HTTP on `localhost`. Signing and validation can share credentials when UAE PASS enables both services for them. [UAE PASS onboarding](https://docs.uaepass.ae/getting-onboarded-with-uae-pass/onboarding-process-for-uae-pass-service-providers/initiation-phase)

## Sign in

Start UAE PASS authorization in your application. When the callback arrives, validate and consume its OAuth state before sending the code to the SDK. Use the exact registered redirect URI from the authorization request. [UAE PASS authorization guide](https://docs.uaepass.ae/feature-guides/authentication/web-application/1.-obtaining-the-oauth2-access-code)

```ts
import { createUaePassClient } from '@alkhajeh/uaepass-server';

const auth = createUaePassClient({
  environment: 'staging',
  clientId: config.clientId,
  clientSecret: config.clientSecret,
  redirectUri: config.redirectUri,
});

const profile = await auth.getUserInfoFromCode(validatedCode);
```

Use the returned profile to link the UAE PASS user to your application account. UAE PASS recommends `uuid` for account linking. Available profile fields depend on the account and approved scopes. [UAE PASS account linking](https://docs.uaepass.ae/feature-guides/authentication/user-linking)

To manage the exchange and profile fetch separately, use `exchangeAuthorizationCode(code)` followed by `getUserInfo(accessToken)`. If the profile fetch fails, you can retry it with the valid token. Start a fresh authorization if the code expires or its exchange times out.

## Sign a PDF

Authenticate the signer through UAE PASS, check eligibility for the selected signature level, and let them review the exact version of the PDF they will sign. Use the identity mapping approved by UAE PASS to bind the expected signer to the transaction. [UAE PASS signing guide](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide)

1. Call `getAccessToken()` and `createProcess()`, then open the returned `approvalUrl`.
2. After the approval return, call `getProcessResult()`. Once the result is `finished`, call `downloadSignedPdf()` and `finalizeSignedPdf()`.
3. Save the verified PDF, then call `deleteProcess()` to remove the provider copy.

### Start signing

Pass the source PDF as a `Uint8Array` (`documentBytes` below). The signing token comes from the signing client and can be reused while valid.

`createProcess()` accepts original PDFs up to **10 MiB** by default. Set `maxUploadPdfBytes` on `createUaePassSigningClient()` to change this limit, up to **20 MiB** (`20 * 1024 * 1024` bytes). This leaves room for the signature and the Base64 encoding used by the UAE PASS LTV and verification APIs.

```ts
import { createUaePassSigningClient } from '@alkhajeh/uaepass-server';

const signing = createUaePassSigningClient({
  environment: 'staging',
  clientId: config.signingClientId,
  clientSecret: config.signingClientSecret,
  finishCallbackUrl: config.finishCallbackUrl,
});

const signatureFieldName = 'Sign1';
const { accessToken } = await signing.getAccessToken();
const { processId, documentId, approvalUrl } = await signing.createProcess({
  pdf: documentBytes,
  filename: 'agreement.pdf',
  signatureField: { name: signatureFieldName },
}, accessToken);
```

Before opening `approvalUrl`, save `processId`, `documentId`, and `signatureFieldName` with the authenticated account, expected signer, and document version in your application's transaction store.

### After approval

Load the transaction associated with the authenticated account and correlate the browser callback's `signer_process_id` with the saved process ID. For mobile, use the finish URL as the cue to check the saved transaction through your backend.

`getProcessResult()` returns a `status` typed as `UaePassSigningStatus`.

| Status | What to do |
| --- | --- |
| `'finished'` | Download and finalize the signed PDF. |
| `'canceled'`, `'failed'`, `'failed_documents'` | End the signing attempt and report the outcome. |

If the result is temporarily unavailable, keep the transaction so you can check again.

```ts
import { createUaePassSigningValidationClient } from '@alkhajeh/uaepass-server';

const validation = createUaePassSigningValidationClient({
  environment: 'staging',
  clientId: config.validationClientId,
  clientSecret: config.validationClientSecret,
});

const { accessToken: signingAccessToken } = await signing.getAccessToken();
const { status } = await signing.getProcessResult(transaction.processId, signingAccessToken);

if (status === 'finished') {
  const signedPdf = await signing.downloadSignedPdf(transaction.documentId, signingAccessToken);
  const { pdf: finalPdf } = await validation.finalizeSignedPdf(signedPdf, {
    expectedSignatureFieldName: transaction.signatureFieldName,
    matchSigner: (signerSubject) =>
      matchesExpectedSigner(signerSubject, transaction.expectedSigner),
  });

  await saveVerifiedPdf(transaction, finalPdf);
  await signing.deleteProcess(transaction.processId, signingAccessToken);
}
```

`finalizeSignedPdf()` applies long-term validation (LTV), verifies the updated bytes, checks the signature field, and calls your `matchesExpectedSigner` function with the certificate subject. Your matcher returns `true` only when the subject matches the expected signer under your approved identity mapping. The result contains the verified PDF bytes and signature evidence. [LTV API](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/untitled/ltv-configuration/integration-web-services)

`saveVerifiedPdf()` represents storage in your application. Persist the verified bytes before deleting the provider copy. If deletion fails, retry it separately. Check that the requesting account can access the stored PDF before serving it.

### Signing options

- **`signatureLevel`** accepts `UaePassSignatureLevel.Qualified` (default) or `UaePassSignatureLevel.Advanced`. Qualified requires an SOP3 account with a qualified certificate. Advanced requires an eligible SOP2 or SOP3 account with an advanced certificate and a signing client authorized for Advanced. [UAE PASS signing scenarios](https://docs.uaepass.ae/guidelines/use-cases/standard-digital-signature-scenarios-for-service-provider-use-cases)
- **`signatureField.name`** is required. Save it with the transaction so you can verify the signature field during finalization.
- **`signatureField.location`** is optional. Set `page` to a one-based page number or `'last'` and supply `rectangle: { x, y, width, height }` in PDF coordinates. Omit `location` to let UAE PASS place the signature. [UAE PASS signer process options](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/untitled/2.-creating-the-document-signature-process)
- **`signatureField.appearance`** is optional. Choose `UaePassSignatureAppearance.DateTimeOnly`, `UaePassSignatureAppearance.SignerAndDateTime`, or `UaePassSignatureAppearance.Hidden`. `Hidden` requests an empty visual appearance while preserving the digital signature. Omit `appearance` to use the UAE PASS default.

## Verify an existing PDF

Use `verifySignedPdf()` on a PDF that already carries one UAE PASS signature. The method takes PDF bytes and returns the verified signature field name and, when available, the certificate subject. [UAE PASS verification API](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/verification-api-integration)

```ts
import { readFile } from 'node:fs/promises';
import { createUaePassSigningValidationClient } from '@alkhajeh/uaepass-server';

const validation = createUaePassSigningValidationClient({
  environment: 'staging',
  clientId: config.validationClientId,
  clientSecret: config.validationClientSecret,
});

const pdf = await readFile('already-signed.pdf');
const { signatureFieldName, signerSubject } = await validation.verifySignedPdf(pdf);
```

If you expect a particular signer, require the returned subject to match that identity before accepting the PDF.

## Errors and limits

- The upload limit applies to the original PDF only. The SDK buffers up to **32 MiB** for the signed PDF download and **48 MiB** for the full LTV response, including Base64 and SOAP overhead. LTV and verification accept PDFs up to **36 MiB**, which covers every PDF the SDK can return from either response.
- Handle `UaePassError` for sign-in, `UaePassSigningError` for signing, and `UaePassSigningValidationError` for validation. Use `code` and `operation` to distinguish a rejected signature or signer mismatch from a service timeout. Provider errors may include an HTTP `status`.
- Refresh an expired signing token with `getAccessToken()`. If `createProcess()` times out, reconcile the attempt with UAE PASS before creating another process.
- For resumable finalization, call `applyLongTermValidation()` and persist its output. Verify those exact bytes with `verifySignedPdf()` and check the expected signature field and signer before accepting the PDF.
- Keep credentials and tokens on the server. Keep authorization codes, secrets, tokens, profile data, certificate subjects, and PDF bytes out of logs.

## Staging demo

[Run the staging demo](https://github.com/Alkhajeh/UAEPass/blob/main/packages/node/example/README.md)
