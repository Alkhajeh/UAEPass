import 'package:flutter/foundation.dart';

import 'configuration.dart';
import 'result.dart';

typedef UaePassAppHandoff = ({Uri appUri, Uri successUri, Uri failureUri});

final class UaePassAuthorizationFlow {
  const UaePassAuthorizationFlow({
    required this.configuration,
    required this.language,
  });

  final UaePassConfiguration configuration;
  final String language;

  static const _mobileAcr = 'urn:digitalid:authentication:flow:mobileondevice';
  static const _webAcr = 'urn:safelayer:tws:policies:authentication:level:low';
  static const _cancellationErrors = {
    'invalid_request',
    'login_required',
    'access_denied',
    'cancelledOnApp',
  };

  bool get _isStaging =>
      configuration.environment == UaePassEnvironment.staging;
  String get _apiHost => _isStaging ? 'stg-id.uaepass.ae' : 'id.uaepass.ae';
  String get _appScheme => _isStaging ? 'uaepassstg' : 'uaepass';

  Uri authorizationUri({required String state, required bool appInstalled}) =>
      Uri.https(_apiHost, '/idshub/authorize', {
        'redirect_uri': configuration.redirectUri.toString(),
        'client_id': configuration.clientId,
        'state': state,
        'response_type': 'code',
        'scope': configuration.scopes.join(' '),
        'acr_values': appInstalled ? _mobileAcr : _webAcr,
        'ui_locales': language,
      });

  UaePassResult<UaePassAuthorizationGrant>? authorizationResult(
    Uri uri,
    String state,
  ) {
    final redirect = configuration.redirectUri;
    if (uri.scheme != redirect.scheme ||
        uri.host != redirect.host ||
        uri.port != redirect.port ||
        (uri.path.isEmpty ? '/' : uri.path) !=
            (redirect.path.isEmpty ? '/' : redirect.path)) {
      return null;
    }

    final query = readUaePassQuery(uri);
    if (query == null ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !listEquals(query['state'], [state]) ||
        !redirect.queryParametersAll.entries.every(
          (entry) => listEquals(query[entry.key], entry.value),
        )) {
      return const UaePassFailure(UaePassFailureReason.authorizationFailed);
    }

    final code = query['code'];
    final error = query['error'];
    if (code case [final value] when value.trim().isNotEmpty && error == null) {
      return UaePassSuccess(
        UaePassAuthorizationGrant(code: value, redirectUri: redirect),
      );
    }
    if (code == null &&
        error != null &&
        error.length == 1 &&
        _cancellationErrors.contains(error.single)) {
      return const UaePassCancelled();
    }
    return const UaePassFailure(UaePassFailureReason.authorizationFailed);
  }

  bool isAppHandoff(Uri uri) =>
      uri.scheme == 'uaepass' || uri.scheme == _appScheme;

  bool isProviderPage(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      (uri.host == 'uaepass.ae' || uri.host.endsWith('.uaepass.ae'));

  bool _isResumeUri(Uri uri) =>
      isProviderPage(uri) &&
      !uri.hasFragment &&
      (uri.host == _apiHost ||
          uri.host == (_isStaging ? 'stg-ids.uaepass.ae' : 'ids.uaepass.ae'));

  UaePassAppHandoff? appHandoff(Uri uri, String state) {
    if (!isAppHandoff(uri) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return null;
    }
    final query = readUaePassQuery(uri);
    if (query == null) return null;
    final parameters = Map.of(query);
    final destinations = <String, Uri>{};

    for (final entry in query.entries) {
      final host = switch (entry.key.toLowerCase()) {
        'successurl' => 'success',
        'failureurl' => 'failure',
        _ => null,
      };
      if (host == null) continue;
      if (entry.value.length != 1 || destinations.containsKey(host)) {
        return null;
      }

      final destination = Uri.tryParse(entry.value.single);
      if (destination == null || !_isResumeUri(destination)) return null;
      destinations[host] = destination;

      parameters[entry.key] = [
        Uri(
          scheme: configuration.callbackScheme,
          host: host,
          queryParameters: {'state': state},
        ).toString(),
      ];
    }

    final success = destinations['success'];
    final failure = destinations['failure'];
    if (success == null || failure == null) return null;
    return (
      appUri: uri.replace(scheme: _appScheme, queryParameters: parameters),
      successUri: success,
      failureUri: failure,
    );
  }
}

Map<String, List<String>>? readUaePassQuery(Uri uri) {
  try {
    return uri.queryParametersAll;
  } on FormatException {
    return null;
  }
}
