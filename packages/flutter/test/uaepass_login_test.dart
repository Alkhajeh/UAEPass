import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/src/helper.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  testWidgets('returns a grant directly or completes the backend exchange', (
    tester,
  ) async {
    const callbackChannel = MethodChannel('ae.uaepass/flutter_auth/callbacks');
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pendingAppCheck = Completer<bool>();
    final callbackCalls = <(String, Object?)>[];
    final launcherCalls = <String>[];
    messenger.setMockMethodCallHandler(callbackChannel, (call) async {
      callbackCalls.add((call.method, call.arguments));
      return null;
    });
    messenger.setMockMethodCallHandler(launcherChannel, (call) {
      launcherCalls.add(call.method);
      return pendingAppCheck.future;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(callbackChannel, null);
      messenger.setMockMethodCallHandler(launcherChannel, null);
    });

    const redirect = 'https://login.example/callback';
    const user = UaepassUser(uuid: 'test-user');
    final client = Uaepass.init(
      env: UaePassEnv.prod,
      appScheme: 'com.example.app',
      clientId: 'client',
      redirectUri: redirect,
    );

    final navigator = GlobalKey<NavigatorState>();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );

    expect(
      await client.login(context),
      isA<UaepassLoginFailure>().having(
        (failure) => failure.reason,
        'reason',
        UaepassLoginFailureReason.exchangeNotConfigured,
      ),
    );
    expect(callbackCalls, isEmpty);

    Future<void> returnFromAuthorization([String? code]) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      navigator.currentState!.pop<UaepassWebViewResult>(
        code == null
            ? null
            : (status: UaepassWebViewStatus.authorized, code: code),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    final authorizationAttempt = client.authorize(context);
    await returnFromAuthorization('authorization-code');
    expect(
      await authorizationAttempt,
      isA<UaepassAuthorizationSuccess>()
          .having(
            (result) => result.authorization.code,
            'code',
            'authorization-code',
          )
          .having(
            (result) => result.authorization.redirectUri,
            'redirectUri',
            Uri.parse(redirect),
          ),
    );
    expect(client.isLoggedIn(), isFalse);
    expect(client.code, isNull);
    expect(client.user, isNull);

    final cancelledAttempt = client.authorize(context);
    await returnFromAuthorization();
    expect(await cancelledAttempt, isA<UaepassAuthorizationCancelled>());

    final grants = <UaepassAuthorization>[];
    final session = Completer<UaepassSession>();
    final loginAttempt = client.login(
      context,
      exchangeCode: (grant) {
        grants.add(grant);
        return session.future;
      },
    );
    await returnFromAuthorization('login-code');
    expect(grants.single.code, 'login-code');
    expect(grants.single.redirectUri, Uri.parse(redirect));
    expect(client.isLoggedIn(), isFalse);
    expect(
      await client.authorize(context),
      isA<UaepassAuthorizationFailure>().having(
        (failure) => failure.reason,
        'reason',
        UaepassAuthorizationFailureReason.alreadyInProgress,
      ),
    );

    session.complete(const UaepassSession(user: user));
    pendingAppCheck.complete(false);
    await tester.pump();

    expect(
      await loginAttempt,
      isA<UaepassLoginSuccess>().having(
        (result) => result.session.user,
        'user',
        user,
      ),
    );
    expect(client.isLoggedIn(), isTrue);
    expect(client.code, 'login-code');
    expect(client.token, isNull);
    expect(callbackCalls, [
      for (var attempt = 0; attempt < 3; attempt++) ...[
        ('setCallbackScheme', 'com.example.app'),
        ('setCallbackScheme', null),
      ],
    ]);
    expect(launcherCalls, ['canLaunch', 'canLaunch', 'canLaunch']);
  });
}
