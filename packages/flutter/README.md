# uaepass

[![Generic badge](https://img.shields.io/badge/platform-android%20|%20ios%20-blue.svg)](https://pub.dev/packages/uaepass)

![Default](https://user-images.githubusercontent.com/12137414/216746446-74762242-d43e-4495-84c6-c73c29bf62f3.png)

## Installation

Requires Flutter 3.50.1 with Dart 3.14 or later, Android API 24 or later, and iOS 15 or later. The example uses CocoaPods on iOS and was verified with JDK 25 on Android.

In your `pubspec.yaml` file within your Flutter Project:

```yaml
dependencies:
  uaepass: <latest_version>
  material_ui: ^1.11.1
```

### iOS

Add the below to `info.plist`

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>uaepass</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>{custom App Scheme}</string>
        </array>
    </dict>
</array>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>uaepass</string>
    <string>uaepassstg</string>
</array>
```

Register the callback channel when Flutter initializes its engine and handle the URL in the scene delegate. Replace `poc` with the same scheme passed to `Uaepass.init`. [Example AppDelegate and SceneDelegate](example/ios/Runner/AppDelegate.swift) · [Example scene configuration](example/ios/Runner/Info.plist)

### Android

Add the below to `AndroidManifest.xml`

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="{custom App Scheme}" />
    <data android:host="success" />
    <data android:host="failure" />
</intent-filter>
```

```xml
<manifest>
   ...
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
         </intent>
        <package android:name="ae.uaepass.mainapp" />
        <package android:name="ae.uaepass.mainapp.stg" />
    </queries>
</manifest>
```

Use `singleTask` for the example's `MainActivity` so the callback resumes the WebView that started sign-in. Forward the callback using the same scheme passed to `Uaepass.init`. [Example MainActivity](example/android/app/src/main/kotlin/com/example/uaepass_example/MainActivity.kt) · [Example manifest](example/android/app/src/main/AndroidManifest.xml)

Set `redirectUri` to the callback registered for your UAE PASS client. The staging example uses the public sandbox client and a loopback callback that the app intercepts. When the staging app is unavailable on the test device, sign in through the embedded web form and confirm the request on a device with your UAE PASS staging account. [UAE PASS staging authentication guide](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)

## Use it

```dart
import 'package:uaepass/uaepass.dart';

UaepassLoginButton();
```

## Example

<?code-excerpt "basic.dart (basic-example)"?>

```dart
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  Uaepass.init(
    env: UaePassEnv.stg,
    appScheme: '{custom App Scheme}',
    clientId: 'sandbox_stage',
    clientSecret: 'sandbox_stage',
    redirectUri: 'https://localhost:8000',
  );
  runApp(
    const MaterialApp(
      home: Material(
        child: Center(
          child: UaepassLoginButton(),
        ),
      ),
    ),
  );
}

```
