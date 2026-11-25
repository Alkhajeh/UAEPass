import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';
import 'package:uaepass_example/main.dart';
import 'package:uaepass_example/sign_in/sandbox_sign_in.dart';

void main() {
  testWidgets('navigates through the bilingual example offline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const UaePassDemo());
    await tester.pumpAndSettle();

    expect(find.text('UAE PASS example'), findsOneWidget);
    final signInButton = find.byType(UaePassSignInButton);
    expect(signInButton, findsNothing);

    await tester.tap(find.text('Try sign-in'));
    await tester.pumpAndSettle();
    expect(signInButton, findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with UAE PASS'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(find.text('مثال الهوية الرقمية'), findsOneWidget);
    await tester.tap(find.text('معاينة نتائج تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('قام المستخدم بإلغاء تسجيل الدخول'), findsOneWidget);
    expect(
      find.textContaining('يرجى الاتصال بـ التطبيق التجريبي'),
      findsOneWidget,
    );
    final message = tester.element(
      find.text('قام المستخدم بإلغاء تسجيل الدخول'),
    );
    expect(Directionality.of(message), TextDirection.rtl);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('استعرض الأزرار'));
    await tester.pumpAndSettle();
    expect(find.text('محتوى الزر'), findsOneWidget);
    expect(find.text('زوايا مستديرة'), findsOneWidget);
    expect(find.text('كبسولة'), findsOneWidget);
    expect(find.text('زوايا قائمة'), findsOneWidget);

    String artworkPath(Image image) => switch (image.image) {
      AssetImage(:final assetName) => assetName,
      ExactAssetImage(:final assetName) => assetName,
      _ => fail('Unexpected button artwork provider'),
    };
    String activeAsset() =>
        artworkPath(tester.widget(find.byType(Image).first));
    expect(
      activeAsset(),
      endsWith('sign_in/ar/rounded_white_outline_active.png'),
    );
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('داكنة'));
    await tester.pumpAndSettle();
    expect(activeAsset(), endsWith('sign_in/ar/rounded_white_active.png'));

    Future<void> choose(Finder menu, String label) async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    final contentMenu = find
        .byWidgetPredicate((widget) => widget is DropdownButton)
        .first;
    await choose(contentMenu, 'طلب المشاركة عبر الهوية الرقمية');
    await tester.tap(find.text('كبسولة'));
    await tester.tap(find.text('أسود سادة'));
    await tester.pumpAndSettle();

    final states = find.text('حالات التفاعل');
    await tester.tap(states);
    await tester.pumpAndSettle();
    expect(tester.widgetList<Image>(find.byType(Image)).map(artworkPath), [
      endsWith('authorize/ar/fully_rounded_black_active.png'),
      endsWith('authorize/ar/fully_rounded_black_focused.png'),
      endsWith('authorize/ar/fully_rounded_black_active.png'),
      endsWith('authorize/ar/fully_rounded_white_outline_disabled.png'),
    ]);
    expect(find.text('في حالة التركيز'), findsOneWidget);
    expect(find.text('تم الضغط'), findsOneWidget);
    expect(find.text('معطّل'), findsOneWidget);
    await tester.tap(states);
    await tester.pumpAndSettle();
    final copy = find.text('نسخ كود Flutter');
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('UaePassSignInButtonContent.authorize'),
    );
    await choose(contentMenu, 'شعار فقط');
    expect(find.text('مربع بزوايا مستديرة'), findsOneWidget);
    expect(find.text('دائرة'), findsOneWidget);
    expect(find.text('مربع'), findsOneWidget);
    expect(find.text('كبسولة'), findsNothing);
    expect(activeAsset(), endsWith('icon/fully_rounded_black_active.png'));

    String? clipboard;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        clipboard = arguments['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.scrollUntilVisible(
      copy,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy.hitTestable());
    await tester.pumpAndSettle();
    expect(clipboard, contains('UaePassSignInButton('));
    expect(clipboard, contains('UaePassSignInButtonContent.logoOnly'));
    expect(clipboard, contains('onResult: handleAuthorizationResult'));
    expect(clipboard, isNot(contains('exchangeCode')));
    expect(clipboard, contains('style: UaePassButtonStyle.black'));
    expect(clipboard, contains('UaePassButtonShape.fullyRounded'));
    expect(clipboard, contains("Locale('ar')"));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the demo owns loading and session creation after authorization',
    (tester) async {
      final tokenResponse = Completer<http.Response>();
      final exchangeRequests = <http.Request>[];
      final grant = UaePassAuthorizationGrant(
        code: 'example-code',
        redirectUri: Uri.parse('https://localhost:8000'),
      );

      await tester.pumpWidget(const MaterialApp(home: SandboxSignIn()));
      final button = find.byType(UaePassSignInButton);
      http.runWithClient(
        () => tester
            .widget<UaePassSignInButton>(button)
            .onResult(UaePassSuccess(grant)),
        () => MockClient((request) async {
          exchangeRequests.add(request);
          if (request.url.path == '/idshub/token') {
            return tokenResponse.future;
          }
          return http.Response(
            '{"sub":"example","fullnameEN":"Example User"}',
            200,
          );
        }),
      );

      await tester.pump();
      final tokenRequest = exchangeRequests.single;
      expect(tokenRequest.url.path, '/idshub/token');
      expect(
        tokenRequest.url.queryParameters,
        containsPair('code', grant.code),
      );
      expect(
        tokenRequest.url.queryParameters,
        containsPair('redirect_uri', grant.redirectUri.toString()),
      );
      expect(button, findsNothing);
      expect(find.bySemanticsLabel('Setting up your session'), findsOneWidget);

      tokenResponse.complete(
        http.Response('{"access_token":"example-token"}', 200),
      );
      await tester.pumpAndSettle();
      expect(exchangeRequests, hasLength(2));
      final userRequest = exchangeRequests.last;
      expect(userRequest.url.path, '/idshub/userinfo');
      expect(userRequest.headers['authorization'], 'Bearer example-token');
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Example User'), findsOneWidget);
    },
  );
}
