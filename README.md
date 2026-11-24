# UAE PASS SDKs

The `uaepass` Flutter plugin integrates UAE PASS sign-in on Android and iOS.

- [Flutter package](packages/flutter/) has installation and integration instructions.
- [Flutter example](packages/flutter/example/) demonstrates staging sign-in and the button styles.

## Develop the Flutter package

Run Flutter commands from the package directory.

```sh
cd packages/flutter
flutter pub get
flutter analyze
flutter test
flutter pub publish --dry-run
```

Run the example from its own directory with an Android or iOS device selected.

```sh
cd packages/flutter/example
flutter pub get
flutter analyze
flutter test
flutter run
```

Before publishing, verify app handoff and web fallback with UAE PASS staging on Android and iOS. Confirm that the official button artwork may be redistributed with the package.
