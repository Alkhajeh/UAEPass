# UAE PASS Flutter example

This app signs in with the public UAE PASS sandbox on Android and iOS. It uses the `poc` URL scheme and includes the platform configuration needed to resume sign-in after the UAE PASS app opens. The iOS example uses Swift Package Manager.

## Run the example

From `packages/flutter/example/`, choose a device and run:

```sh
flutter pub get
flutter run
```

Use a UAE PASS staging account. With the staging app installed, the example hands off to it during sign-in. Otherwise, the web form prompts you to confirm the request on a device with the staging app. [UAE PASS staging authentication guide](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)

See the [package README](../README.md) for platform configuration and the backend exchange used by production integrations.
