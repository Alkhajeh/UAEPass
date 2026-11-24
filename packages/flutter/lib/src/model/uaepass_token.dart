/// An OAuth access token returned by UAE PASS.
///
/// Keep provider tokens on your backend whenever the app can use its own session.
final class UaepassToken {
  const UaepassToken({
    this.accessToken,
    this.scope,
    this.tokenType,
    this.expiresIn,
  });

  /// Parses the UAE PASS token response.
  UaepassToken.fromJson(Map<String, Object?> json)
    : accessToken = json['access_token'] as String?,
      scope = json['scope'] as String?,
      tokenType = json['token_type'] as String?,
      expiresIn = json['expires_in'] as int?;

  final String? accessToken;
  final String? scope;
  final String? tokenType;

  /// The token's reported lifetime in seconds.
  final int? expiresIn;
}
