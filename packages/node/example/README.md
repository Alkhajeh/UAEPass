# Node staging demo

The demo uses one loopback server on port 8787 for browser signing and Flutter code exchange. From a source checkout, run these commands in `packages/node`. Copy the environment template on first setup.

```sh
npm ci
npm run build
cp example/.env.example example/.env
```

Use the public UAE PASS sandbox credentials in the template. [Public staging credentials](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/testing-credentials-for-poc)

If using the code-exchange route, set `UAEPASS_REDIRECT_URI` in `example/.env` to the exact redirect URI used by your client. Start the server with `npm run example`.

## Browser signing demo

Use a staging UAE PASS SOP3 account with a verified Emirates ID and a qualified certificate. The demo signs a synthetic PDF on loopback and uses `SignerAndDateTime` in the reserved box on the last page. The visible stamp may include the staging Emirates ID number. [Create a qualified staging certificate](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/upgrade-staging-uae-pass-account)

The signing demo uses `UAEPASS_CLIENT_ID` and `UAEPASS_CLIENT_SECRET` for sign-in. It uses `UAEPASS_SIGNING_CLIENT_ID` and `UAEPASS_SIGNING_CLIENT_SECRET` for REST signing, LTV, and signature verification.

The signing flow uses `http://localhost:8787/signing/auth/callback` and `http://localhost:8787/signing/finish` for its callbacks. The SDK selects the standard staging gateway. The demo calls `finalizeSignedPdf()` with a staging matcher that compares the certificate subject's serial-number attribute to the authenticated profile's `idn`. Use the identity mapping UAE PASS approves for your production integration. [SOAP gateway documentation](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/verification-api-integration/integration-web-service-details)

Open `http://localhost:8787/signing`. Sign in, review the PDF, and choose **Sign with UAE PASS**. Complete approvals and enter any certificate password in UAE PASS. A download becomes available after LTV and signer verification succeed. The demo keeps short-lived local state and attempts pending cleanup for a stored PDF when its session expires.

### Staging verification

- With a synthetic PDF and one SOP3 staging signer, the public sandbox issued a 600-second signing token, accepted the signing request, and redirected the browser to the configured localhost callback. The result endpoint returned HTTP 404 before approval and HTTP 200 with `finished` afterward. Keep pending requests recoverable when the provider has yet to return a terminal result. A separate cancellation returned HTTP 200 with `canceled`.
- The staging result request uses the v2 signer-process path listed in the endpoint table. The signing step’s public example shows a v1 result path. The REST token request follows the official Postman collection’s query-parameter form, and LTV and verification use the staging HTTPS SOAP gateway. [Endpoint table](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/endpoints) · [Signing step](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/untitled/3.-executing-the-document-signature-process) · [Official Postman collection](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/postman-collection-for-digital-signature)
- UAE PASS returned the signed PDF and accepted the SOAP LTV and verification calls. Its verified certificate subject matched the first account’s authenticated Emirates ID. The same signed PDF was rejected when compared against a different synthetic identifier. An independent check verified the signature and the document timestamp cryptographically, confirmed that the timestamp covers the entire final PDF, and found embedded revocation data. The staging SOAP service supplied the trust verdict. Provider cleanup returned HTTP 204.
- All five appearance checks with that staging account passed LTV, signature field verification, signer matching, and provider cleanup. Omitting both `location` and `appearance` produced no visible stamp. With explicit placement, omitted appearance rendered signer and date/time text, `DateTimeOnly` rendered date/time, `SignerAndDateTime` rendered signer details including the Emirates ID number and date/time, and `Hidden` produced no visible stamp. None of the five outputs embedded a signature image in the stamp.
- Coverage still needs a second qualified staging signer and UAE PASS confirmation of the identity mapping for the intended signer population. The issuing CA’s published certificate profile treats the subject serial number as optional. Use a separate browser profile for the alternate account to avoid a reused UAE PASS session. [Certificate practice statement](https://www.desc.gov.ae/wp-content-repository/source/cps/DubaiPKI-CorporateCA-CertificationPracticeStatement_v1.9.pdf#page=68) · [LTV configuration](https://docs.uaepass.ae/feature-guides/signature-integration-guide/digital-signature-single-document/signing-guide/untitled/ltv-configuration)

## Code-exchange demo

After your client validates the callback, send the code promptly to `POST http://127.0.0.1:8787/auth/uaepass` with `Content-Type: application/json` and a JSON body of `{"code":"…"}`. HTTP `200` with `{"ok":true}` confirms a successful exchange and profile fetch. For fixture-based verification, run `npm test`.
