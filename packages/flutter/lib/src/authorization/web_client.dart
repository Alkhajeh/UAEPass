import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../platform/browser.dart';
import 'configuration.dart';
import 'flow.dart';
import 'result.dart';

/// Authorizes users with UAE PASS in the current browser tab.
final class UaePassWebClient {
  UaePassWebClient(this.configuration)
    : _sessionKey =
          'uaepass.authorization.${jsonEncode([configuration.environment.name, configuration.clientId, configuration.redirectUri.toString()])}';

  final UaePassWebConfiguration configuration;
  final String _sessionKey;

  static const _attemptLifetime = Duration(minutes: 10);
  static const _failure = UaePassFailure<Never>(
    UaePassFailureReason.authorizationFailed,
  );

  /// Starts authorization by navigating the current tab to UAE PASS.
  ///
  /// Success means navigation was requested. Complete the new page's attempt
  /// with [completeAuthorization] or [completeLogin] at startup.
  UaePassResult<void> startAuthorization({Locale locale = const Locale('en')}) {
    final browser = UaePassBrowser.instance;
    final redirect = configuration.redirectUri;
    try {
      if (browser == null || !sharesUaePassOrigin(browser.location, redirect)) {
        return _failure;
      }

      final state = generateUaePassState();
      final uri = buildUaePassAuthorizationUri(
        environment: configuration.environment,
        redirectUri: redirect,
        clientId: configuration.clientId,
        state: state,
        scopes: configuration.scopes,
        language: locale.languageCode == 'ar' ? 'ar' : 'en',
      );
      browser.writeSession(
        _sessionKey,
        jsonEncode({
          'state': state,
          'startedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      try {
        browser.navigate(uri);
      } catch (_) {
        browser.removeSession(_sessionKey);
        rethrow;
      }
      return const UaePassSuccess<void>(null);
    } catch (_) {
      return _failure;
    }
  }

  /// Validates and consumes the current callback before returning a grant.
  ///
  /// Call once at startup, before routing. Returns `null` on ordinary loads.
  UaePassResult<UaePassAuthorizationGrant>? completeAuthorization() {
    final browser = UaePassBrowser.instance;
    if (browser == null) return null;

    final redirect = configuration.redirectUri;
    try {
      final current = browser.location;
      if (!matchesUaePassRedirect(current, redirect)) return null;
      final query = readUaePassQuery(current);
      if (query != null &&
          !query.keys.any(const {'code', 'state', 'error'}.contains)) {
        return null;
      }

      final String? attempt;
      try {
        attempt = browser.readSession(_sessionKey);
        browser.removeSession(_sessionKey);
      } finally {
        browser.replaceUrl(redirect);
      }
      if (attempt == null) return _failure;

      final Object? data = jsonDecode(attempt);
      if (data case {'state': final String state, 'startedAt': final int time}
          when state.isNotEmpty) {
        final age = DateTime.now().millisecondsSinceEpoch - time;
        if (age >= 0 && age < _attemptLifetime.inMilliseconds) {
          return parseUaePassAuthorizationResult(current, redirect, state);
        }
      }
      return _failure;
    } catch (_) {
      return _failure;
    }
  }

  /// Completes a callback and exchanges its grant for an app-owned session.
  ///
  /// Returns `null` when this page load is outside the authorization callback.
  Future<UaePassResult<T>?> completeLogin<T>({
    required UaePassCodeExchange<T> exchangeCode,
  }) async {
    final result = completeAuthorization();
    return result == null ? null : exchangeUaePassResult(result, exchangeCode);
  }

  /// Builds the UAE PASS logout URL for a return to the app's origin.
  ///
  /// Invalidate the app session before redirecting the user to this URL.
  Uri logoutUri({required Uri redirectUri}) {
    if (!sharesUaePassOrigin(redirectUri, configuration.redirectUri) ||
        redirectUri.userInfo.isNotEmpty ||
        redirectUri.hasFragment) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'Use a logout return URL on the configured origin.',
      );
    }
    return Uri.https(
      uaePassApiHost(configuration.environment),
      '/idshub/logout',
      {'redirect_uri': redirectUri.toString()},
    );
  }
}
