import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uaepass/src/helper.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  final redirectUri = Uri.parse('https://app.example/callback?channel=mobile');
  final staging = UaepassAuthFlow(
    env: UaePassEnv.stg,
    redirectUri: redirectUri,
    clientId: 'app-client',
    appScheme: 'poc',
  );
  final production = UaepassAuthFlow(
    env: UaePassEnv.prod,
    redirectUri: redirectUri,
    clientId: 'app-client',
    appScheme: 'poc',
  );

  test('uses the selected environment and installed-app flow', () {
    final web = staging.authorizationUrl(state: 'state', appInstalled: false);
    final mobile = production.authorizationUrl(
      state: 'state',
      appInstalled: true,
    );
    expect(web.host, 'stg-id.uaepass.ae');
    expect(mobile.host, 'id.uaepass.ae');
    expect(
      web.queryParameters,
      containsPair(
        'acr_values',
        'urn:safelayer:tws:policies:authentication:level:low',
      ),
    );
    expect(
      mobile.queryParameters,
      containsPair(
        'acr_values',
        'urn:digitalid:authentication:flow:mobileondevice',
      ),
    );
    expect(web.queryParameters['redirect_uri'], redirectUri.toString());
    expect(web.queryParameters['state'], 'state');
  });

  test('accepts a single code bound to the configured redirect and state', () {
    final response = Uri.parse(
      'https://app.example/callback?channel=mobile&code=code&state=state',
    );
    expect(staging.authorizationResult(response, 'state'), (
      status: UaepassWebViewStatus.authorized,
      code: 'code',
    ));
    expect(
      staging.authorizationResult(
        response.replace(host: 'other.example'),
        'state',
      ),
      isNull,
    );

    for (final invalidQuery in [
      'code=code&state=state',
      'channel=mobile&code=code&state=wrong',
      'channel=mobile&code=code&state=state&state=state',
      'channel=mobile&code=code&code=other&state=state',
      'channel=mobile&code=code&error=access_denied&state=state',
    ]) {
      expect(
        staging
            .authorizationResult(response.replace(query: invalidQuery), 'state')
            ?.status,
        UaepassWebViewStatus.failed,
      );
    }

    final cancelled = response.replace(
      query: 'channel=mobile&error=access_denied&state=state',
    );
    expect(
      staging.authorizationResult(cancelled, 'state')?.status,
      UaepassWebViewStatus.cancelled,
    );
  });

  test('preserves the handoff and restricts return hosts by environment', () {
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
    expect(handoff.appUrl.scheme, 'uaepassstg');
    expect(handoff.appUrl.path, nativeUrl.path);
    expect(handoff.successUrl.queryParameters['status'], 'success');
    expect(handoff.failureUrl.queryParameters['status'], 'failure');
    expect(handoff.appUrl.queryParametersAll['session'], ['one', 'two']);
    expect(
      handoff.appUrl.queryParameters['successURL'],
      'poc://success?state=state',
    );
    expect(
      handoff.appUrl.queryParameters['failureURL'],
      'poc://failure?state=state',
    );
    expect(production.appHandoff(handoffUrl, 'state'), isNull);

    for (final invalidHost in [
      'https://id.uaepass.ae/resume',
      'https://stg-id.uaepass.ae.other.example/resume',
      'https://stg-id.uaepass.ae:8443/resume',
    ]) {
      final invalid = handoffUrl.replace(
        queryParameters: {
          ...handoffUrl.queryParameters,
          'successURL': invalidHost,
        },
      );
      expect(staging.appHandoff(invalid, 'state'), isNull);
    }
  });

  test(
    'the built-in exchange sends only the fixed public sandbox credentials',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return request.url.path.endsWith('/token')
            ? http.Response('{"access_token":"test-token"}', 200)
            : http.Response('{"sub":"test-subject"}', 200);
      });

      final session = await http.runWithClient(
        () => exchangeSandboxCode(
          UaepassAuthorization(code: 'test-code', redirectUri: redirectUri),
        ),
        () => client,
      );

      expect(session.user.sub, 'test-subject');
      expect(session.token?.accessToken, 'test-token');
      expect(requests[0].method, 'POST');
      expect(requests[0].url.host, 'stg-id.uaepass.ae');
      expect(requests[0].url.queryParameters, {
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
        'code': 'test-code',
      });
      expect(
        requests[0].headers['authorization'],
        'Basic ${base64Encode(utf8.encode('sandbox_stage:sandbox_stage'))}',
      );
      expect(requests[1].url.host, 'stg-id.uaepass.ae');
      expect(requests[1].headers['authorization'], 'Bearer test-token');
    },
  );
}
