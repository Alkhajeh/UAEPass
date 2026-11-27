## 0.2.1

- Improve the README and pub.dev Example tab with a bilingual screenshot, minimal mobile and web sign-in examples, and clearer setup checklists.
- Update the example app to resume a pending signing approval, reset the web signing return on exit, and show hosted signing in Arabic.

## 0.2.0

- Add the UAE PASS signing approval launcher and official English and Arabic signing buttons for Android, iOS, and web.
- Open the UAE PASS approval document link in an in-app PDF viewer on Android and iOS.
- Add `UaePassClient.logout()` to end the UAE PASS embedded browser session on Android and iOS.

## 0.1.2

- Add same-tab UAE PASS Web sign-in with a registered callback, one-time state, and the existing backend exchange hook. Add the official web sign-in button and a browser staging demo that supports HTTP on localhost.

## 0.1.1

- Add the instance-based `UaePassClient`. Use `authorize()` for a typed grant and `login()` for an app-owned session returned by your backend exchange.
- Route UAE PASS detection and app handoff through native Android and iOS bridges, with an embedded WebView for the flow.
- Add official English and Arabic button artwork for sign-in, login, registration, sign-up, and authorization, plus logo-only buttons.
- Add `UaePassSignInButton` for provider-owned pages. Each artwork choice starts the same UAE PASS flow and returns a typed authorization result. The button disables itself during authorization. The bilingual example manages its own exchange and loading state and includes offline outcomes and an artwork gallery.
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
