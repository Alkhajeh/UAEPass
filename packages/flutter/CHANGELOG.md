## Unreleased

- Configure the registered redirect URI in `Uaepass.init`. Call `authorize()` for a typed grant, cancellation, or failure, and exchange a successful grant on your backend.
- Use `login(exchangeCode: ...)` to authorize and return a completed session. The public staging sandbox provides a built-in exchange. The login button supports both flows.
- Replace `flutter_inappwebview` with `webview_flutter` and remove the example's legacy Android Gradle workaround.
- Handle app-to-app callbacks in the plugin. Android declarations cover network access and UAE PASS app visibility. iOS supports Swift Package Manager and CocoaPods.
- Document the migration from `0.0.x` and publish only the supported sign-in button artwork.

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
