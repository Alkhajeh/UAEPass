import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/src/signing/review_document_page.dart';
import 'package:uaepass/uaepass.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  const channel = MethodChannel('ae.uaepass/flutter_auth/callbacks');
  final client = UaePassClient(
    UaePassConfiguration(
      environment: UaePassEnvironment.staging,
      redirectUri: Uri.parse('https://service.example/callback'),
      clientId: 'app-client',
      callbackScheme: 'poc',
    ),
  );
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  late _TestWebViewPlatform webViews;
  late List<(String, Object?)> nativeCalls;
  late bool appInstalled;
  late BuildContext hostContext;

  setUp(() {
    final previousPlatform = WebViewPlatform.instance;
    WebViewPlatform.instance = webViews = _TestWebViewPlatform();
    nativeCalls = [];
    appInstalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add((call.method, call.arguments));
      return switch (call.method) {
        'isAppInstalled' => appInstalled,
        'launchApp' => true,
        _ => null,
      };
    });
    addTearDown(() {
      if (previousPlatform != null) WebViewPlatform.instance = previousPlatform;
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  Future<void> openHost(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          hostContext = context;
          return const Scaffold();
        },
      ),
    ),
  );

  testWidgets('ends the embedded UAE PASS session at the registered return', (
    tester,
  ) async {
    await openHost(tester);
    final logout = client.logout(hostContext);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    expect(
      view.requests.single,
      Uri.https('stg-id.uaepass.ae', '/idshub/logout', {
        'redirect_uri': client.configuration.redirectUri.toString(),
      }),
    );
    expect(await client.logout(hostContext), isFalse);
    expect(
      await view.navigation.navigate(client.configuration.redirectUri),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
    expect(await logout, isTrue);
  });

  testWidgets('reports a provider logout error as unsuccessful', (
    tester,
  ) async {
    await openHost(tester);
    final logout = client.logout(hostContext);
    await tester.pumpAndSettle();
    final error = client.configuration.redirectUri.replace(
      queryParameters: {'error': 'invalid_request'},
    );
    expect(
      await webViews.controllers.single.navigation.navigate(error),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
    expect(await logout, isFalse);
  });

  Future<void> redirect(
    WidgetTester tester, {
    String? code,
    String? error,
  }) async {
    final view = webViews.controllers.last;
    final callback = client.configuration.redirectUri.replace(
      queryParameters: {
        'state': view.requests.first.queryParameters['state']!,
        'code': ?code,
        'error': ?error,
      },
    );
    expect(
      await view.navigation.navigate(callback),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
  }

  Future<ByteData?> deliverPlatformCall(String method, String value) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, value)),
        null,
      );

  Future<ByteData?> deliverCallback(Uri uri) =>
      deliverPlatformCall('onCallback', uri.toString());

  final appHandoff = Uri(
    scheme: 'uaepass',
    host: 'digitalid-users-ids',
    queryParameters: {
      'successURL': 'https://stg-id.uaepass.ae/resume?status=success',
      'failureURL': 'https://stg-id.uaepass.ae/resume?status=failure',
    },
  );

  final approval = Uri.https(
    'stg-id.uaepass.ae',
    '/trustedx-resources/esignsp/v2/ui',
    {'signerProcessId': 'fixture-process'},
  );
  final finish = Uri.parse('http://localhost:8787/signing/finish?app=demo');
  const signing = UaePassSigningClient(environment: UaePassEnvironment.staging);

  Future<void> openSigning() => signing.openApproval(
    hostContext,
    approval,
    finishCallbackUri: finish,
    callbackScheme: client.configuration.callbackScheme,
  );

  testWidgets('resumes signing in the same WebView and intercepts its return', (
    tester,
  ) async {
    await openHost(tester);
    var returned = false;
    final attempt = openSigning().then((_) => returned = true);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    expect(view.requests, [approval]);

    expect(
      await view.navigation.navigate(appHandoff),
      NavigationDecision.prevent,
    );
    final launch = Uri.parse(nativeCalls.last.$2! as String);
    final callback = Uri.parse(launch.queryParameters['successURL']!);
    expect(callback.scheme, client.configuration.callbackScheme);
    await deliverCallback(Uri.parse('poc://success?state=unrelated'));
    expect(view.requests, [approval]);
    await deliverCallback(callback);
    await tester.pump();
    final resume = Uri.parse(appHandoff.queryParameters['successURL']!);
    expect(view.requests, [approval, resume]);
    expect(returned, isFalse);

    final callbackUri = finish.replace(
      queryParameters: {
        ...finish.queryParameters,
        'signer_process_id': 'fixture-process',
        'status': 'canceled',
      },
    );
    expect(
      await view.navigation.navigate(callbackUri),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
    expect(await attempt, isTrue);
    expect(view.requests, [approval, resume]);
    expect(nativeCalls.last, ('setCallbackScheme', null));
  });

  testWidgets('routes a provider PDF popup to review and keeps approval open', (
    tester,
  ) async {
    await openHost(tester);
    final approvalAttempt = openSigning();
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    final document = approval.replace(
      path: '/trustedx-resources/esignsp/v2/ui/documents/0',
      queryParameters: {'x_correlation_id': 'fixture-correlation'},
    );

    expect(
      await view.navigation.navigate(
        document.replace(host: 'elsewhere.example'),
        isMainFrame: false,
      ),
      NavigationDecision.navigate,
    );
    expect(
      await view.navigation.navigate(document, isMainFrame: false),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
    expect(find.text('Review document'), findsOneWidget);
    expect(view.requests, [approval]);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await approvalAttempt;
  });

  test('accepts a 20 MiB PDF for mobile approval review', () async {
    final document = approval.replace(
      path: '/trustedx-resources/esignsp/v2/ui/documents/0',
      queryParameters: {'x_correlation_id': 'fixture-correlation'},
    );
    final pdf = Uint8List(20 * 1024 * 1024)..setAll(0, '%PDF-'.codeUnits);
    final loaded = await http.runWithClient(
      () => fetchApprovalPdf(WebViewController(), document, approval),
      () => MockClient.streaming((request, _) async {
        expect(request.url, document);
        return http.StreamedResponse(
          Stream.value(pdf),
          200,
          contentLength: pdf.length,
          headers: {'content-type': 'application/pdf'},
        );
      }),
    );
    expect(loaded.length, pdf.length);
    expect(loaded.take(5), '%PDF-'.codeUnits);
  });

  testWidgets('rejects an unrelated signing return and allows dismissing', (
    tester,
  ) async {
    await openHost(tester);
    final attempt = openSigning();
    final failure = expectLater(
      attempt,
      throwsA(isA<UaePassSigningLaunchException>()),
    );
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    final unrelated = finish.replace(
      queryParameters: {
        ...finish.queryParameters,
        'signer_process_id': 'different-process',
      },
    );
    expect(
      await view.navigation.navigate(unrelated),
      NavigationDecision.prevent,
    );
    await tester.pumpAndSettle();
    await failure;
    expect(nativeCalls.last, ('setCallbackScheme', null));

    final dismissed = openSigning();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await dismissed;
    expect(nativeCalls.last, ('setCallbackScheme', null));
  });

  testWidgets(
    'authorizes through the web flow and removes the Dart callback handler',
    (tester) async {
      await openHost(tester);
      final attempt = client.authorize(
        hostContext,
        locale: const Locale('ar', 'AE'),
      );
      await tester.pumpAndSettle();
      final request = webViews.controllers.single.requests.single;
      expect(request.queryParameters['ui_locales'], 'ar');
      expect(
        request.queryParameters['acr_values'],
        'urn:safelayer:tws:policies:authentication:level:low',
      );
      expect(nativeCalls, [
        ('setCallbackScheme', 'poc'),
        ('isAppInstalled', 'staging'),
      ]);
      final callback = Uri.parse('poc://success');
      expect(await deliverCallback(callback), isNotNull);

      await redirect(tester, code: 'one-time-code');
      final result = await attempt;
      expect(result, isA<UaePassSuccess<UaePassAuthorizationGrant>>());
      final grant = (result as UaePassSuccess<UaePassAuthorizationGrant>).value;
      expect(grant.code, 'one-time-code');
      expect(grant.redirectUri, client.configuration.redirectUri);
      expect(nativeCalls.last, ('setCallbackScheme', null));
      expect(await deliverCallback(callback), isNull);
    },
  );

  testWidgets('resumes the same web view after an installed-app handoff', (
    tester,
  ) async {
    appInstalled = true;
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    final request = view.requests.single;
    final state = request.queryParameters['state'];
    expect(
      request.queryParameters['acr_values'],
      'urn:digitalid:authentication:flow:mobileondevice',
    );

    final success = Uri.parse(
      'https://stg-ids.uaepass.ae/resume?status=success',
    );
    final failure = Uri.parse(
      'https://stg-id.uaepass.ae/resume?status=failure',
    );
    final handoff = Uri(
      scheme: 'uaepass',
      host: 'digitalid-users-ids',
      queryParameters: {'successURL': '$success', 'failureURL': '$failure'},
    );
    expect(await view.navigation.navigate(handoff), NavigationDecision.prevent);
    final (method, arguments) = nativeCalls.last;
    expect(method, 'launchApp');
    final launchUri = Uri.parse(arguments! as String);
    expect(launchUri.scheme, 'uaepassstg');
    final callback = Uri.parse(launchUri.queryParameters['failureURL']!);
    expect(callback.scheme, 'poc');
    expect(callback.host, 'failure');
    expect(callback.queryParameters['state'], state);

    await deliverCallback(Uri.parse('poc://success?state=unrelated'));
    await tester.pump();
    expect(view.requests, [request]);
    await deliverCallback(callback);
    await tester.pump();
    await deliverCallback(callback);
    expect(webViews.controllers.single, same(view));
    expect(view.requests, [request, failure]);

    await redirect(tester, error: 'cancelledOnApp');
    expect(await attempt, isA<UaePassCancelled<UaePassAuthorizationGrant>>());
    expect(nativeCalls.last, ('setCallbackScheme', null));
  });

  testWidgets(
    'resumes the same web view and exchanges one grant after a successful handoff',
    (tester) async {
      appInstalled = true;
      await openHost(tester);
      final exchangedGrants = <UaePassAuthorizationGrant>[];
      final login = client.login<String>(
        hostContext,
        exchangeCode: (grant) async {
          exchangedGrants.add(grant);
          return const UaePassSuccess('app session');
        },
      );
      await tester.pumpAndSettle();
      final view = webViews.controllers.single;
      final initialRequest = view.requests.single;

      expect(
        await view.navigation.navigate(appHandoff),
        NavigationDecision.prevent,
      );
      final (method, arguments) = nativeCalls.last;
      expect(method, 'launchApp');
      final launchUri = Uri.parse(arguments! as String);
      final callback = Uri.parse(launchUri.queryParameters['successURL']!);
      expect(callback.scheme, 'poc');
      expect(callback.host, 'success');
      expect(
        callback.queryParameters['state'],
        initialRequest.queryParameters['state'],
      );

      await deliverCallback(callback);
      await tester.pump();
      await deliverCallback(callback);
      await tester.pump();
      expect(webViews.controllers.single, same(view));
      expect(view.requests, [
        initialRequest,
        Uri.parse(appHandoff.queryParameters['successURL']!),
      ]);
      expect(exchangedGrants, isEmpty);

      await redirect(tester, code: 'app-grant');
      expect(
        await login,
        isA<UaePassSuccess<String>>().having(
          (result) => result.value,
          'value',
          'app session',
        ),
      );
      final grant = exchangedGrants.single;
      expect(grant.code, 'app-grant');
      expect(grant.redirectUri, client.configuration.redirectUri);
      expect(nativeCalls.last, ('setCallbackScheme', null));
    },
  );

  testWidgets('does not launch UAE PASS after the authorization route pops', (
    tester,
  ) async {
    appInstalled = true;
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;

    Navigator.of(hostContext).pop();
    expect(
      await view.navigation.navigate(appHandoff),
      NavigationDecision.prevent,
    );
    expect(nativeCalls.any((call) => call.$1 == 'launchApp'), isFalse);
    expect(await attempt, isA<UaePassCancelled<UaePassAuthorizationGrant>>());
    expect(nativeCalls.last, ('setCallbackScheme', null));
    await tester.pumpAndSettle();
  });

  testWidgets('ignores a queued native callback when the route pops', (
    tester,
  ) async {
    appInstalled = true;
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    await view.navigation.navigate(appHandoff);
    final launchedUri = Uri.parse(nativeCalls.last.$2! as String);
    final callback = Uri.parse(launchedUri.queryParameters['successURL']!);

    final delivery = deliverCallback(callback);
    Navigator.of(hostContext).pop();
    await delivery;
    expect(await attempt, isA<UaePassCancelled<UaePassAuthorizationGrant>>());
    expect(view.requests, hasLength(1));
    expect(nativeCalls.last, ('setCallbackScheme', null));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'finishes an asynchronous startup failure without another frame',
    (tester) async {
      final initialLoad = Completer<void>();
      webViews.initialLoad = initialLoad.future;
      await openHost(tester);
      final attempt = client.authorize(hostContext);
      await tester.pumpAndSettle();
      expect(webViews.controllers.single.requests, hasLength(1));

      initialLoad.completeError(StateError('WebView load failed'));
      await tester.idle();
      expect(nativeCalls.last, ('setCallbackScheme', null));
      expect(
        await attempt,
        isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
          (failure) => failure.reason,
          'reason',
          UaePassFailureReason.authorizationFailed,
        ),
      );
      await tester.pumpAndSettle();

      webViews.initialLoad = null;
      final retry = client.authorize(hostContext);
      await tester.pumpAndSettle();
      await redirect(tester, code: 'retry-code');
      expect(await retry, isA<UaePassSuccess<UaePassAuthorizationGrant>>());
    },
  );

  testWidgets('returns a typed failure for HTTP errors on the loading page', (
    tester,
  ) async {
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    final view = webViews.controllers.single;
    final uri = view.requests.single;

    view.navigation.emitHttpError(uri.replace(path: '/missing-image.png'), 404);
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);

    view.navigation.emitHttpError(uri, 503);
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsNothing);
    expect(
      await attempt,
      isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.authorizationFailed,
      ),
    );
    expect(nativeCalls.last, ('setCallbackScheme', null));
  });

  testWidgets('ignores a native HTTP failure from a different attempt', (
    tester,
  ) async {
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    final request = webViews.controllers.single.requests.single;

    await deliverPlatformCall('onMainFrameHttpError', 'old-attempt');
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);

    await deliverPlatformCall(
      'onMainFrameHttpError',
      request.queryParameters['state']!,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsNothing);
    expect(
      await attempt,
      isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.authorizationFailed,
      ),
    );
  });

  testWidgets('holds the engine guard until login exchange completes', (
    tester,
  ) async {
    await openHost(tester);
    final exchange = Completer<UaePassResult<String>>();
    UaePassAuthorizationGrant? exchangedGrant;
    UaePassResult<String>? loginResult;
    unawaited(
      client
          .login<String>(
            hostContext,
            exchangeCode: (grant) {
              exchangedGrant = grant;
              return exchange.future;
            },
          )
          .then((result) => loginResult = result),
    );

    await tester.pumpAndSettle();
    await redirect(tester, code: 'login-code');
    expect(nativeCalls.last, ('setCallbackScheme', null));
    expect(exchangedGrant?.code, 'login-code');
    expect(loginResult, isNull);
    final competingClient = UaePassClient(client.configuration);
    UaePassResult<UaePassAuthorizationGrant>? competingResult;
    unawaited(
      competingClient
          .authorize(hostContext)
          .then((result) => competingResult = result),
    );
    await tester.pump();
    expect(
      competingResult,
      isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.alreadyInProgress,
      ),
    );

    exchange.complete(const UaePassSuccess('app session'));
    await tester.pump();
    expect(
      loginResult,
      isA<UaePassSuccess<String>>().having(
        (success) => success.value,
        'value',
        'app session',
      ),
    );

    final rejected = client.login<String>(
      hostContext,
      exchangeCode: (_) async =>
          const UaePassFailure(UaePassFailureReason.uaeNationalsOnly),
    );
    await tester.pumpAndSettle();
    await redirect(tester, code: 'new-code');
    expect(
      await rejected,
      isA<UaePassFailure<String>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.uaeNationalsOnly,
      ),
    );

    final failed = client.login<String>(
      hostContext,
      exchangeCode: (_) async => throw StateError('backend unavailable'),
    );
    await tester.pumpAndSettle();
    await redirect(tester, code: 'latest-code');
    expect(
      await failed,
      isA<UaePassFailure<String>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.exchangeFailed,
      ),
    );
  });

  testWidgets('cancels when the Navigator is disposed', (tester) async {
    await openHost(tester);
    final attempt = client.authorize(hostContext);
    await tester.pumpAndSettle();
    expect(webViews.controllers, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(await attempt, isA<UaePassCancelled<UaePassAuthorizationGrant>>());
    expect(nativeCalls.last, ('setCallbackScheme', null));
  });

  testWidgets('sign-in, login, and logo artwork return authorization results', (
    tester,
  ) async {
    final appWork = Completer<void>();
    final results = <UaePassResult<UaePassAuthorizationGrant>>[];

    Future<void> show({
      required bool enabled,
      UaePassSignInButtonContent content = UaePassSignInButtonContent.signIn,
      Locale locale = const Locale('ar'),
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UaePassSignInButton(
              client: client,
              enabled: enabled,
              content: content,
              locale: locale,
              onResult: (result) async {
                results.add(result);
                if (result is UaePassSuccess) await appWork.future;
              },
            ),
          ),
        ),
      ),
    );

    final button = find.byType(TextButton, skipOffstage: false);
    bool isEnabled() => tester.widget<TextButton>(button).onPressed != null;

    await show(enabled: false);
    expect(isEnabled(), isFalse);
    expect(webViews.controllers, isEmpty);

    await show(enabled: true);
    expect(isEnabled(), isTrue);
    expect(
      find.bySemanticsLabel('تسجيل الدخول بالهوية الرقمية'),
      findsOneWidget,
    );

    final startSignIn = tester.widget<TextButton>(button).onPressed!;
    startSignIn();
    startSignIn();
    await tester.pumpAndSettle();
    expect(isEnabled(), isFalse);
    expect(
      webViews.controllers.single.requests.first.queryParameters['ui_locales'],
      'ar',
    );
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(results.single, isA<UaePassCancelled<UaePassAuthorizationGrant>>());
    expect(isEnabled(), isTrue);

    await show(
      enabled: true,
      content: UaePassSignInButtonContent.login,
      locale: const Locale('en'),
    );
    expect(find.bySemanticsLabel('Login with UAE PASS'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await redirect(tester, error: 'server_error');
    expect(results, hasLength(2));
    expect(
      results.last,
      isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.authorizationFailed,
      ),
    );
    expect(isEnabled(), isTrue);

    await show(enabled: true, content: UaePassSignInButtonContent.logoOnly);
    expect(
      find.bySemanticsLabel('تسجيل الدخول بالهوية الرقمية'),
      findsOneWidget,
    );
    final icon = tester.widget<Image>(find.byType(Image)).image as AssetImage;
    expect(icon.assetName, endsWith('icon/rounded_white_outline_active.png'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    await redirect(tester, code: 'button-grant');
    expect(results, hasLength(3));
    expect(
      results.last,
      isA<UaePassSuccess<UaePassAuthorizationGrant>>()
          .having((success) => success.value.code, 'code', 'button-grant')
          .having(
            (success) => success.value.redirectUri,
            'redirect URI',
            client.configuration.redirectUri,
          ),
    );
    expect(appWork.isCompleted, isFalse);
    expect(isEnabled(), isTrue);
    expect(nativeCalls.last, ('setCallbackScheme', null));
    appWork.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration and authorization artwork also start UAE PASS', (
    tester,
  ) async {
    for (final (content, label, directory) in const [
      (
        UaePassSignInButtonContent.registerAccount,
        'Register Account with UAE PASS',
        'register_account',
      ),
      (UaePassSignInButtonContent.signUp, 'Sign up with UAE PASS', 'sign_up'),
      (
        UaePassSignInButtonContent.authorize,
        'Authorize Using UAE PASS',
        'authorize',
      ),
    ]) {
      final results = <UaePassResult<UaePassAuthorizationGrant>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: UaePassSignInButton(
                client: client,
                content: content,
                onResult: results.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(label), findsOneWidget);
      final artwork = tester.widget<Image>(find.byType(Image)).image;
      final assetName = switch (artwork) {
        AssetImage(:final assetName) ||
        ExactAssetImage(:final assetName) => assetName,
        _ => fail('Unexpected button artwork provider'),
      };
      expect(assetName, contains('/$directory/en/'));

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(
        webViews.controllers.last.requests.single.path,
        '/idshub/authorize',
      );
      final code = 'grant-${content.name}';
      await redirect(tester, code: code);
      expect(
        results.single,
        isA<UaePassSuccess<UaePassAuthorizationGrant>>().having(
          (result) => result.value.code,
          'code',
          code,
        ),
      );
    }
  });
}

final class _TestWebViewPlatform extends WebViewPlatform {
  final controllers = <_TestWebViewController>[];
  Future<void>? initialLoad;

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _TestWebViewCookieManager(params);

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _TestWebViewController(params, initialLoad);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _TestNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _TestWebViewWidget(params);
}

final class _TestWebViewCookieManager extends PlatformWebViewCookieManager {
  _TestWebViewCookieManager(super.params) : super.implementation();

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async => [];
}

final class _TestWebViewController extends PlatformWebViewController {
  _TestWebViewController(super.params, this.initialLoad)
    : super.implementation();

  final Future<void>? initialLoad;
  final requests = <Uri>[];
  late _TestNavigationDelegate navigation;

  @override
  Future<String?> getUserAgent() async => null;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigation = handler as _TestNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests.add(params.uri);
    if (requests.length == 1) await initialLoad;
  }
}

final class _TestNavigationDelegate extends PlatformNavigationDelegate {
  _TestNavigationDelegate(super.params) : super.implementation();

  late NavigationRequestCallback _handler;
  late HttpResponseErrorCallback _httpError;

  FutureOr<NavigationDecision> navigate(Uri uri, {bool isMainFrame = true}) =>
      _handler(
        NavigationRequest(url: uri.toString(), isMainFrame: isMainFrame),
      );

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _handler = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    _httpError = onHttpError;
  }

  void emitHttpError(Uri uri, int statusCode) => _httpError(
    HttpResponseError(
      request: WebResourceRequest(uri: uri),
      response: WebResourceResponse(uri: null, statusCode: statusCode),
    ),
  );

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

final class _TestWebViewWidget extends PlatformWebViewWidget {
  _TestWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
