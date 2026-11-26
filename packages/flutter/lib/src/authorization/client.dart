import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../localization/locale.dart';
import '../platform/webview_page.dart';
import 'configuration.dart';
import 'flow.dart';
import 'result.dart';

/// Authorizes users with UAE PASS on Android and iOS.
final class UaePassClient {
  UaePassClient(this.configuration);

  final UaePassConfiguration configuration;

  // All clients on the engine's UI isolate share the native callback channel.
  static bool _attemptInProgress = false;
  static const _busy = UaePassFailure<Never>(
    UaePassFailureReason.alreadyInProgress,
  );

  /// Requests an authorization grant suitable for a backend exchange.
  Future<UaePassResult<UaePassAuthorizationGrant>> authorize(
    BuildContext context, {
    Locale? locale,
  }) => _runAttempt(() => _authorize(context, locale), _busy);

  /// Authorizes and calls [exchangeCode] to establish an app-owned session.
  Future<UaePassResult<T>> login<T>(
    BuildContext context, {
    required UaePassCodeExchange<T> exchangeCode,
    Locale? locale,
  }) => _runAttempt(
    () async =>
        exchangeUaePassResult(await _authorize(context, locale), exchangeCode),
    _busy,
  );

  /// Ends the UAE PASS session in the embedded browser on Android and iOS.
  ///
  /// Invalidate your app's own session first. Returns true when UAE PASS
  /// returns to the configured redirect URI. Returns false if logout is
  /// dismissed, fails, or another UAE PASS operation is in progress.
  Future<bool> logout(BuildContext context) => _runAttempt(() async {
    final redirectUri = configuration.redirectUri;
    final result = await openUaePassWebView<bool>(
      context,
      flow: UaePassAppFlow(
        environment: configuration.environment,
        callbackScheme: configuration.callbackScheme,
      ),
      initialUri: (_, _) =>
          buildUaePassLogoutUri(configuration.environment, redirectUri),
      onRedirect: (uri, _) {
        if (!matchesUaePassRedirect(uri, redirectUri)) return null;
        final query = readUaePassQuery(uri);
        return uri.userInfo.isEmpty &&
            !uri.hasFragment &&
            query != null &&
            !query.keys.any(const {'code', 'error'}.contains) &&
            redirectUri.queryParametersAll.entries.every(
              (entry) => listEquals(query[entry.key], entry.value),
            );
      },
      failure: false,
    );
    return result == true;
  }, false);

  Future<T> _runAttempt<T>(Future<T> Function() run, T busyResult) async {
    if (_attemptInProgress) return busyResult;
    _attemptInProgress = true;
    try {
      return await run();
    } finally {
      _attemptInProgress = false;
    }
  }

  Future<UaePassResult<UaePassAuthorizationGrant>> _authorize(
    BuildContext context,
    Locale? locale,
  ) async {
    if (!context.mounted) return const UaePassCancelled();
    final flow = UaePassAuthorizationFlow(
      configuration: configuration,
      language: resolveUaePassLocale(context, locale).languageCode,
    );
    final result =
        await openUaePassWebView<UaePassResult<UaePassAuthorizationGrant>>(
          context,
          flow: flow.appFlow,
          initialUri: (state, platform) async => flow.authorizationUri(
            state: state,
            appInstalled: await platform.isAppInstalled(
              configuration.environment,
            ),
          ),
          onRedirect: flow.authorizationResult,
          failure: const UaePassFailure(
            UaePassFailureReason.authorizationFailed,
          ),
          locale: locale,
        );
    return result ?? const UaePassCancelled();
  }
}
