## Unreleased

- Add English and Arabic locale selection for the UAE PASS hosted signing screens.

## 0.2.0

- **Breaking change.** Remove `maxPdfBytes` from the signing validation client. Set `maxUploadPdfBytes` on the signing client to control the original upload size. It defaults to 10 MiB and can be raised to 20 MiB. Signed PDFs can grow during signing and long-term validation (LTV).
- Allow up to 60 seconds for PDF uploads, downloads, LTV, and verification.
- Bound validation inputs at 36 MiB before encoding them for SOAP.

## 0.1.0

- Add Qualified and Advanced PDF signing with configurable signature placement and appearance.
- Add long-term validation, signed PDF verification, and finalization with an application-supplied signer check.

## 0.0.3

- Add HTTP `localhost` redirect support for staging web sign-in.

## 0.0.2

- Publish the existing SDK through npm Trusted Publishing.

## 0.0.1

- Initial release with server-side authorization code exchange and user profile retrieval.
