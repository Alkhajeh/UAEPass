# UAE PASS for Flutter

`uaepass` adds UAE PASS sign-in to Flutter apps on Android and iOS. The plugin handles the mobile app handoff and provides a sign-in button with English and Arabic artwork.

## Install

Requires Flutter 3.50.1 or later, Dart 3.14 or later, Android API 24 or later, and iOS 15 or later.

```sh
flutter pub add uaepass
```

## Platform setup

Choose a custom URL scheme unique to your app and use the same value in the platform configuration and the Dart initializer. The snippets use `com.example.myapp.uaepass`.

### Android

In `android/app/src/main/AndroidManifest.xml`, set `android:launchMode="singleTask"` on the Flutter activity to route the return to the running sign-in screen. Add the following inside that activity. The plugin supplies the Internet permission and UAE PASS app visibility declarations through manifest merging.

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.myapp.uaepass" />
    <data android:host="success" />
    <data android:host="failure" />
</intent-filter>
```

### iOS

Add or merge these entries in `ios/Runner/Info.plist`. Keep the standard Flutter app and scene delegates. The plugin supports Swift Package Manager and CocoaPods.

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.example.myapp.uaepass</string>
        </array>
    </dict>
</array>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>uaepass</string>
    <string>uaepassstg</string>
</array>
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

If your app already routes incoming URLs, account for the Flutter deep-linking opt-out on both platforms. [Flutter deep-linking guide](https://docs.flutter.dev/ui/navigation/deep-linking)

## Try the public sandbox

Once the platform setup is in place, initialize the package before displaying `UaepassLoginButton`. To run this snippet as a standalone Flutter app, add `material_ui` to your app dependencies.

```dart
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  Uaepass.initSandbox(appScheme: 'com.example.myapp.uaepass');

  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: UaepassLoginButton())),
    ),
  );
}
```

The public sandbox uses UAE PASS staging credentials and the registered `https://localhost:8000` callback. Use a UAE PASS staging account. The repository [example app](example/) comes with the `poc` scheme already configured. [UAE PASS staging authentication guide](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)

## Connect your backend

For production or private staging, register your redirect URI with UAE PASS and configure the SDK.

```dart
final client = Uaepass.init(
  env: UaePassEnv.prod,
  appScheme: 'com.example.myapp.uaepass',
  clientId: 'your-client-id',
  redirectUri: 'https://login.example.com/uaepass/callback',
);
```

In your sign-in handler, call `authorize()` and send a successful grant to your backend. Handle `UaepassAuthorizationCancelled` and `UaepassAuthorizationFailure` as appropriate for your UI. The branded `UaepassLoginButton.authorize(onResult: ...)` provides the same result.

```dart
final result = await client.authorize(context);
if (result case UaepassAuthorizationSuccess(:final authorization)) {
  await exchangeWithBackend(authorization);
}
```

`exchangeWithBackend` is a function you supply. Send the grant's one-time `code` and `redirectUri` to your backend. The backend holds your UAE PASS secret, exchanges the code, and establishes your app's session. [UAE PASS mobile integration](https://docs.uaepass.ae/feature-guides/authentication/mobile-application/guide/api)

For a combined flow, pass the backend function to `login()`. The function returns a `UaepassSession` with the user profile and an optional token. A `UaepassLoginSuccess` contains that session. `UaepassLoginButton(exchangeCode: ..., onResult: ...)` offers the same convenience flow. The public sandbox uses its built-in exchange when you omit the function.

```dart
final result = await client.login(context, exchangeCode: exchangeWithBackend);
```

## Upgrade from 0.0.x

- Move the client secret to your backend and pass your registered `redirectUri` to `Uaepass.init`. Use `authorize()` with your app's backend flow or pass `exchangeCode` to the `login()` convenience method. Use `Uaepass.initSandbox` for the public staging demo.
- Remove older callback forwarding from `MainActivity`, `AppDelegate`, or `SceneDelegate`. Keep the platform URL registration for your app scheme.
- If your app only used the legacy InAppWebView ProGuard workaround for `uaepass`, remove that setting. The package now uses `webview_flutter`.
- Use `onResult` when handling a specific sign-in attempt. The existing `onCallback` is available for consumers that only need notification that an attempt finished.

## Maintain the package

Run `flutter analyze`, `flutter test`, and `flutter pub publish --dry-run` from `packages/flutter/`. The [example](example/) also has its own Flutter tests.

The sign-in button artwork comes from the [UAE PASS button assets](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines/button-assets).
