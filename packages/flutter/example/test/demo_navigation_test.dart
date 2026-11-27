import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';
import 'package:uaepass_example/home/demo_home.dart';
import 'package:uaepass_example/main.dart';
import 'package:uaepass_example/sign_in/backend_response.dart';
import 'package:uaepass_example/sign_in/sandbox_sign_in.dart';
import 'package:uaepass_example/signing/staging_signing.dart';
import 'package:uaepass_example/signing/signing_transaction.dart';
import 'package:uaepass_example/staging_config.dart';

void main() {
  testWidgets('the home switch enables signing and keeps sign-in available', (
    tester,
  ) async {
    await tester.pumpWidget(const UaePassDemo());
    final signIn = find.widgetWithText(ListTile, 'Try sign-in');
    final signing = find.widgetWithText(ListTile, 'Sign a document');
    final toggle = find.widgetWithText(SwitchListTile, 'Use local backend');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.widget<ListTile>(signIn).onTap, isNotNull);
    expect(tester.widget<ListTile>(signing).enabled, isFalse);
    expect(
      find.text('Enable the local backend to sign a document.'),
      findsOneWidget,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(tester.widget<ListTile>(signIn).onTap, isNotNull);
    expect(tester.widget<ListTile>(signing).enabled, isTrue);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SandboxSignIn>(find.byType(SandboxSignIn)).exchangeCode,
      isNotNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(signing);
    await tester.pumpAndSettle();
    expect(find.byType(UaePassSigningButton), findsOneWidget);
    await tester.tap(find.text('Advanced'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(signing);
    await tester.pumpAndSettle();
    final levels = find.byType(SegmentedButton<DemoSignatureLevel>);
    expect(
      tester.widget<SegmentedButton<DemoSignatureLevel>>(levels).selected,
      {DemoSignatureLevel.qualified},
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(signing).onTap, isNull);
  });

  testWidgets('signing retries the failed step only when requested', (
    tester,
  ) async {
    final requests =
        <({String method, String path, String? code, String? token})>[];
    var authorizations = 0;
    var available = false;
    var checkAvailable = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StagingSigning(
          authorize: (_) async {
            authorizations++;
            return UaePassSuccess(
              UaePassAuthorizationGrant(
                code: 'fixture-code',
                redirectUri: Uri.parse('https://localhost:8000'),
              ),
            );
          },
          requestBackend:
              (path, {required method, body, transactionToken}) async {
                requests.add((
                  method: method,
                  path: path,
                  code: body?['code'],
                  token: transactionToken,
                ));
                if (!available || (method == 'POST' && !checkAvailable)) {
                  throw const BackendConnectionException();
                }
                final uri = Uri(path: path.split('?').first);
                final json = <String, Object?>{
                  if (method == 'PUT') 'transactionId': uri.pathSegments.last,
                  'signatureLevel': 'advanced',
                  'status': 'signed',
                };
                return BackendResponse(
                  200,
                  Uint8List.fromList(utf8.encode(jsonEncode(json))),
                );
              },
        ),
      ),
    );
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(UaePassSigningButton));
    await tester.pumpAndSettle();
    expect(find.text(backendUnavailableMessage(false)), findsOneWidget);
    expect(Uri.parse(requests.single.path).queryParameters, {
      'level': 'advanced',
      'locale': 'en',
    });
    expect(requests.single.code, 'fixture-code');
    expect(requests.single.token, matches(r'^[a-zA-Z0-9_-]{32}$'));

    available = true;
    await tester.pump(const Duration(minutes: 1));
    expect(requests, hasLength(1));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
    expect(requests[1].path, requests[0].path);
    expect(requests[1].token, requests[0].token);
    expect(requests[1].code, isNull);
    expect(authorizations, 1);
    expect(requests[2].method, 'POST');
    expect(requests[2].path, endsWith('/check'));
    expect(find.text('Retry'), findsOneWidget);

    checkAvailable = true;
    await tester.pump(const Duration(minutes: 1));
    expect(requests, hasLength(3));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(4));
    expect(requests[3], requests[2]);
    expect(find.text('Signed PDF verified.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('pending approval resumes without another authorization', (
    tester,
  ) async {
    const channel = MethodChannel('ae.uaepass/flutter_auth/callbacks');
    final messenger = tester.binding.defaultBinaryMessenger;
    var approvalLaunches = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setCallbackScheme' && call.arguments != null) {
        approvalLaunches++;
        throw PlatformException(code: 'fixture-unavailable');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final starts = <({String path, String? code, String? token})>[];
    var authorizations = 0;
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StagingSigning(
          authorize: (_) async {
            authorizations++;
            return UaePassSuccess(
              UaePassAuthorizationGrant(
                code: 'fixture-code',
                redirectUri: Uri.parse('https://localhost:8000'),
              ),
            );
          },
          requestBackend:
              (path, {required method, body, transactionToken}) async {
                final response = switch (method) {
                  'PUT' => {
                    'transactionId': Uri.parse(path).pathSegments.last,
                    'status': 'pending',
                    'approvalUri': 'https://stg-id.uaepass.ae/trustedx-resources/esignsp/v2/ui?signerProcessId=fixture-process',
                    'finishCallbackUri': 'http://localhost:8787/signing/finish',
                  },
                  'POST' => {'status': ++checks == 1 ? 'pending' : 'signed'},
                  _ => fail('Unexpected request method $method'),
                };
                if (method == 'PUT') {
                  starts.add((
                    path: path,
                    code: body?['code'],
                    token: transactionToken,
                  ));
                }
                return BackendResponse(
                  200,
                  Uint8List.fromList(utf8.encode(jsonEncode(response))),
                );
              },
        ),
      ),
    );
    await tester.tap(find.byType(UaePassSigningButton));
    await tester.pumpAndSettle();
    expect(starts.single.code, 'fixture-code');
    expect(checks, 1);

    final resume = find.text('Return to UAE PASS');
    expect(resume, findsOneWidget);
    await tester.tap(resume);
    await tester.pumpAndSettle();

    expect(starts, hasLength(2));
    expect(starts.last, (
      path: starts.first.path,
      code: null,
      token: starts.first.token,
    ));
    expect(authorizations, 1);
    expect(approvalLaunches, 2);
    expect(checks, 2);
    expect(resume, findsNothing);
    expect(find.text('View signed PDF'), findsOneWidget);
  });

  testWidgets(
    'signing defaults to Qualified and lets the user select Advanced',
    (tester) async {
      final webSandbox = WebSandbox(
        null,
        const UaePassCancelled(),
        SigningTransaction.start(DemoSignatureLevel.advanced),
      )..takeAuthorization();
      await tester.pumpWidget(
        MaterialApp(home: StagingSigning(webSandbox: webSandbox)),
      );
      final control = find.byType(SegmentedButton<DemoSignatureLevel>);
      expect(
        tester.widget<SegmentedButton<DemoSignatureLevel>>(control).selected,
        {DemoSignatureLevel.qualified},
      );
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SegmentedButton<DemoSignatureLevel>>(control).selected,
        {DemoSignatureLevel.advanced},
      );
    },
  );

  testWidgets('home waits for demo sign-out before reporting success', (
    tester,
  ) async {
    final signOut = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: DemoHome(
          onLocaleChanged: (_) {},
          onSignOut: (_) => signOut.future,
        ),
      ),
    );
    final action = find.widgetWithText(TextButton, 'Sign out of UAE PASS');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    expect(tester.widget<TextButton>(action).onPressed, isNull);
    expect(find.text('Signed out of UAE PASS.'), findsNothing);

    signOut.complete();
    await tester.pumpAndSettle();
    expect(find.text('Signed out of UAE PASS.'), findsOneWidget);
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
  });

  testWidgets('reopening web sign-in starts with a fresh result', (
    tester,
  ) async {
    final webSandbox = WebSandbox(
      UaePassWebClient(
        UaePassWebConfiguration(
          environment: UaePassEnvironment.staging,
          clientId: 'sandbox_stage',
          redirectUri: Uri.parse('http://localhost:8000'),
        ),
      ),
      UaePassSuccess(
        UaePassAuthorizationGrant(
          code: 'fixture-code',
          redirectUri: Uri.parse('http://localhost:8000'),
        ),
      ),
    );
    await tester.pumpWidget(UaePassDemo(webSandbox: webSandbox));
    await tester.pumpAndSettle();
    expect(find.text('Authorization complete'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try sign-in'));
    await tester.pumpAndSettle();

    expect(find.byType(UaePassWebSignInButton), findsOneWidget);
    expect(find.text('Authorization complete'), findsNothing);
    expect(find.text('Sign out of UAE PASS'), findsNothing);
  });

  testWidgets('web sign-in explains which callback URLs it accepts', (
    tester,
  ) async {
    for (final redirectUrl in ['', 'http://staging.example.com/']) {
      await tester.pumpWidget(
        UaePassDemo(
          key: ValueKey(redirectUrl),
          webSandbox: WebSandbox.restore(redirectUrl: redirectUrl),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try sign-in'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Set UAEPASS_WEB_REDIRECT_URI to an HTTPS callback or http://localhost:8000 for staging.',
        ),
        findsOneWidget,
      );
      expect(find.byType(UaePassSignInButton), findsNothing);
      expect(find.byType(UaePassWebSignInButton), findsNothing);
    }
  });

  testWidgets('the opt-in demo waits for the backend and reports its outcome', (
    tester,
  ) async {
    final exchange = Completer<void>();
    final calls = <String>[];
    var succeeds = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SandboxSignIn(
          exchangeCode: (code) async {
            calls.add(code);
            if (!succeeds) throw StateError('backend error containing $code');
            await exchange.future;
          },
        ),
      ),
    );
    final button = find.byType(UaePassSignInButton);
    const code = 'secret-example-code';
    final grant = UaePassSuccess(
      UaePassAuthorizationGrant(
        code: code,
        redirectUri: Uri.parse('https://localhost:8000'),
      ),
    );
    tester.widget<UaePassSignInButton>(button).onResult(grant);
    await tester.pump();
    expect(find.text('Verifying authorization'), findsOneWidget);
    expect(tester.widget<UaePassSignInButton>(button).enabled, isFalse);
    tester.widget<UaePassSignInButton>(button).onResult(grant);
    expect(calls, [code]);

    exchange.complete();
    await tester.pumpAndSettle();
    expect(find.text('Backend exchange complete'), findsOneWidget);
    expect(tester.widget<UaePassSignInButton>(button).enabled, isTrue);

    succeeds = false;
    tester.widget<UaePassSignInButton>(button).onResult(grant);
    await tester.pumpAndSettle();
    expect(find.text('Backend exchange complete'), findsNothing);
    expect(find.textContaining(code), findsNothing);
    expect(tester.widget<UaePassSignInButton>(button).enabled, isTrue);
    expect(calls, [code, code]);
  });

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
    expect(
      tester
          .widget<UaePassSignInButton>(signInButton)
          .client
          .configuration
          .redirectUri,
      Uri.parse(
        const String.fromEnvironment(
          'UAEPASS_MOBILE_REDIRECT_URI',
          defaultValue: 'https://localhost:8000',
        ),
      ),
    );
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

  testWidgets('the demo reports authorization without exposing the code', (
    tester,
  ) async {
    final grant = UaePassAuthorizationGrant(
      code: 'example-code',
      redirectUri: Uri.parse('https://localhost:8000'),
    );

    await tester.pumpWidget(const UaePassDemo());
    final button = find.byType(UaePassSignInButton);
    for (final (trySignIn, completion) in const [
      ('Try sign-in', 'Authorization complete'),
      ('جرّب تسجيل الدخول', 'اكتمل التفويض'),
    ]) {
      await tester.tap(find.text(trySignIn));
      await tester.pumpAndSettle();
      tester
          .widget<UaePassSignInButton>(button)
          .onResult(UaePassSuccess(grant));
      await tester.pumpAndSettle();
      expect(find.text(completion), findsOneWidget);
      expect(find.textContaining(grant.code), findsNothing);
      expect(tester.widget<UaePassSignInButton>(button).enabled, isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      if (trySignIn == 'Try sign-in') {
        await tester.tap(find.text('العربية'));
        await tester.pumpAndSettle();
      }
    }
  });
}
