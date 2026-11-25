# UAE PASS for Flutter

Add official English and Arabic UAE PASS buttons to your Flutter app. The SDK hands off to the UAE PASS app when installed and offers web sign-in when it is absent. It returns the authorization result to your app.

## Requirements

- Flutter 3.50.1+ and Dart 3.14+
- Android API 24+ or iOS 15+
- A UAE PASS client ID and a registered HTTPS redirect URI for your environment. [UAE PASS mobile integration guide](https://docs.uaepass.ae/feature-guides/authentication/mobile-application)

## Quick start

### 1. Install

```sh
flutter pub add uaepass
```

### 2. Register the callback

- `redirectUri` is the HTTPS URL registered with UAE PASS for the authorization result.
- `callbackScheme` is an app-specific lowercase scheme that opens your Flutter app again after the UAE PASS app handoff. Choose a unique reverse-domain name based on your app ID. Register the same value in Dart and your platform settings, and share it with UAE PASS as required by your integration.

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

The deep-link opt-out on each platform disables Flutter's default deep-link routing across the host app. If you also use app links or universal links elsewhere, make sure your app's link handler continues to route those URLs. The SDK handles the registered UAE PASS callback. [Flutter deep-link setup](https://docs.flutter.dev/ui/navigation/deep-linking#migrating-from-plugin-based-deep-linking)

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

Implement `completeSignInOnBackend` by sending the one-time code over HTTPS to an endpoint on your own backend, for example `POST /auth/uaepass` with a JSON body of `{"code":"<authorization code>"}`.

1. Exchange the code promptly at UAE PASS `/idshub/token`. Use the client secret stored on your server and the configured HTTPS redirect URI that exactly matches `UaePassConfiguration.redirectUri`.
2. Fetch the UAE PASS profile at `/idshub/userinfo` from the backend. Apply your approved account eligibility rules and use the stored UAE PASS `uuid` to look up a linked account. Apply your approved first-time account flow when there is no match.
3. Return an app session on success, or a result the app can present or route. Use `UaePassSignInMessages.forResult` to display supported eligibility and sign-in errors in the app's locale. The app owns loading and navigation during this step.

When the user signs out, invalidate the app session on your backend and clear the local session. Verify that the next UAE PASS sign-in challenges the user again on both mobile paths as part of your assessment. [UAE PASS mobile API](https://docs.uaepass.ae/feature-guides/authentication/mobile-application/guide/api) · [Authentication checklist](https://docs.uaepass.ae/getting-onboarded-with-uae-pass/onboarding-process-for-uae-pass-service-providers/development-phase#assessment-check-list)

The repository README links to the Node.js SDK and staging example for evaluating the backend exchange locally. [UAEPass repository](https://github.com/Alkhajeh/UAEPass)

## Optional configuration

- **Arabic.** Add `Locale('ar')` alongside `Locale('en')` in `supportedLocales`. Set `localizationsDelegates` to `GlobalMaterialLocalizations.delegates` or merge those delegates into your existing list. The SDK follows your app locale for the button and the UAE PASS authorization page, with English as the fallback. [Example app setup](example/lib/main.dart)
- **Appearance.** Use `content` to choose `signIn`, `login`, `registerAccount`, `signUp`, `authorize`, or `logoOnly`. Set `shape` and `style` to suit your layout. By default, light themes use white with outline and dark themes use solid white. The gallery previews all available combinations. [UAE PASS button guidelines](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines)
- **Button space.** Give the text button its own row where possible. Allow at least 190 logical pixels of width and 60 of height for the default sign-in artwork in both languages, or 220 of width for all wording variants. The artwork keeps its aspect ratio and clear space. When the bounds are too small for text at 140 × 30, the `signIn` and `login` variants use official logo-only artwork with the same accessible label. [UAE PASS button size and margin](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines/button-size-and-margin)
- **Programmatic authorization.** `client.authorize(context)` returns the same typed result as the button. `client.login<T>()` also calls your app-supplied exchange callback and returns the session result. One attempt can be active per Flutter engine.
- **Scopes and messages.** Pass `scopes` in `UaePassConfiguration` if your approved scopes differ from the default general-profile scope. Use `UaePassSignInMessages.forResult` for localized cancellation and failure messages.

## Example app

Run the example app to try staging sign-in, preview localized outcomes offline, or explore the official button variations and copy a Flutter snippet. [Example app instructions](example/README.md)

## Development

Use the Flutter version pinned in CI. Run these checks from both `packages/flutter` and `packages/flutter/example`.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Both projects use `flutter_lints` and the same strict type checks. The example inherits the package's analyzer settings.

### Release checks

From `packages/flutter`, preview what will be published to pub.dev.

```sh
flutter pub publish --dry-run
```

Before publishing, verify app handoff and web fallback with UAE PASS staging on Android and iOS. Confirm that the official button artwork may be redistributed with the package.
