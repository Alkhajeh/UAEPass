import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uaepass/uaepass.dart';
import 'package:uaepass_example/main.dart' as app;

void main() {
  testWidgets('starts the example and loads the sign-in button artwork', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('UAE PASS'), findsOneWidget);
    expect(find.byType(UaepassLoginButton), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with UAE PASS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets(),
      contains('packages/uaepass/images/sign_in/normal_outline_en.png'),
    );
  });
}
