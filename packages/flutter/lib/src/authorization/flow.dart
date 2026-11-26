import 'dart:convert';
import 'dart:math';

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

  UaePassAppFlow get appFlow => UaePassAppFlow(
    environment: configuration.environment,
    callbackScheme: configuration.callbackScheme,
  );

  Uri authorizationUri({required String state, required bool appInstalled}) =>
      buildUaePassAuthorizationUri(
        environment: configuration.environment,
        redirectUri: configuration.redirectUri,
        clientId: configuration.clientId,
        state: state,
        scopes: configuration.scopes,
        language: language,
        appHandoff: appInstalled,
      );

  UaePassResult<UaePassAuthorizationGrant>? authorizationResult(
    Uri uri,
    String state,
  ) => matchesUaePassRedirect(uri, configuration.redirectUri)
      ? parseUaePassAuthorizationResult(uri, configuration.redirectUri, state)
      : null;
}

/// Validates and resumes UAE PASS app handoffs from an embedded browser.
final class UaePassAppFlow {
  const UaePassAppFlow({
    required this.environment,
    required this.callbackScheme,
  });

  final UaePassEnvironment environment;
  final String callbackScheme;

  bool get _isStaging => environment == UaePassEnvironment.staging;
  String get _appScheme => _isStaging ? 'uaepassstg' : 'uaepass';

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
      (uri.host == uaePassApiHost(environment) ||
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
          scheme: callbackScheme,
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

String uaePassApiHost(UaePassEnvironment environment) => switch (environment) {
  UaePassEnvironment.staging => 'stg-id.uaepass.ae',
  UaePassEnvironment.production => 'id.uaepass.ae',
};

String generateUaePassState() {
  final random = Random.secure();
  return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
}

Uri buildUaePassAuthorizationUri({
  required UaePassEnvironment environment,
  required Uri redirectUri,
  required String clientId,
  required String state,
  required List<String> scopes,
  required String language,
  bool appHandoff = false,
}) => Uri.https(uaePassApiHost(environment), '/idshub/authorize', {
  'redirect_uri': redirectUri.toString(),
  'client_id': clientId,
  'state': state,
  'response_type': 'code',
  'scope': scopes.join(' '),
  'acr_values': appHandoff
      ? 'urn:digitalid:authentication:flow:mobileondevice'
      : 'urn:safelayer:tws:policies:authentication:level:low',
  'ui_locales': language,
});

Uri buildUaePassLogoutUri(UaePassEnvironment environment, Uri redirectUri) =>
    Uri.https(uaePassApiHost(environment), '/idshub/logout', {
      'redirect_uri': redirectUri.toString(),
    });

bool sharesUaePassOrigin(Uri uri, Uri reference) =>
    uri.scheme == reference.scheme &&
    uri.host == reference.host &&
    uri.port == reference.port;

bool matchesUaePassRedirect(Uri uri, Uri redirect) =>
    sharesUaePassOrigin(uri, redirect) &&
    (uri.path.isEmpty ? '/' : uri.path) ==
        (redirect.path.isEmpty ? '/' : redirect.path);

const _cancellationErrors = {
  'invalid_request',
  'login_required',
  'access_denied',
  'cancelledOnApp',
};

UaePassResult<UaePassAuthorizationGrant> parseUaePassAuthorizationResult(
  Uri uri,
  Uri redirect,
  String state,
) {
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

Future<UaePassResult<T>> exchangeUaePassResult<T>(
  UaePassResult<UaePassAuthorizationGrant> result,
  UaePassCodeExchange<T> exchangeCode,
) async {
  switch (result) {
    case UaePassSuccess(:final value):
      try {
        return await exchangeCode(value);
      } catch (_) {
        return const UaePassFailure(UaePassFailureReason.exchangeFailed);
      }
    case UaePassCancelled():
      return const UaePassCancelled();
    case UaePassFailure(:final reason):
      return UaePassFailure(reason);
  }
}

Map<String, List<String>>? readUaePassQuery(Uri uri) {
  try {
    return uri.queryParametersAll;
  } on FormatException {
    return null;
  }
}
