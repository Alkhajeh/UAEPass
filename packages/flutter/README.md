# UAE PASS for Flutter

Add UAE PASS sign-in to your app with the official English or Arabic button. The SDK opens the UAE PASS app when available and uses a WebView otherwise. Your app owns the sign-in page and session.

Requires Flutter 3.50.1 or later and Dart 3.14 or later. Supports Android API 24 or later and iOS 15 or later.

## Install and add the sign-in button

```sh
flutter pub add uaepass
```

Create one client for your integration and add the button to your sign-in page.

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

final signInButton = UaePassSignInButton<ServiceSession>(
  client: client,
  exchangeCode: exchangeGrantOnBackend,
  onResult: handleSignInResult,
);
```

Provide `ServiceSession` and both callbacks in your app. `exchangeGrantOnBackend` sends the one-time grant to your backend, which exchanges it with UAE PASS and establishes your app's session. Return `UaePassSuccess(session)` or a typed `UaePassFailure` from the callback. `handleSignInResult` receives the outcome, including cancellation. The button disables itself during sign-in and the exchange. Keep any UAE PASS client secret on your backend.

Use `MaterialApp` from `package:material_ui/material_ui.dart` to provide the theme and localizations used by the button and authorization route. For English and Arabic, configure `supportedLocales` and `GlobalMaterialLocalizations.delegates`. The [example app](example/) shows both locales. [Flutter Material UI setup](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)

## Configure your host app

Obtain a UAE PASS client ID, registered HTTPS redirect URI, and approved scopes for your environment. The default scope requests the user's general profile. Pass `scopes` if your integration has a different approved set. Set `redirectUri` to the registered HTTPS URI that returns the authorization result. Set `callbackScheme` to a unique lowercase custom scheme registered in your app for the return from the UAE PASS app. Share it with UAE PASS as required by your integration. Use the same scheme in Dart and the platform configuration. [UAE PASS mobile integration guide](https://docs.uaepass.ae/feature-guides/authentication/mobile-application)

### Android

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

### iOS

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

## Start UAE PASS sign-in from Dart

The client methods start the same UAE PASS authentication as the widget. Call `authorize(context)` for a typed result containing a one-time code and redirect URI. Call `login<T>()` to also invoke your backend exchange callback and return the completed session.

```dart
final result = await client.login<ServiceSession>(
  context,
  exchangeCode: exchangeGrantOnBackend,
);

switch (result) {
  case UaePassSuccess(:final value):
    openSession(value);
  case UaePassCancelled():
    return;
  case UaePassFailure(:final reason):
    showSignInFailure(reason);
}
```

Both methods accept an optional `Locale`. They use the app locale by default and fall back to English for locales other than Arabic. One attempt can be active per Flutter engine. Use `UaePassSignInMessages.forResult` to show localized outcome messages with your service provider's name.

## Choose the sign-in button artwork

Choose `signIn` (the default), `login`, `registerAccount`, `signUp`, `authorize`, or `logoOnly` for `content`. Each choice starts UAE PASS authentication and calls the supplied backend exchange callback. Choose the wording that matches the action on your screen. Use the registration artwork on your account creation page. The logo-only option has a localized sign-in label for screen readers. [UAE PASS button usage guidance](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines/dos-and-donts/sign-in-and-sign-up)

```dart
UaePassSignInButton<ServiceSession>(
  client: client,
  exchangeCode: exchangeGrantOnBackend,
  onResult: handleSignInResult,
  content: UaePassSignInButtonContent.logoOnly,
  shape: UaePassButtonShape.fullyRounded,
)
```

Omit `style` to use white with outline in a light theme or solid white in a dark theme. Set it explicitly when the local background differs from the theme. Set `enabled: false` to disable sign-in. Text artwork scales to the available width and takes up to 366 logical pixels at natural size, including clear space. Logo-only artwork fits a 50-logical-pixel square. [UAE PASS button guidelines](https://docs.uaepass.ae/guidelines/design-guidelines/button-guidelines)

## Example app

Run the [example app](example/) to try staging sign-in, preview localized outcomes offline, or explore the official button variations and copy a Flutter snippet.
