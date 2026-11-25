/// A short-lived, single-use grant for exchange on the app's backend.
final class UaePassAuthorizationGrant {
  const UaePassAuthorizationGrant({
    required this.code,
    required this.redirectUri,
  });

  final String code;
  final Uri redirectUri;
}

/// An authorization, sign-in, or code exchange outcome.
sealed class UaePassResult<T> {
  const UaePassResult();
}

final class UaePassSuccess<T> extends UaePassResult<T> {
  const UaePassSuccess(this.value);

  final T value;
}

final class UaePassCancelled<T> extends UaePassResult<T> {
  const UaePassCancelled();
}

final class UaePassFailure<T> extends UaePassResult<T> {
  const UaePassFailure(this.reason);

  final UaePassFailureReason reason;
}

enum UaePassFailureReason {
  alreadyInProgress,
  authorizationFailed,
  exchangeFailed,
  ineligibleAccount,
  registeredUsersOnly,
  uaeNationalsOnly,
}

/// Exchanges the grant on the app's backend for an app-owned session.
///
/// Return a typed [UaePassFailure] to report a service eligibility restriction.
typedef UaePassCodeExchange<T> = Future<UaePassResult<T>> Function(
  UaePassAuthorizationGrant grant,
);
