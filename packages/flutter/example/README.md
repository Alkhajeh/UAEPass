# UAE PASS Flutter example

Run the example from this directory with an Android emulator, iOS simulator, or physical device selected. The example uses the local `uaepass` package.

```sh
flutter pub get
flutter run
```

- **Try sign-in** starts authorization with the UAE PASS public staging sandbox. Install the official [UAE PASS staging app](https://docs.uaepass.ae/resources/staging-apps) and create a [staging account](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/create-uaepass-user). With the staging app installed on the same device, the SDK opens it. You can also use the embedded web flow and approve from a second device with the staging app.
- **Explore buttons** works offline. Preview the selected artwork on a light or dark background and expand **Interaction states** to see focused, pressed, and disabled artwork. Copy a `UaePassSignInButton` snippet for any of the available artwork choices.
- **Preview sign-in outcomes** shows the cancellation, technical failure, and eligibility messages offline.

Switch between English and Arabic from the landing screen. After a valid callback, the demo displays **Authorization complete** and discards the one-time code. The example registers `com.example.uaepass.flutterdemo` as its callback scheme in Dart, the Android manifest, and the iOS plist.

See the [package integration guide](../README.md#4-complete-sign-in-on-your-backend) for exchanging the code and establishing an app session. For UAE PASS assessment, exercise both authorization paths in English and Arabic on staging devices and record successful and cancelled flows with a staging account intended for assessment.

## Verify the local backend

The optional debug flow uses the same public UAE PASS staging client and registered redirect URI as the default demo. The backend runs on your development machine at `127.0.0.1:8787`.

1. From `packages/node`, run `npm ci` and `npm run build`. Set `UAEPASS_CLIENT_ID` to `sandbox_stage`, `UAEPASS_REDIRECT_URI` to `https://localhost:8000`, and `UAEPASS_CLIENT_SECRET` to the public sandbox secret. Then run `npm run example`. [UAE PASS staging walkthrough](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)
2. Use an iOS simulator or an Android device connected through ADB. For Android, run `adb reverse tcp:8787 tcp:8787` on the development machine.
3. From the Flutter example directory, run `flutter run --dart-define=UAEPASS_LOCAL_BACKEND=true`. Select **Try sign-in** and approve the request with a UAE PASS staging account.

**Backend exchange complete** indicates that the sample exchanged the code and fetched a valid UAE PASS profile. The sample returns a success flag to the demo. Keep production credentials in your own backend and use its HTTPS endpoint to establish an app session.
