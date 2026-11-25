import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uaepass/src/platform/browser.dart';
import 'package:uaepass/uaepass.dart';

class _Browser implements UaePassBrowser {
  _Browser(this.location);

  @override
  Uri location;
  Uri? destination;
  bool allowNavigation = true;
  final session = <String, String>{};

  @override
  void navigate(Uri uri) {
    if (!allowNavigation) throw StateError('Navigation refused');
    destination = uri;
  }

  @override
  String? readSession(String key) => session[key];

  @override
  void removeSession(String key) => session.remove(key);

  @override
  void replaceUrl(Uri uri) => location = uri;

  @override
  void writeSession(String key, String value) => session[key] = value;
}

void main() {
  final redirect = Uri.parse('https://service.example/callback?channel=web');
  final config = UaePassWebConfiguration(
    environment: UaePassEnvironment.staging,
    clientId: 'fixture-web-client',
    redirectUri: redirect,
  );
  late UaePassWebClient client;
  late _Browser browser;

  setUp(() {
    client = UaePassWebClient(config);
    browser = _Browser(redirect.resolve('/sign-in'));
    UaePassBrowser.instance = browser;
  });
  tearDown(() => UaePassBrowser.instance = null);

  String start() {
    expect(client.startAuthorization(), isA<UaePassSuccess<void>>());
    return browser.destination!.queryParameters['state']!;
  }

  Uri callback(String query) => redirect.replace(query: 'channel=web&$query');

  test('resumes web staging from an HTTP localhost callback', () async {
    final loopback = Uri.parse('http://localhost:8000');
    client = UaePassWebClient(
      UaePassWebConfiguration(
        environment: UaePassEnvironment.staging,
        clientId: config.clientId,
        redirectUri: loopback,
      ),
    );
    browser.location = loopback.resolve('/sign-in');
    final state = start();
    expect(browser.destination!.origin, 'https://stg-id.uaepass.ae');
    expect(browser.destination!.queryParameters['redirect_uri'], '$loopback');
    browser.location = loopback.replace(
      path: '/',
      queryParameters: {'code': 'fixture-code', 'state': state},
    );

    final result = await client.completeLogin<Uri>(
      exchangeCode: (grant) async => UaePassSuccess(grant.redirectUri),
    );
    expect(
      result,
      isA<UaePassSuccess<Uri>>().having(
        (value) => value.value,
        'redirect',
        loopback,
      ),
    );
    expect(browser.location, loopback);
  });

  test('rejects HTTP callbacks outside localhost web staging', () {
    for (final (environment, url) in const [
      (UaePassEnvironment.production, 'http://localhost:8000'),
      (UaePassEnvironment.staging, 'http://service.example/callback'),
      (UaePassEnvironment.staging, 'http://localhost.example/callback'),
      (UaePassEnvironment.staging, 'http://127.0.0.1:8000'),
    ]) {
      expect(
        () => UaePassWebConfiguration(
          environment: environment,
          clientId: config.clientId,
          redirectUri: Uri.parse(url),
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => UaePassConfiguration(
        environment: UaePassEnvironment.staging,
        clientId: config.clientId,
        callbackScheme: 'com.example.fixture',
        redirectUri: Uri.parse('http://localhost:8000'),
      ),
      throwsArgumentError,
    );
  });

  test('starts same-tab browser authorization in the selected locale', () {
    expect(
      client.startAuthorization(locale: const Locale('ar')),
      isA<UaePassSuccess<void>>(),
    );
    final destination = browser.destination!;
    expect(destination.origin, 'https://stg-id.uaepass.ae');
    expect(destination.path, '/idshub/authorize');
    final params = destination.queryParameters;
    expect(params['client_id'], config.clientId);
    expect(params['redirect_uri'], redirect.toString());
    expect(params['response_type'], 'code');
    expect(params['scope'], UaePassConfiguration.profileScope);
    expect(params['ui_locales'], 'ar');
    expect(
      params['acr_values'],
      'urn:safelayer:tws:policies:authentication:level:low',
    );
    expect(base64Url.decode(params['state']!), hasLength(32));
    expect(browser.session, hasLength(1));
  });

  test('resumes after a reload and exchanges the grant exactly once', () async {
    final state = Uri.encodeQueryComponent(start());
    final response = callback('code=fixture-code&state=$state');
    browser.location = response;
    final resumedClient = UaePassWebClient(config);
    var exchanges = 0;

    Future<UaePassResult<int>> exchange(UaePassAuthorizationGrant grant) async {
      exchanges++;
      expect(browser.session, isEmpty);
      expect(browser.location, redirect);
      expect(grant.code, 'fixture-code');
      expect(grant.redirectUri, redirect);
      return const UaePassSuccess(42);
    }

    expect(
      await resumedClient.completeLogin(exchangeCode: exchange),
      isA<UaePassSuccess<int>>().having((result) => result.value, 'value', 42),
    );
    expect(await resumedClient.completeLogin(exchangeCode: exchange), isNull);
    browser.location = response;
    expect(
      await resumedClient.completeLogin(exchangeCode: exchange),
      const TypeMatcher<UaePassFailure<int>>(),
    );
    expect(exchanges, 1);
    expect(browser.location, redirect);
  });

  test('starting again after Back replaces the pending state', () {
    final first = start();
    expect(client.completeAuthorization(), isNull);
    final second = start();
    expect(first, isNot(second));
    expect(browser.session, hasLength(1));
    browser.location = callback(
      'code=fixture-code&state=${Uri.encodeQueryComponent(second)}',
    );
    expect(
      client.completeAuthorization(),
      isA<UaePassSuccess<UaePassAuthorizationGrant>>(),
    );
  });

  test('cancellation requires valid state and cleans the URL', () {
    final state = Uri.encodeQueryComponent(start());
    browser.location = callback(
      'error=access_denied&state=$state&error_description=fixture-description',
    );
    expect(
      client.completeAuthorization(),
      isA<UaePassCancelled<UaePassAuthorizationGrant>>(),
    );
    expect(browser.location, redirect);
    expect(browser.session, isEmpty);
  });

  test('rejects missing, mismatched, duplicated, and malformed data', () async {
    for (final makeQuery in <String Function(String)>[
      (_) => 'code=fixture-code',
      (_) => 'code=fixture-code&state=unrelated',
      (state) => 'code=fixture-code&state=$state&state=$state',
      (state) => 'code=fixture-code&code=other&state=$state',
      (state) => 'code=fixture-code&error=access_denied&state=$state',
      (state) => 'code=%FF&state=$state',
    ]) {
      final state = Uri.encodeQueryComponent(start());
      browser.location = callback(makeQuery(state));
      var exchanged = false;
      final result = await client.completeLogin<void>(
        exchangeCode: (_) async {
          exchanged = true;
          return const UaePassSuccess(null);
        },
      );
      expect(result, isA<UaePassFailure<void>>());
      expect(exchanged, isFalse);
      expect(browser.location, redirect);
      expect(browser.session, isEmpty);
    }
  });

  test('only the configured origin and callback can complete an attempt', () {
    final state = Uri.encodeQueryComponent(start());
    final response = callback('code=fixture-code&state=$state');
    for (final location in [
      response.replace(host: 'other.example'),
      response.replace(port: 8443),
      response.replace(path: '/another-page'),
    ]) {
      browser.location = location;
      expect(client.completeAuthorization(), isNull);
      expect(browser.session, hasLength(1));
    }
    browser.location = response.replace(
      query: 'code=fixture-code&state=$state',
    );
    expect(
      client.completeAuthorization(),
      isA<UaePassFailure<UaePassAuthorizationGrant>>(),
    );
    browser.location = Uri.parse('https://other.example/');
    expect(client.startAuthorization(), isA<UaePassFailure<void>>());
    expect(browser.session, isEmpty);
  });

  test('rejects missing or expired pending attempts', () {
    final state = start();
    final response = callback(
      'code=fixture-code&state=${Uri.encodeQueryComponent(state)}',
    );
    UaePassBrowser.instance = _Browser(response);
    expect(
      client.completeAuthorization(),
      isA<UaePassFailure<UaePassAuthorizationGrant>>(),
    );
    UaePassBrowser.instance = browser;
    browser.session[browser.session.keys.single] = jsonEncode({
      'state': state,
      'startedAt': DateTime.now()
          .subtract(const Duration(minutes: 11))
          .millisecondsSinceEpoch,
    });
    browser.location = response;
    expect(
      client.completeAuthorization(),
      isA<UaePassFailure<UaePassAuthorizationGrant>>(),
    );
    expect(browser.session, isEmpty);
  });

  test('reports and cleans up a failed navigation request', () {
    browser.allowNavigation = false;
    expect(client.startAuthorization(), isA<UaePassFailure<void>>());
    expect(browser.session, isEmpty);
  });

  test('sanitizes exchange errors and consumes the grant', () async {
    final state = Uri.encodeQueryComponent(start());
    browser.location = callback('code=fixture-code&state=$state');
    expect(
      await client.completeLogin<void>(
        exchangeCode: (_) async => throw StateError('fixture'),
      ),
      isA<UaePassFailure<void>>().having(
        (failure) => failure.reason,
        'reason',
        UaePassFailureReason.exchangeFailed,
      ),
    );
    expect(browser.session, isEmpty);
  });

  test('builds a provider logout URI for a same-origin HTTPS return', () {
    final returnUri = redirect.resolve('/signed-out?language=ar');
    expect(
      client.logoutUri(redirectUri: returnUri),
      Uri.https('stg-id.uaepass.ae', '/idshub/logout', {
        'redirect_uri': returnUri.toString(),
      }),
    );
    expect(
      () => client.logoutUri(redirectUri: Uri.parse('https://other.example/')),
      throwsArgumentError,
    );
  });
}
