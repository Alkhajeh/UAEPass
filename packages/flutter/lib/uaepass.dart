import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'src/enums.dart';
import 'src/helper.dart';
import 'src/model/uaepass_login_result.dart';
import 'src/model/uaepass_token.dart';
import 'src/model/uaepass_user.dart';
import 'src/uaepass_login_view.dart';

export 'src/enums.dart';
export 'src/model/uaepass_login_result.dart';
export 'src/model/uaepass_token.dart';
export 'src/model/uaepass_user.dart';
export 'src/uaepass_login_button.dart';

/// The UAE PASS authentication client used by [UaepassLoginButton].
final class Uaepass {
  Uaepass._({
    required this.env,
    required this.appScheme,
    required this.clientId,
    required this.redirectUri,
    required this.fullscreen,
    required this.showMessages,
  });

  static const _callbackChannel = MethodChannel(
    'ae.uaepass/flutter_auth/callbacks',
  );
  static const _sandboxClientId = 'sandbox_stage';

  static Uaepass? _instance;
  static bool _attemptInProgress = false;

  /// Configures the client with the redirect registered for the UAE PASS app.
  static Uaepass init({
    required UaePassEnv env,
    required String appScheme,
    required String clientId,
    required String redirectUri,
    bool fullscreen = true,
    bool showMessages = true,
  }) {
    if (_attemptInProgress) {
      throw StateError('Wait for the current UAE PASS sign-in to finish.');
    }
    if (!RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(appScheme) ||
        const {'http', 'https', 'uaepass', 'uaepassstg'}.contains(appScheme)) {
      throw ArgumentError.value(
        appScheme,
        'appScheme',
        'Use a custom URI scheme.',
      );
    }
    final redirect = Uri.tryParse(redirectUri);
    if (redirect == null ||
        redirect.scheme != 'https' ||
        redirect.host.isEmpty ||
        redirect.userInfo.isNotEmpty ||
        redirect.hasFragment ||
        redirect.queryParameters.keys.any(
          const {'code', 'state', 'error'}.contains,
        )) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'Use your registered HTTPS callback URI.',
      );
    }
    if (clientId.trim().isEmpty) {
      throw ArgumentError.value(
        clientId,
        'clientId',
        'A client ID is required.',
      );
    }

    return _instance = Uaepass._(
      env: env,
      appScheme: appScheme,
      clientId: clientId,
      redirectUri: redirect,
      fullscreen: fullscreen,
      showMessages: showMessages,
    );
  }

  /// Configures sign-in with the UAE PASS public staging sandbox credentials.
  ///
  /// For your own staging or production client, use [init].
  static Uaepass initSandbox({
    required String appScheme,
    String redirectUri = 'https://localhost:8000',
    bool fullscreen = true,
    bool showMessages = true,
  }) => init(
    env: UaePassEnv.stg,
    appScheme: appScheme,
    clientId: _sandboxClientId,
    redirectUri: redirectUri,
    fullscreen: fullscreen,
    showMessages: showMessages,
  );

  /// The configured client. Call [init] or [initSandbox] first.
  static Uaepass get instance =>
      _instance ?? (throw StateError('Initialize the UAE PASS plugin first.'));

  final UaePassEnv env;
  final String appScheme;
  final String clientId;
  final Uri redirectUri;
  final bool showMessages;
  final bool fullscreen;
  String? _code;
  UaepassSession? _session;

  /// The code from the most recent successful exchange. It has been consumed.
  String? get code => _code;

  /// The optional provider token from the most recent successful exchange.
  UaepassToken? get token => _session?.token;

  /// The profile from the most recent successful exchange.
  UaepassUser? get user => _session?.user;

  /// Whether this client has completed sign-in during its lifetime.
  ///
  /// Your application owns its session lifetime and checks expiry separately.
  bool isLoggedIn() => _session != null;

  /// Opens UAE PASS and returns a grant, cancellation, or failure.
  ///
  /// Send a successful grant to your backend for exchange.
  Future<UaepassAuthorizationResult> authorize(BuildContext context) =>
      _runAttempt(context, (result, _) => result);

  /// Authorizes with UAE PASS and returns the session from [exchangeCode].
  ///
  /// Provide a callback that sends the grant to your backend. The public
  /// staging sandbox can use the SDK's built-in exchange.
  Future<UaepassLoginResult> login(
    BuildContext context, {
    UaepassCodeExchange? exchangeCode,
  }) async {
    final exchange =
        exchangeCode ??
        (env == UaePassEnv.stg && clientId == _sandboxClientId
            ? exchangeSandboxCode
            : null);
    if (exchange == null) {
      return const UaepassLoginFailure(
        UaepassLoginFailureReason.exchangeNotConfigured,
      );
    }

    return _runAttempt(context, (result, messenger) async {
      switch (result) {
        case UaepassAuthorizationSuccess(:final authorization):
          try {
            final session = await exchange(authorization);
            _code = authorization.code;
            _session = session;
            return UaepassLoginSuccess(session);
          } catch (_) {
            _showFailure(messenger);
            return const UaepassLoginFailure(
              UaepassLoginFailureReason.exchangeFailed,
            );
          }
        case UaepassAuthorizationCancelled():
          return const UaepassLoginCancelled();
        case UaepassAuthorizationFailure(:final reason):
          return UaepassLoginFailure(switch (reason) {
            UaepassAuthorizationFailureReason.alreadyInProgress =>
              UaepassLoginFailureReason.alreadyInProgress,
            UaepassAuthorizationFailureReason.authorizationFailed =>
              UaepassLoginFailureReason.authorizationFailed,
          });
      }
    });
  }

  Future<T> _runAttempt<T>(
    BuildContext context,
    FutureOr<T> Function(UaepassAuthorizationResult, ScaffoldMessengerState?)
    complete,
  ) async {
    if (_attemptInProgress) {
      return complete(
        const UaepassAuthorizationFailure(
          UaepassAuthorizationFailureReason.alreadyInProgress,
        ),
        null,
      );
    }

    final messenger = showMessages ? ScaffoldMessenger.maybeOf(context) : null;
    _attemptInProgress = true;
    try {
      final result = await _authorize(context);
      if (result is UaepassAuthorizationFailure) _showFailure(messenger);
      return await complete(result, messenger);
    } finally {
      _attemptInProgress = false;
    }
  }

  Future<UaepassAuthorizationResult> _authorize(BuildContext context) async {
    const failed = UaepassAuthorizationFailure(
      UaepassAuthorizationFailureReason.authorizationFailed,
    );
    final callbacks = StreamController<String>.broadcast();
    _callbackChannel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (call.method == 'onCallback' && arguments is String) {
        callbacks.add(arguments);
      }
    });

    try {
      await _callbackChannel.invokeMethod<void>('setCallbackScheme', appScheme);
      if (!context.mounted) return const UaepassAuthorizationCancelled();

      final result = await Navigator.of(context).push<UaepassWebViewResult>(
        MaterialPageRoute<UaepassWebViewResult>(
          builder: (_) => UaepassLoginView(
            flow: UaepassAuthFlow(
              env: env,
              redirectUri: redirectUri,
              clientId: clientId,
              appScheme: appScheme,
            ),
            callbacks: callbacks.stream,
          ),
          fullscreenDialog: fullscreen,
        ),
      );

      if (result == null || result.status == UaepassWebViewStatus.cancelled) {
        return const UaepassAuthorizationCancelled();
      }
      final code = result.code;
      if (result.status != UaepassWebViewStatus.authorized || code == null) {
        return failed;
      }
      return UaepassAuthorizationSuccess(
        UaepassAuthorization(code: code, redirectUri: redirectUri),
      );
    } on Exception {
      return failed;
    } finally {
      _callbackChannel.setMethodCallHandler(null);
      unawaited(callbacks.close());
      try {
        await _callbackChannel.invokeMethod<void>('setCallbackScheme');
      } on Exception {
        // The engine may have detached while the sign-in route was open.
      }
    }
  }

  void _showFailure(ScaffoldMessengerState? messenger) {
    if (messenger != null && messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not complete UAE PASS sign-in.')),
      );
    }
  }
}
