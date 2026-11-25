# UAE PASS Flutter example

Run the example from this directory with an Android emulator, iOS simulator, or physical device selected. The example uses the local `uaepass` package.

```sh
flutter pub get
flutter run
```

- **Try sign-in** shows a provider-owned page using the SDK's sign-in button and the UAE PASS public staging sandbox. A live sign-in requires a [UAE PASS staging account](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/create-uaepass-user). With the staging app installed, the SDK opens it. Otherwise the SDK uses the embedded web flow, where approval can happen on a second device.
- **Explore buttons** works offline. Preview the selected artwork on a light or dark background and expand **Interaction states** to see focused, pressed, and disabled artwork. Copy a `UaePassSignInButton` snippet for any of the available artwork choices.
- **Preview sign-in outcomes** shows the cancellation, technical failure, and eligibility messages offline.

Switch between English and Arabic from the landing screen. The demo receives the grant from the sign-in button, shows its own loading indicator, and exchanges the code using the [public staging credentials](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/testing-credentials-for-poc). Real integrations perform the exchange on their own backend.

See the [package integration guide](../README.md) for host app setup and the backend exchange. For UAE PASS assessment, exercise both authorization paths in English and Arabic on staging devices and record successful and cancelled flows with a staging account intended for assessment.
