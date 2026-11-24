import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uaepass/src/configuration.dart';
import 'package:uaepass/src/helper.dart';
import 'package:uaepass/uaepass.dart';

void init(UaePassEnv environment) {
  Uaepass.init(
    env: environment,
    appScheme: 'poc',
    clientId: 'test-client',
    clientSecret: 'test-secret',
    redirectUri: 'https://localhost:8000/callback',
  );
}

void main() {
  test('selects the staging web flow when UAE PASS is unavailable', () {
    init(UaePassEnv.stg);
    final url = Helper.authorizationUrl(
      state: 'test state',
      appInstalled: false,
    );

    expect(url.host, 'stg-id.uaepass.ae');
    expect(url.queryParameters['acr_values'], Configuration.acrValuesWeb);
    expect(
      url.queryParameters['redirect_uri'],
      'https://localhost:8000/callback',
    );
    expect(url.queryParameters['state'], 'test state');
    expect(
      Helper.isAuthorizationRedirect(
        Uri.parse('https://localhost:8000/callback?code=code'),
      ),
      isTrue,
    );
    expect(
      Helper.isAuthorizationRedirect(
        Uri.parse('https://localhost:8001/callback?code=code'),
      ),
      isFalse,
    );

    final mobileUrl = Helper.authorizationUrl(
      state: 'test state',
      appInstalled: true,
    );
    expect(
      mobileUrl.queryParameters['acr_values'],
      Configuration.acrValuesMobile,
    );
  });

  test('preserves the UAE PASS handoff parameters and both return URLs', () {
    init(UaePassEnv.stg);
    final source = Uri.parse('uaepass://digitalid-users-ids/signatures/test')
        .replace(
          queryParameters: {
            'successURL':
                'https://stg-ids.uaepass.ae/resume?status=success&id=123',
            'failureURL':
                'https://stg-ids.uaepass.ae/resume?status=failure&id=123',
            'closeondone': 'true',
            'session': ['one', 'two'],
          },
        );

    expect(Helper.isUaePassHandoff(source), isTrue);
    expect(
      Helper.isUaePassHandoff(source.replace(scheme: 'uaepassstg')),
      isTrue,
    );
    final handoff = Helper.getUaePassOpenUrl(source, 'test-state')!;
    expect(handoff.appUrl.scheme, 'uaepassstg');
    expect(handoff.appUrl.path, '/signatures/test');
    expect(handoff.successUrl.queryParameters['status'], 'success');
    expect(handoff.failureUrl.queryParameters['status'], 'failure');
    expect(handoff.appUrl.queryParametersAll['session'], ['one', 'two']);
    expect(handoff.appUrl.queryParameters['closeondone'], 'true');
    expect(
      handoff.appUrl.queryParameters['successURL'],
      'poc://success?state=test-state',
    );
    expect(
      handoff.appUrl.queryParameters['failureURL'],
      'poc://failure?state=test-state',
    );

    init(UaePassEnv.prod);
    expect(
      Helper.isUaePassHandoff(source.replace(scheme: 'uaepassstg')),
      isFalse,
    );
    expect(
      Helper.getUaePassOpenUrl(source, 'test-state')!.appUrl.scheme,
      'uaepass',
    );
  });

  test('uses the documented token headers and selected API host', () async {
    init(UaePassEnv.stg);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return request.url.path.endsWith('/token')
          ? http.Response('{"access_token":"test-token"}', 200)
          : http.Response('{"sub":"test-subject"}', 200);
    });

    await http.runWithClient(() async {
      final token = await Helper.getTokenAsync('test-code');
      await Helper.getUser(token!.accessToken!);
      init(UaePassEnv.prod);
      await Helper.getUser('production-token');
    }, () => client);

    expect(requests[0].method, 'POST');
    expect(requests[0].url.queryParameters, {
      'grant_type': 'authorization_code',
      'redirect_uri': 'https://localhost:8000/callback',
      'code': 'test-code',
    });
    expect(
      requests[0].headers['authorization'],
      'Basic ${base64Encode(utf8.encode('test-client:test-secret'))}',
    );
    expect(requests[1].url.host, 'stg-id.uaepass.ae');
    expect(requests[1].headers['authorization'], 'Bearer test-token');
    expect(requests[2].url.host, 'id.uaepass.ae');
    expect(requests[2].headers['authorization'], 'Bearer production-token');
  });
}
