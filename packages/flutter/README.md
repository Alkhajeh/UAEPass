# UAE PASS for Flutter

Add official English and Arabic UAE PASS buttons to your Flutter app. On Android and iOS, the SDK hands off to the UAE PASS app when installed and uses an embedded browser otherwise. On Flutter Web, it redirects the current browser tab to UAE PASS and resumes at your app's registered callback.

## Requirements

- Flutter 3.50.1+ and Dart 3.14+
- Android API 24+, iOS 15+, or a Flutter Web app
- A UAE PASS client ID and a registered redirect URI for your environment and channel. [UAE PASS mobile guide](https://docs.uaepass.ae/feature-guides/authentication/mobile-application) · [UAE PASS web guide](https://docs.uaepass.ae/feature-guides/authentication/web-application)

## Quick start

Follow these steps for Android and iOS. For a browser app, see [Flutter Web quick start](#flutter-web-quick-start).

### 1. Install

```sh
flutter pub add uaepass
```

### 2. Register the callback

- `redirectUri` is the final HTTPS OAuth URL registered with UAE PASS. The mobile SDK intercepts it in the WebView to read and validate the authorization result.
- `callbackScheme` is the custom URL scheme used to reopen your app during the UAE PASS app handoff. Choose a unique lowercase reverse-domain name based on your app ID. Register it in the platform settings below and pass the same string, such as `com.example.yourapp`, to `UaePassConfiguration`. Share it with UAE PASS as required by your integration.

#### Android

Merge these entries into the activity that hosts Flutter in your app's `AndroidManifest.xml`. Keep the activity exported for external callbacks. Configure it to deliver the callback to the existing activity via `onNewIntent` so the SDK can resume the same WebView. The example uses `android:launchMode="singleTask"`.

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.yourapp" />
    <data android:host="success" />
    <data android:host="failure" />
</intent-filter>
```

The plugin declares internet access and both UAE PASS packages in its Android manifest.

#### iOS

Merge these keys and array entries into your app's `Info.plist`. The URL type registers your app's callback. The query schemes allow the SDK to check for the production and staging UAE PASS apps. The plugin supports Swift Package Manager and CocoaPods.

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.example.yourapp</string>
        </array>
    </dict>
</array>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>uaepass</string>
    <string>uaepassstg</string>
</array>
```

These platform settings let the SDK receive the custom-scheme return and resume the active WebView. Your Flutter sign-in screen handles the result through the button's `onResult` callback. The deep-link opt-out disables Flutter's default deep-link routing across the host app. If you also use app links or universal links elsewhere, route those URLs with your app's link handler. [Flutter deep-link setup](https://docs.flutter.dev/ui/navigation/deep-linking#migrating-from-plugin-based-deep-linking)

### 3. Add the button and handle the result

Create one client for your integration and place `UaePassSignInButton` on your sign-in page. The button disables itself during UAE PASS authorization. Its `onResult` callback receives a typed grant, cancellation, or authorization failure.

```dart
import 'package:uaepass/uaepass.dart';

final client = UaePassClient(
  UaePassConfiguration(
    environment: UaePassEnvironment.staging,
    clientId: 'your-client-id',
    callbackScheme: 'com.example.yourapp',
    redirectUri: Uri.parse('https://service.example/uaepass/callback'),
  ),
);

final signInButton = UaePassSignInButton(
  client: client,
  onResult: handleAuthorizationResult,
);

Future<void> handleAuthorizationResult(
  UaePassResult<UaePassAuthorizationGrant> result,
) async {
  switch (result) {
    case UaePassSuccess(:final value):
      await completeSignInOnBackend(value.code);
    case UaePassCancelled():
      return;
    case UaePassFailure(:final reason):
      showSignInFailure(reason);
  }
}
```

### 4. Complete sign-in on your backend

Implement `completeSignInOnBackend` by sending the one-time code over HTTPS to an endpoint on your own backend. The backend can use any language or framework that can call the UAE PASS APIs.

1. Exchange the code promptly at UAE PASS `/idshub/token`. Use the client secret stored on your server and the exact registered redirect URI used to start authorization.
2. Fetch the UAE PASS profile at `/idshub/userinfo` from the backend. Apply your approved account eligibility rules and use the stored UAE PASS `uuid` to look up a linked account. Apply your approved first-time account flow when there is no match.
3. Return an app session on success, or a result the app can present or route. Use `UaePassSignInMessages.forResult` to display supported eligibility and sign-in errors in the app's locale. The app owns loading and navigation during this step.

When the user signs out, invalidate the app session on your backend and clear the local session. Verify that the next UAE PASS sign-in challenges the user again on both mobile paths as part of your assessment. [UAE PASS mobile API](https://docs.uaepass.ae/feature-guides/authentication/mobile-application/guide/api) · [Authentication checklist](https://docs.uaepass.ae/getting-onboarded-with-uae-pass/onboarding-process-for-uae-pass-service-providers/development-phase#assessment-check-list)

## Flutter Web quick start

Install `uaepass` and register a callback on the same origin as your Flutter Web app. Use HTTPS for hosted apps. Web staging can use HTTP at `localhost`. Configure your web host to serve the Flutter entry document at that path and process the callback before your router or analytics initialize. Set `Referrer-Policy: no-referrer` on the callback response and omit its query string from access logs and traces. Use the exact registered redirect URI in the app and backend configuration. UAE PASS issues separate credentials for the approved web channel. [Flutter URL strategies](https://docs.flutter.dev/ui/navigation/url-strategies) · [UAE PASS onboarding guidelines](https://docs.uaepass.ae/guidelines/use-cases/standard-implementation-guidelines)

```dart
import 'package:flutter/widgets.dart';
import 'package:uaepass/uaepass.dart';

final webClient = UaePassWebClient(
  UaePassWebConfiguration(
    environment: UaePassEnvironment.staging,
    clientId: 'your-web-client-id',
    redirectUri: Uri.parse('https://service.example/uaepass/callback'),
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final signIn = webClient.completeLogin(exchangeCode: exchangeCode);
  runApp(
    MyApp(
      initialSignIn: signIn,
      signInButton: UaePassWebSignInButton(
        client: webClient,
        onStart: (result) {
          if (result case UaePassFailure(:final reason)) {
            showSignInFailure(reason);
          }
        },
      ),
    ),
  );
}
```

Implement `UaePassCodeExchange<T>` as `exchangeCode` to send the grant to your backend and return a typed session result. Use a browser-accessible endpoint, follow the same server exchange steps, and protect session creation against cross-site requests. See [Complete sign-in on your backend](#4-complete-sign-in-on-your-backend).

Use your app's `showSignInFailure` handler to display errors when the browser cannot start authorization.

The SDK stores one-time authorization state in the current tab, validates and consumes it after the redirect, and removes the provider parameters from the URL before calling `exchangeCode`. The future resolves to `null` on a regular page load. Use `completeAuthorization()` instead when your app handles the grant directly. UAE PASS advises exchanging the code within 10 seconds. [Authorization code guide](https://docs.uaepass.ae/feature-guides/authentication/web-application/1.-obtaining-the-oauth2-access-code) · [Token API](https://docs.uaepass.ae/feature-guides/authentication/web-application/2.-obtaining-the-access-token) · [Exchange timing](https://docs.uaepass.ae/faq/common-integration-issues)

For programmatic sign-in, call `webClient.startAuthorization(locale: locale)`. The button uses the app locale and exposes `onStart` for the navigation result. Handle the authorization result when Flutter starts again. When the user signs out, invalidate the app session and navigate the current tab to `webClient.logoutUri(redirectUri: returnUri)` with a return URL on the app's origin. [Web logout guide](https://docs.uaepass.ae/feature-guides/authentication/web-application/4.-web-single-sign-on-sso-and-logout-user-session-from-uae-pass)

## Optional configuration

- **Arabic.** Add `Locale('ar')` alongside `Locale('en')` in `supportedLocales`. Set `localizationsDelegates` to `GlobalMaterialLocalizations.delegates` or merge those delegates into your existing list. The SDK follows your app locale for the button and the UAE PASS authorization page, with English as the fallback. [Example app setup](example/lib/main.dart)
- **Appearance.** Use `content` to choose `signIn`, `login`, `registerAccount`, `signUp`, `authorize`, or `logoOnly`. Set `shape` and `style` to suit your layout. By default, light themes use white with outline and dark themes use solid white. The gallery previews all available combinations. [UAE PASS button guidelines](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines)
- **Button space.** Give the text button its own row where possible. Allow at least 190 logical pixels of width and 60 of height for the default sign-in artwork in both languages, or 220 of width for all wording variants. The artwork keeps its aspect ratio and clear space. When the bounds are too small for text at 140 × 30, the `signIn` and `login` variants use official logo-only artwork with the same accessible label. [UAE PASS button size and margin](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines/button-size-and-margin)
- **Programmatic mobile authorization.** `client.authorize(context)` returns the same typed result as the button. `client.login<T>()` also calls your app-supplied exchange callback and returns the session result. One attempt can be active per Flutter engine.
- **Scopes and messages.** Pass `scopes` in your client configuration if your approved scopes differ from the default general-profile scope. Use `UaePassSignInMessages.forResult` for localized cancellation and failure messages.

## Example app

Run the example app to try staging sign-in, preview localized outcomes offline, or explore the official button variations and copy a Flutter snippet. [Example app instructions](example/README.md) · [Demo redirect settings](example/README.md#redirect-configuration)

## Development

Use the Flutter version pinned in CI. Run these checks from both `packages/flutter` and `packages/flutter/example`.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Both projects use `flutter_lints` and the same strict type checks. The example inherits the package's analyzer settings.

From the plugin, run `flutter test --no-pub --platform chrome test/web_authorization_test.dart`. From the example directory, run `flutter build web --no-pub --dart-define=UAEPASS_WEB_REDIRECT_URI=http://localhost:8000`.

### Release checks

From `packages/flutter`, preview what will be published to pub.dev.

```sh
flutter pub publish --dry-run
```

Before publishing, verify app handoff and embedded-browser fallback with UAE PASS staging on Android and iOS. Verify Flutter Web approval, cancellation, backend exchange, and logout in English and Arabic using the staging demo. Include a cold browser return and confirm the exchange starts within 10 seconds. Confirm that the official button artwork may be redistributed with the package. [Staging demo](example/README.md) · [Demo backend exchange](example/README.md#optional-backend-exchange) · [UAE PASS exchange timing](https://docs.uaepass.ae/faq/common-integration-issues)
