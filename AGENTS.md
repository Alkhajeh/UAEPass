# Repository guide

- Work on the Flutter plugin in `packages/flutter` and the runnable demo in `packages/flutter/example`. Run `flutter analyze` and `flutter test` from each directory. Run `flutter pub publish --dry-run` from the plugin directory when checking release contents.
- Keep `package:uaepass/uaepass.dart` as the consumer entry point. Document the host integration in the package README and demo-specific steps in the example README.
- Preserve authorization state and redirect validation, native callback cleanup, and the backend exchange boundary. Live provider secrets belong on the host's backend. The demo uses only UAE PASS public staging credentials.
- Keep bundled artwork traceable to `packages/flutter/assets/button-artwork.json`. When changing artwork, check the complete variant matrix with the existing button tests and verify English and Arabic in the demo.
