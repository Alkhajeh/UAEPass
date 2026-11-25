import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/src/branding/button_artwork.dart'
    show UaePassButtonArtwork, UaePassButtonLabel, UaePassButtonState;
import 'package:uaepass/src/presentation/branded_button.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  testWidgets('maps every wording, icon, and state to its official assets', (
    tester,
  ) async {
    final source = jsonDecode(
      File('assets/button-artwork.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final variants = source['buttons'] as Map<String, dynamic>;
    final densityCounts = <String, int>{};

    Future<void> check(UaePassButtonArtwork preview, String name) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: preview)));
      final asset = variants[name] as Map<String, dynamic>;
      final densities = asset['sources'] as Map<String, dynamic>;
      final image = tester.widget<Image>(find.byType(Image)).image;
      final path = switch (image) {
        AssetImage(:final keyName) => keyName,
        ExactAssetImage(:final keyName, :final scale) =>
          switch (densities.keys.single) {
            '4x' when scale == 4 => keyName,
            _ => fail('Unexpected exact asset scale for $name'),
          },
        _ => fail('Unexpected image provider for $name'),
      };
      expect(path, 'packages/uaepass/${asset['asset']}', reason: name);
      densityCounts[asset['asset'] as String] = densities.length;
    }

    for (final shape in UaePassButtonShape.values) {
      final shapeName = switch (shape) {
        UaePassButtonShape.rounded => 'rounded',
        UaePassButtonShape.fullyRounded => 'fully_rounded',
        UaePassButtonShape.squareCorners => 'square_corners',
      };
      for (final style in UaePassButtonStyle.values) {
        final styleName = style == UaePassButtonStyle.whiteOutline
            ? 'white_outline'
            : style.name;
        for (final state in UaePassButtonState.values) {
          final filename = '${shapeName}_${styleName}_${state.name}';
          await check(
            UaePassButtonArtwork.icon(shape: shape, style: style, state: state),
            'icon/$filename',
          );
          for (final language in ['en', 'ar']) {
            for (final label in UaePassButtonLabel.values) {
              final directory = switch (label) {
                UaePassButtonLabel.signIn => 'sign_in',
                UaePassButtonLabel.signUp => 'sign_up',
                UaePassButtonLabel.registerAccount => 'register_account',
                _ => label.name,
              };
              await check(
                UaePassButtonArtwork.text(
                  label: label,
                  locale: Locale(language),
                  shape: shape,
                  style: style,
                  state: state,
                ),
                '$directory/$language/$filename',
              );
            }
          }
        }
      }
    }
    expect(variants, hasLength(396));
    expect(densityCounts, hasLength(324));
    final files = Directory('assets/buttons')
        .listSync(recursive: true)
        .whereType<File>();
    expect(files, hasLength(852));

    final scales = await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final entry in densityCounts.entries) {
        expect(
          manifest.getAssetVariants(entry.key),
          hasLength(entry.value),
          reason: entry.key,
        );
      }
      final image = AssetImage(densityCounts.keys.first);
      return [
        for (final density in [1.0, 2.0, 3.0])
          await image.obtainKey(
            ImageConfiguration(bundle: rootBundle, devicePixelRatio: density),
          ),
      ];
    });
    expect(scales!.map((key) => key.scale), [1.0, 2.0, 3.0]);
    expect(scales[1].name, contains('/2.0x/'));
    expect(scales[2].name, contains('/3.0x/'));
  });

  testWidgets(
    'preserves artwork, tap target, semantics, and keyboard feedback',
    (tester) async {
      var actions = 0;

      Future<void> show({
        required bool enabled,
        Brightness brightness = Brightness.light,
        UaePassButtonStyle? style,
      }) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 190,
                child: BrandedButton(
                  label: UaePassButtonLabel.signIn,
                  style: style,
                  locale: const Locale('ar'),
                  onPressed: enabled ? () => actions++ : null,
                ),
              ),
            ),
          ),
        ),
      );

      String asset() =>
          (tester.widget<Image>(find.byType(Image)).image as AssetImage)
              .assetName;
      await show(enabled: true);
      expect(asset(), endsWith('sign_in/ar/rounded_white_outline_active.png'));
      expect(
        find.bySemanticsLabel('تسجيل الدخول بالهوية الرقمية'),
        findsOneWidget,
      );
      final artworkSize = tester.getSize(find.byType(Image));
      final targetSize = tester.getSize(find.byType(TextButton));
      expect(artworkSize.height, greaterThanOrEqualTo(30));
      expect(artworkSize.width / artworkSize.height, closeTo(304 / 50, .001));
      expect(targetSize.height, greaterThanOrEqualTo(48));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(asset(), endsWith('sign_in/ar/rounded_white_outline_focused.png'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(actions, 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextButton)),
      );
      await tester.pump();
      expect(asset(), endsWith('sign_in/ar/rounded_white_outline_pressed.png'));
      await gesture.cancel();
      await tester.pump();

      await show(enabled: false, brightness: Brightness.dark);
      await tester.pumpAndSettle();
      expect(asset(), endsWith('sign_in/ar/rounded_white_disabled.png'));
      await tester.tap(find.byType(TextButton));
      expect(actions, 1);

      await show(
        enabled: false,
        brightness: Brightness.dark,
        style: UaePassButtonStyle.black,
      );
      await tester.pumpAndSettle();
      expect(asset(), endsWith('sign_in/ar/rounded_black_disabled.png'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps sign-in artwork legible in both locales', (tester) async {
    var actions = 0;

    for (final (language, ratio, label) in const [
      ('en', 264 / 50, 'Sign in with UAE PASS'),
      ('ar', 304 / 50, 'تسجيل الدخول بالهوية الرقمية'),
    ]) {
      Future<void> show({required double width, double height = 60}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: BrandedButton(
                    label: UaePassButtonLabel.signIn,
                    locale: Locale(language),
                    onPressed: () => actions++,
                  ),
                ),
              ),
            ),
          );

      final image = find.byType(Image);
      final button = find.bySemanticsLabel(label);
      final minimumWidthWithMargin = 30 * ratio + 6;

      await show(width: minimumWidthWithMargin + 1);
      expect(button, findsOneWidget);
      final size = tester.getSize(image);
      expect(size.width, greaterThanOrEqualTo(140));
      expect(size.height, greaterThanOrEqualTo(30));
      expect(size.width / size.height, closeTo(ratio, .001));

      await show(width: minimumWidthWithMargin - 1);
      expect(tester.getSize(image), const Size.square(50));
      expect(
        (tester.widget<Image>(image).image as AssetImage).assetName,
        'assets/buttons/icon/rounded_white_outline_active.png',
      );
      await tester.tap(button);

      await show(width: 220, height: 35);
      expect(tester.getSize(image), const Size.square(35));
      expect(button, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(actions, 2);
  });

  testWidgets('uses the localized action for a square logo-only button', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrandedButton(
              icon: true,
              label: UaePassButtonLabel.signIn,
              style: UaePassButtonStyle.black,
              locale: const Locale('ar'),
              onPressed: () => actions++,
            ),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('تسجيل الدخول بالهوية الرقمية'),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(TextButton)), const Size.square(50));
    final image = tester.widget<Image>(find.byType(Image)).image as AssetImage;
    expect(image.assetName, 'assets/buttons/icon/rounded_black_active.png');
    await tester.tap(find.byType(TextButton));
    expect(actions, 1);
  });
}
