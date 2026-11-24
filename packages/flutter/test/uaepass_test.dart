import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uaepass/src/model/uaepass_buttons.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles the artwork for every sign-in button variant', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    for (final language in UaepassLang.values) {
      for (final type in UaepassButtonType.values) {
        for (final theme in UaePassButtonTheme.values) {
          final image = UaepassButtons.signInButton(
            lang: language,
            type: type,
            theme: theme,
          );
          expect(assets, contains(image));
        }
      }
    }
  });
}
