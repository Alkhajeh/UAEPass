import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../uaepass.dart';
import 'configuration.dart';
import 'model/uaepass_token.dart';
import 'model/uaepass_user.dart';

class UaePassAuthUrl {
  const UaePassAuthUrl({
    required this.appUrl,
    required this.successUrl,
    required this.failureUrl,
  });

  final Uri appUrl;
  final Uri successUrl;
  final Uri failureUrl;
}

mixin Helper {
  static const _requestTimeout = Duration(seconds: 20);

  static Future<Uri> getLoginUrl(String state) async {
    final installed = await canLaunchUrl(
      Uri(scheme: Configuration.uaePassScheme, host: 'digitalid-users-ids'),
    );
    return authorizationUrl(state: state, appInstalled: installed);
  }

  static Uri authorizationUrl({
    required String state,
    required bool appInstalled,
  }) {
    final uaepass = Uaepass.instance;
    return Uri.parse(Configuration.authorizeUrl).replace(
      queryParameters: {
        'redirect_uri': uaepass.redirectUri.toString(),
        'client_id': uaepass.clientId,
        'state': state,
        'response_type': Configuration.responseType,
        'scope': Configuration.scope,
        'acr_values': appInstalled
            ? Configuration.acrValuesMobile
            : Configuration.acrValuesWeb,
      },
    );
  }

  static bool isAuthorizationRedirect(Uri url) {
    final redirect = Uaepass.instance.redirectUri;
    return url.scheme == redirect.scheme &&
        url.host == redirect.host &&
        url.port == redirect.port &&
        (url.path.isEmpty ? '/' : url.path) ==
            (redirect.path.isEmpty ? '/' : redirect.path);
  }

  static bool isUaePassHandoff(Uri url) {
    // The staging authorization page can emit the shared UAE PASS scheme.
    return url.scheme == 'uaepass' || url.scheme == Configuration.uaePassScheme;
  }

  static UaePassAuthUrl? getUaePassOpenUrl(Uri url, String state) {
    final parameters = {
      for (final entry in url.queryParametersAll.entries)
        entry.key: entry.value,
    };
    final callbacks = <String, Uri>{};
    for (final name in parameters.keys.toList()) {
      final key = name.toLowerCase();
      if (key != 'successurl' && key != 'failureurl') continue;

      final values = parameters[name]!;
      if (values.length != 1 || callbacks.containsKey(key)) return null;
      final original = Uri.tryParse(values.single);
      if (original == null ||
          original.scheme != 'https' ||
          original.host.isEmpty) {
        return null;
      }
      callbacks[key] = original;
      parameters[name] = [
        Uri(
          scheme: Uaepass.instance.appScheme,
          host: key == 'successurl' ? 'success' : 'failure',
          queryParameters: {'state': state},
        ).toString(),
      ];
    }

    final successUrl = callbacks['successurl'];
    final failureUrl = callbacks['failureurl'];
    if (successUrl == null || failureUrl == null) return null;
    return UaePassAuthUrl(
      appUrl: url.replace(
        scheme: Configuration.uaePassScheme,
        queryParameters: parameters,
      ),
      successUrl: successUrl,
      failureUrl: failureUrl,
    );
  }

  static Future<UaepassToken?> getTokenAsync(String code) async {
    final uaepass = Uaepass.instance;
    final credentials = base64Encode(
      utf8.encode('${uaepass.clientId}:${uaepass.clientSecret}'),
    );
    final uri = Uri.parse(Configuration.tokenUrl).replace(
      queryParameters: {
        'grant_type': Configuration.grantType,
        'redirect_uri': uaepass.redirectUri.toString(),
        'code': code,
      },
    );
    final response = await http
        .post(uri, headers: {'Authorization': 'Basic $credentials'})
        .timeout(_requestTimeout);

    if (response.statusCode != 200) return null;
    return UaepassToken.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  static Future<UaepassUser?> getUser(String accessToken) async {
    final response = await http
        .get(
          Uri.parse(Configuration.profileUrl),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) return null;
    return UaepassUser.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
}
