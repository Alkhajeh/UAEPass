/// The UAE PASS service environment.
enum UaePassEnvironment { staging, production }

/// The registered client and redirect settings for UAE PASS authentication.
final class UaePassConfiguration {
  UaePassConfiguration({
    required this.environment,
    required this.clientId,
    required this.callbackScheme,
    required this.redirectUri,
    Iterable<String> scopes = const [profileScope],
  }) : scopes = List.unmodifiable(scopes) {
    if (!RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(callbackScheme) ||
        const {
          'http',
          'https',
          'uaepass',
          'uaepassstg',
        }.contains(callbackScheme)) {
      throw ArgumentError.value(
        callbackScheme,
        'callbackScheme',
        'Use a custom URI scheme.',
      );
    }
    if (redirectUri.scheme != 'https' ||
        redirectUri.host.isEmpty ||
        redirectUri.userInfo.isNotEmpty ||
        redirectUri.hasFragment ||
        redirectUri.queryParameters.keys.any(
          const {'code', 'state', 'error'}.contains,
        )) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'Use your registered HTTPS redirect URI.',
      );
    }
    if (clientId.trim().isEmpty) {
      throw ArgumentError.value(
        clientId,
        'clientId',
        'A client ID is required.',
      );
    }
    if (this.scopes.isEmpty ||
        this.scopes.any(
          (scope) => scope.isEmpty || RegExp(r'\s').hasMatch(scope),
        )) {
      throw ArgumentError.value(
        this.scopes,
        'scopes',
        'Provide individual UAE PASS scopes.',
      );
    }
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
