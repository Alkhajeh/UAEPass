/// The UAE PASS service environment.
enum UaePassEnvironment { staging, production }

bool isValidUaePassCallbackScheme(String value) =>
    RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(value) &&
    !const {'http', 'https', 'uaepass', 'uaepassstg'}.contains(value);

/// The registered client and redirect settings for UAE PASS authentication.
final class UaePassConfiguration {
  UaePassConfiguration({
    required this.environment,
    required this.clientId,
    required this.callbackScheme,
    required this.redirectUri,
    Iterable<String> scopes = const [profileScope],
  }) : scopes = List.unmodifiable(scopes) {
    if (!isValidUaePassCallbackScheme(callbackScheme)) {
      throw ArgumentError.value(
        callbackScheme,
        'callbackScheme',
        'Use a custom URI scheme.',
      );
    }
    _validateOAuthSettings(clientId, redirectUri, this.scopes);
  }

  static const profileScope = 'urn:uae:digitalid:profile:general';

  final UaePassEnvironment environment;
  final String clientId;

  /// The custom URI scheme registered with the app and UAE PASS.
  final String callbackScheme;

  /// The HTTPS OAuth redirect registered with UAE PASS.
  final Uri redirectUri;
  final List<String> scopes;
}

/// The registered client and callback for browser-based authorization.
final class UaePassWebConfiguration {
  UaePassWebConfiguration({
    required this.environment,
    required this.clientId,
    required this.redirectUri,
    Iterable<String> scopes = const [UaePassConfiguration.profileScope],
  }) : scopes = List.unmodifiable(scopes) {
    _validateOAuthSettings(
      clientId,
      redirectUri,
      this.scopes,
      allowHttpLocalhost: environment == UaePassEnvironment.staging,
    );
  }

  final UaePassEnvironment environment;
  final String clientId;

  /// The registered callback served by the Flutter app's origin.
  ///
  /// HTTPS is required except for HTTP on `localhost` in staging.
  final Uri redirectUri;
  final List<String> scopes;
}

void _validateOAuthSettings(
  String clientId,
  Uri redirectUri,
  List<String> scopes, {
  bool allowHttpLocalhost = false,
}) {
  final validScheme =
      redirectUri.scheme == 'https' ||
      (allowHttpLocalhost &&
          redirectUri.scheme == 'http' &&
          redirectUri.host == 'localhost');
  if (!validScheme ||
      redirectUri.host.isEmpty ||
      redirectUri.userInfo.isNotEmpty ||
      redirectUri.hasFragment ||
      redirectUri.queryParameters.keys.any(
        const {'code', 'state', 'error'}.contains,
      )) {
    throw ArgumentError.value(
      redirectUri,
      'redirectUri',
      allowHttpLocalhost
          ? 'Use your registered HTTPS redirect URI or a staging HTTP localhost URI.'
          : 'Use your registered HTTPS redirect URI.',
    );
  }
  if (clientId.trim().isEmpty) {
    throw ArgumentError.value(clientId, 'clientId', 'A client ID is required.');
  }
  if (scopes.isEmpty ||
      scopes.any((scope) => scope.isEmpty || RegExp(r'\s').hasMatch(scope))) {
    throw ArgumentError.value(
      scopes,
      'scopes',
      'Provide individual UAE PASS scopes.',
    );
  }
}
