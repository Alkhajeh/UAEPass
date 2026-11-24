import 'uaepass_token.dart';
import 'uaepass_user.dart';

/// A UAE PASS authorization grant ready for the application's backend.
final class UaepassAuthorization {
  const UaepassAuthorization({required this.code, required this.redirectUri});

  /// The short-lived, single-use authorization code.
  final String code;

  /// The same URI used in the authorization request.
  final Uri redirectUri;
}

/// The outcome of requesting an authorization grant from UAE PASS.
sealed class UaepassAuthorizationResult {
  const UaepassAuthorizationResult();
}

/// UAE PASS returned a grant that the app can exchange on its backend.
final class UaepassAuthorizationSuccess extends UaepassAuthorizationResult {
  const UaepassAuthorizationSuccess(this.authorization);

  final UaepassAuthorization authorization;
}

/// The user closed or cancelled the authorization flow.
final class UaepassAuthorizationCancelled extends UaepassAuthorizationResult {
  const UaepassAuthorizationCancelled();
}

/// The attempt ended before UAE PASS returned an authorization grant.
final class UaepassAuthorizationFailure extends UaepassAuthorizationResult {
  const UaepassAuthorizationFailure(this.reason);

  final UaepassAuthorizationFailureReason reason;
}

/// Why the authorization attempt could not complete.
enum UaepassAuthorizationFailureReason {
  alreadyInProgress,
  authorizationFailed,
}

/// Exchanges a grant on the application's backend and returns its sign-in result.
typedef UaepassCodeExchange = Future<UaepassSession> Function(
  UaepassAuthorization authorization,
);

/// The verified UAE PASS profile and any token the integrator chooses to expose.
final class UaepassSession {
  const UaepassSession({required this.user, this.token});

  final UaepassUser user;
  final UaepassToken? token;
}

/// The outcome of a single sign-in attempt.
sealed class UaepassLoginResult {
  const UaepassLoginResult();
}

/// The application completed the authorization and code exchange.
final class UaepassLoginSuccess extends UaepassLoginResult {
  const UaepassLoginSuccess(this.session);

  final UaepassSession session;
}

/// The user closed or cancelled the sign-in flow.
final class UaepassLoginCancelled extends UaepassLoginResult {
  const UaepassLoginCancelled();
}

/// The attempt failed before an authenticated session could be established.
final class UaepassLoginFailure extends UaepassLoginResult {
  const UaepassLoginFailure(this.reason);

  final UaepassLoginFailureReason reason;
}

/// The stage at which a sign-in attempt failed.
enum UaepassLoginFailureReason {
  alreadyInProgress,
  authorizationFailed,
  exchangeNotConfigured,
  exchangeFailed,
}
