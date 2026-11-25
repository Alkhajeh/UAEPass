import 'package:flutter_test/flutter_test.dart';
import 'package:uaepass/src/authorization/flow.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  final redirectUri = Uri.parse('https://app.example/callback?channel=mobile');
  final staging = UaePassAuthorizationFlow(
    configuration: UaePassConfiguration(
      environment: UaePassEnvironment.staging,
      redirectUri: redirectUri,
      clientId: 'app-client',
      callbackScheme: 'poc',
      scopes: [UaePassConfiguration.profileScope, 'openid'],
    ),
    language: 'ar',
  );
  final production = UaePassAuthorizationFlow(
    configuration: UaePassConfiguration(
      environment: UaePassEnvironment.production,
      redirectUri: redirectUri,
      clientId: 'app-client',
      callbackScheme: 'poc',
    ),
    language: 'en',
  );

  test('configures both environments and forwards locale and scopes', () {
    final web = staging.authorizationUri(state: 'state', appInstalled: false);
    final mobile = production.authorizationUri(
      state: 'state',
      appInstalled: true,
    );
    expect(web.host, 'stg-id.uaepass.ae');
    expect(mobile.host, 'id.uaepass.ae');
    expect(
      web.queryParameters['acr_values'],
      'urn:safelayer:tws:policies:authentication:level:low',
    );
    expect(
      mobile.queryParameters['acr_values'],
      'urn:digitalid:authentication:flow:mobileondevice',
    );
    expect(web.queryParameters['redirect_uri'], redirectUri.toString());
    expect(web.queryParameters['state'], 'state');
    expect(web.queryParameters['ui_locales'], 'ar');
    expect(mobile.queryParameters['ui_locales'], 'en');
    expect(
      web.queryParameters['scope'],
      '${UaePassConfiguration.profileScope} openid',
    );
    expect(mobile.queryParameters['scope'], UaePassConfiguration.profileScope);
  });

  test(
    'requires a valid custom scheme, a client ID, and an HTTPS redirect',
    () {
      UaePassConfiguration create({
        String scheme = 'poc',
        String clientId = 'app-client',
        Uri? redirect,
        List<String> scopes = const [UaePassConfiguration.profileScope],
      }) => UaePassConfiguration(
        environment: UaePassEnvironment.staging,
        clientId: clientId,
        callbackScheme: scheme,
        redirectUri: redirect ?? redirectUri,
        scopes: scopes,
      );

      expect(() => create(scheme: 'https'), throwsArgumentError);
      expect(() => create(scheme: 'uaepassstg'), throwsArgumentError);
      expect(() => create(clientId: ' '), throwsArgumentError);
      expect(
        () => create(redirect: Uri.parse('http://app.example')),
        throwsArgumentError,
      );
      expect(
        () => create(redirect: Uri.parse('https://app.example?state=value')),
        throwsArgumentError,
      );
      expect(() => create(scopes: []), throwsArgumentError);
      expect(() => create(scopes: ['two scopes']), throwsArgumentError);
    },
  );

  test('accepts a single code at the configured redirect and state', () {
    final response = redirectUri.replace(
      query: 'channel=mobile&code=code&state=state',
    );
    final result = staging.authorizationResult(response, 'state');
    expect(result, isA<UaePassSuccess<UaePassAuthorizationGrant>>());
    final grant = (result as UaePassSuccess<UaePassAuthorizationGrant>).value;
    expect(grant.code, 'code');
    expect(grant.redirectUri, redirectUri);
    for (final wrongRedirect in [
      response.replace(host: 'other.example'),
      response.replace(port: 8443),
      response.replace(path: '/unexpected'),
    ]) {
      expect(staging.authorizationResult(wrongRedirect, 'state'), isNull);
    }
    expect(
      staging.authorizationResult(
        response.replace(userInfo: 'someone'),
        'state',
      ),
      isA<UaePassFailure<UaePassAuthorizationGrant>>(),
    );
    expect(
      staging.authorizationResult(
        response.replace(fragment: 'unexpected'),
        'state',
      ),
      isA<UaePassFailure<UaePassAuthorizationGrant>>(),
    );
  });

  test('classifies each documented cancellation only after correlation', () {
    for (final error in [
      'invalid_request',
      'login_required',
      'access_denied',
      'cancelledOnApp',
    ]) {
      Uri response(String state) => redirectUri.replace(
        query: 'channel=mobile&error=$error&state=$state',
      );
      expect(
        staging.authorizationResult(response('state'), 'state'),
        isA<UaePassCancelled<UaePassAuthorizationGrant>>(),
      );
      expect(
        staging.authorizationResult(response('different'), 'state'),
        isA<UaePassFailure<UaePassAuthorizationGrant>>(),
      );
    }
  });

  test('rejects conflicting, incomplete, and repeated redirect parameters', () {
    for (final query in [
      'code=code&state=state',
      'channel=mobile&code=code&state=wrong',
      'channel=mobile&code=code&state=state&state=state',
      'channel=mobile&code=code&code=other&state=state',
      'channel=mobile&code=code&error=access_denied&state=state',
      'channel=mobile&code=%20&state=state',
      'channel=mobile&code=%FF&state=state',
      'channel=mobile&error=access_denied&error=access_denied&state=state',
      'channel=mobile&error=server_error&state=state',
    ]) {
      expect(
        staging.authorizationResult(redirectUri.replace(query: query), 'state'),
        isA<UaePassFailure<UaePassAuthorizationGrant>>().having(
          (failure) => failure.reason,
          'reason',
          UaePassFailureReason.authorizationFailed,
        ),
        reason: query,
      );
    }
  });

  test('rewrites and validates the provider app handoff', () {
    final nativeUrl = Uri.parse(
      'uaepass://digitalid-users-ids/signatures/test',
    );
    final handoffUrl = nativeUrl.replace(
      queryParameters: {
        'successURL': 'https://stg-ids.uaepass.ae/resume?status=success',
        'failureURL': 'https://stg-id.uaepass.ae/resume?status=failure',
        'session': ['one', 'two'],
      },
    );
    final handoff = staging.appHandoff(handoffUrl, 'state')!;
    expect(handoff.appUri.scheme, 'uaepassstg');
    expect(handoff.appUri.path, nativeUrl.path);
    expect(handoff.successUri.queryParameters['status'], 'success');
    expect(handoff.failureUri.queryParameters['status'], 'failure');
    expect(handoff.appUri.queryParametersAll['session'], ['one', 'two']);
    expect(
      handoff.appUri.queryParameters['successURL'],
      'poc://success?state=state',
    );
    expect(
      handoff.appUri.queryParameters['failureURL'],
      'poc://failure?state=state',
    );
    expect(production.appHandoff(handoffUrl, 'state'), isNull);

    for (final invalidDestination in [
      'http://stg-id.uaepass.ae/resume',
      'https://id.uaepass.ae/resume',
      'https://stg-id.uaepass.ae.other.example/resume',
      'https://stg-id.uaepass.ae:8443/resume',
      'https://someone@stg-id.uaepass.ae/resume',
      'https://stg-id.uaepass.ae/resume#fragment',
    ]) {
      final invalid = handoffUrl.replace(
        queryParameters: {
          ...handoffUrl.queryParameters,
          'successURL': invalidDestination,
        },
      );
      expect(staging.appHandoff(invalid, 'state'), isNull);
    }
  });
}
