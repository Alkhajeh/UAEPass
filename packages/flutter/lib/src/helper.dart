import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'enums.dart';
import 'model/uaepass_login_result.dart';
import 'model/uaepass_token.dart';
import 'model/uaepass_user.dart';

typedef UaepassAppHandoff = ({Uri appUrl, Uri successUrl, Uri failureUrl});

enum UaepassWebViewStatus { authorized, cancelled, failed }

typedef UaepassWebViewResult = ({UaepassWebViewStatus status, String? code});

final class UaepassAuthFlow {
  const UaepassAuthFlow({
    required this.env,
    required this.redirectUri,
    required this.clientId,
    required this.appScheme,
  });

  final UaePassEnv env;
  final Uri redirectUri;
  final String clientId;
  final String appScheme;

  static const _scope = 'urn:uae:digitalid:profile:general';
  static const _mobileAcr = 'urn:digitalid:authentication:flow:mobileondevice';
  static const _webAcr = 'urn:safelayer:tws:policies:authentication:level:low';

  String get _apiHost =>
      env == UaePassEnv.stg ? 'stg-id.uaepass.ae' : 'id.uaepass.ae';

  String get _appScheme => env == UaePassEnv.stg ? 'uaepassstg' : 'uaepass';

  Future<Uri> getLoginUrl(String state) async => authorizationUrl(
    state: state,
    appInstalled: await canLaunchUrl(
      Uri(scheme: _appScheme, host: 'digitalid-users-ids'),
    ),
  );

  Uri authorizationUrl({required String state, required bool appInstalled}) =>
      Uri.https(_apiHost, '/idshub/authorize', {
        'redirect_uri': redirectUri.toString(),
        'client_id': clientId,
        'state': state,
        'response_type': 'code',
        'scope': _scope,
        'acr_values': appInstalled ? _mobileAcr : _webAcr,
      });

  UaepassWebViewResult? authorizationResult(Uri url, String state) {
    if (url.scheme != redirectUri.scheme ||
        url.host != redirectUri.host ||
        url.port != redirectUri.port ||
        url.userInfo.isNotEmpty ||
        (url.path.isEmpty ? '/' : url.path) !=
            (redirectUri.path.isEmpty ? '/' : redirectUri.path)) {
      return null;
    }

    final query = url.queryParametersAll;
    final expectedQuery = redirectUri.queryParametersAll;
    if (url.hasFragment ||
        !listEquals(query['state'], [state]) ||
        !expectedQuery.entries.every(
          (entry) => listEquals(query[entry.key], entry.value),
        )) {
      return (status: UaepassWebViewStatus.failed, code: null);
    }

    final code = query['code'];
    if (code case [final value]
        when value.isNotEmpty && query['error'] == null) {
      return (status: UaepassWebViewStatus.authorized, code: value);
    }
    if (code == null && listEquals(query['error'], ['access_denied'])) {
      return (status: UaepassWebViewStatus.cancelled, code: null);
    }
    return (status: UaepassWebViewStatus.failed, code: null);
  }

  bool isUaePassHandoff(Uri url) =>
      // The staging page can emit the shared UAE PASS scheme.
      url.scheme == 'uaepass' || url.scheme == _appScheme;

  bool _isResumeUrl(Uri url) =>
      url.scheme == 'https' &&
      url.port == 443 &&
      url.userInfo.isEmpty &&
      !url.hasFragment &&
      (url.host == _apiHost ||
          url.host ==
              (env == UaePassEnv.stg
                  ? 'stg-ids.uaepass.ae'
                  : 'ids.uaepass.ae'));

  UaepassAppHandoff? appHandoff(Uri url, String state) {
    if (!isUaePassHandoff(url) || url.userInfo.isNotEmpty) return null;
    final parameters = Map.of(url.queryParametersAll);
    final callbacks = <String, Uri>{};

    for (final entry in url.queryParametersAll.entries) {
      final name = entry.key.toLowerCase();
      if (name != 'successurl' && name != 'failureurl') continue;
      if (entry.value.length != 1 || callbacks.containsKey(name)) return null;

      final original = Uri.tryParse(entry.value.single);
      if (original == null || !_isResumeUrl(original)) return null;
      callbacks[name] = original;
      parameters[entry.key] = [
        Uri(
          scheme: appScheme,
          host: name == 'successurl' ? 'success' : 'failure',
          queryParameters: {'state': state},
        ).toString(),
      ];
    }

    final successUrl = callbacks['successurl'];
    final failureUrl = callbacks['failureurl'];
    if (successUrl == null || failureUrl == null) return null;
    return (
      appUrl: url.replace(scheme: _appScheme, queryParameters: parameters),
      successUrl: successUrl,
      failureUrl: failureUrl,
    );
  }
}

Future<UaepassSession> exchangeSandboxCode(
  UaepassAuthorization authorization,
) async {
  const requestTimeout = Duration(seconds: 20);
  const host = 'stg-id.uaepass.ae';
  // UAE PASS publishes this fixed credential for the staging sandbox.
  final credentials = base64Encode(utf8.encode('sandbox_stage:sandbox_stage'));
  final tokenResponse = await http
      .post(
        Uri.https(host, '/idshub/token', {
          'grant_type': 'authorization_code',
          'redirect_uri': authorization.redirectUri.toString(),
          'code': authorization.code,
        }),
        headers: {'Authorization': 'Basic $credentials'},
      )
      .timeout(requestTimeout);
  final token = UaepassToken.fromJson(_responseJson(tokenResponse));
  final accessToken = token.accessToken;
  if (accessToken == null || accessToken.isEmpty) {
    throw const FormatException('Missing UAE PASS sandbox access token.');
  }

  final userResponse = await http
      .get(
        Uri.https(host, '/idshub/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      )
      .timeout(requestTimeout);
  final user = UaepassUser.fromJson(_responseJson(userResponse));
  if ((user.sub?.isEmpty ?? true) && (user.uuid?.isEmpty ?? true)) {
    throw const FormatException('Missing UAE PASS sandbox user identifier.');
  }
  return UaepassSession(user: user, token: token);
}

Map<String, Object?> _responseJson(http.Response response) {
  if (response.statusCode != 200) {
    throw const FormatException('The UAE PASS sandbox request failed.');
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes));
  if (json is! Map<String, Object?>) {
    throw const FormatException('Invalid UAE PASS sandbox response.');
  }
  return json;
}
