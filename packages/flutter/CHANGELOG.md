## Unreleased

- Add the instance-based `UaePassClient`. Use `authorize()` for a typed grant and `login()` for an app-owned session returned by your backend exchange.
- Route UAE PASS detection and app handoff through native Android and iOS bridges, with an embedded WebView for the flow.
- Add official English and Arabic button artwork for sign-in, login, registration, sign-up, and authorization, plus logo-only buttons.
- Add `UaePassSignInButton` for provider-owned pages. Sign-in, login, registration, sign-up, authorization, and logo-only artwork all start the same UAE PASS authentication flow, with automatic disabling during the attempt and typed outcomes. Redesign the bilingual example with live staging sign-in, offline outcomes, and an artwork gallery.
- Ignore late app handoffs and callbacks after dismissing authorization. Return a typed failure when WebView startup fails.
- Return a typed authorization failure when the sign-in page receives an HTTP error.
- Clarify host app setup and surface the active button preview in the example gallery.

## 0.0.5

- Update readme.

## 0.0.4

- Bug fixes.

## 0.0.3

- Bug fixes.

## 0.0.2

- Bug fixes.

## 0.0.1

- Initial release.
