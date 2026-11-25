# UAE PASS Flutter example

The example uses the local `uaepass` package. Install the UAE PASS staging app and create a staging account to try authorization. You can verify the callback with the Flutter app alone or connect a backend to test the code exchange. [Staging app](https://docs.uaepass.ae/resources/staging-apps) · [Staging account](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/create-uaepass-user)

## Redirect configuration

The demo passes the redirect URI to the SDK in Dart. Android and iOS default to `https://localhost:8000`. The web command below sets `http://localhost:8000` for local staging. The mobile `callbackScheme` is the app-return scheme registered in Dart, Android, and iOS. [Flutter integration guide](../README.md#2-register-the-callback)

If you prefer a file for these public build settings, the repository checkout includes an optional `.env.example` in this directory. Copy it to `.env` and use `--dart-define-from-file=.env` in place of the redirect flag. [Flutter support for env files](https://docs.flutter.dev/release/release-notes/release-notes-3.13.0)

## Run on Android or iOS

Run these commands from this directory with an emulator, simulator, or physical device selected.

```sh
flutter pub get
flutter run
```

To use a different registered mobile redirect, pass `--dart-define=UAEPASS_MOBILE_REDIRECT_URI=https://your-domain.example/callback` with your exact URI.

- **Try sign-in** starts authorization with the UAE PASS public staging sandbox. With the staging app installed on the same device, the SDK opens it. You can also use the embedded browser flow and approve from a second device with the staging app.
- **Explore buttons** works offline. Preview the selected artwork on a light or dark background and expand **Interaction states** to see focused, pressed, and disabled artwork. Copy a `UaePassSignInButton` snippet for any of the available artwork choices.
- **Preview sign-in outcomes** shows the cancellation, technical failure, and eligibility messages offline.

Switch between English and Arabic from the landing screen. After a valid callback, the demo displays **Authorization complete** and discards the one-time code. The example registers `com.example.uaepass.flutterdemo` as its callback scheme in Dart, the Android manifest, and the iOS plist.

See the [package integration guide](../README.md#4-complete-sign-in-on-your-backend) for exchanging the code and establishing an app session. For UAE PASS assessment, exercise both authorization paths in English and Arabic on staging devices and record successful and cancelled flows with a staging account intended for assessment.

## Run on the web

Run UAE PASS staging at `http://localhost:8000` without a local certificate.

```sh
flutter pub get
flutter run -d chrome --dart-define=UAEPASS_WEB_REDIRECT_URI=http://localhost:8000
```

Select **Try sign-in** and approve in the staging app. **Authorization complete** indicates a valid callback. **Sign out of UAE PASS** ends the provider's browser session. [UAE PASS web logout](https://docs.uaepass.ae/feature-guides/authentication/web-application/4.-web-single-sign-on-sso-and-logout-user-session-from-uae-pass)

### Host the web demo over HTTPS

Set `UAEPASS_WEB_REDIRECT_URI` to your exact registered HTTPS callback URL. Build the demo and serve `build/web` at that URL. [UAE PASS staging walkthrough](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)

```sh
flutter pub get
flutter build web --dart-define=UAEPASS_WEB_REDIRECT_URI=https://your-domain.example/callback
```

## Optional backend exchange

To test the full staging exchange, add `--dart-define=UAEPASS_LOCAL_BACKEND=true` to the run or build command. You can use a staging backend written in any language. The demo sends `POST /auth/uaepass` with JSON `{"code":"…"}`. Configure your backend with the public sandbox credentials, keep the client secret on the server, and use the exact redirect URI the demo used to start authorization. After exchanging the code and fetching the profile, respond with HTTP `200` and JSON `{"ok":true}`. [Backend exchange steps](../README.md#4-complete-sign-in-on-your-backend) · [UAE PASS staging credentials](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)

- **Local web.** Run the backend at `127.0.0.1:8787`. The Flutter development server forwards `/auth/uaepass` to it.
- **Hosted web.** Serve `/auth/uaepass` on the same HTTPS origin as the demo.
- **Mobile.** Run the demo in debug mode and start the backend at `127.0.0.1:8787`. The iOS simulator can reach it directly. For an Android emulator or ADB-connected Android device, run `adb reverse tcp:8787 tcp:8787`.

Select **Try sign-in** and approve in the staging app. **Backend exchange complete** means the demo received a successful exchange response. For a production integration, use your own backend to establish an app session. [Flutter integration guide](../README.md#4-complete-sign-in-on-your-backend)
