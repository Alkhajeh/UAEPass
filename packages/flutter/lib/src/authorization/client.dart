import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../localization/locale.dart';
import '../platform/native_bridge.dart';
import 'configuration.dart';
import 'flow.dart';
import 'result.dart';
import 'webview_page.dart';

/// Authorizes users with UAE PASS on Android and iOS.
final class UaePassClient {
  UaePassClient(this.configuration);

  final UaePassConfiguration configuration;
  final _platform = UaePassPlatform();

  // All clients on the engine's UI isolate share the native callback channel.
  static bool _attemptInProgress = false;

  /// Requests an authorization grant suitable for a backend exchange.
  Future<UaePassResult<UaePassAuthorizationGrant>> authorize(
    BuildContext context, {
    Locale? locale,
  }) => _runAttempt(() => _authorize(context, locale));

  /// Authorizes and calls [exchangeCode] to establish an app-owned session.
  Future<UaePassResult<T>> login<T>(
    BuildContext context, {
    required UaePassCodeExchange<T> exchangeCode,
    Locale? locale,
  }) => _runAttempt(() async {
    final result = await _authorize(context, locale);
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
  });

  Future<UaePassResult<T>> _runAttempt<T>(
    Future<UaePassResult<T>> Function() run,
  ) async {
    if (_attemptInProgress) {
      return const UaePassFailure(UaePassFailureReason.alreadyInProgress);
    }
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
    final callbacks = StreamController<String>();
    final language = resolveUaePassLocale(context, locale).languageCode;

    try {
      final random = Random.secure();
      final state = base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      );
      final flow = UaePassAuthorizationFlow(
        configuration: configuration,
        language: language,
      );

      _platform.setCallbackHandler(callbacks.add);
      await _platform.setCallbackScheme(configuration.callbackScheme);
      final installed = await _platform.isAppInstalled(
        configuration.environment,
      );
      if (!context.mounted) return const UaePassCancelled();

      final route = MaterialPageRoute<UaePassResult<UaePassAuthorizationGrant>>(
        fullscreenDialog: true,
        builder: (_) => UaePassAuthorizationPage(
          flow: flow,
          state: state,
          initialUri: flow.authorizationUri(
            state: state,
            appInstalled: installed,
          ),
          callbacks: callbacks.stream,
          platform: _platform,
        ),
      );
      final result = await Future.any([
        Navigator.of(context).push(route),
        route.completed,
      ]);
      return result ?? const UaePassCancelled();
    } on Exception {
      return const UaePassFailure(UaePassFailureReason.authorizationFailed);
    } finally {
      _platform.setCallbackHandler(null);
      unawaited(callbacks.close());
      try {
        await _platform.setCallbackScheme(null);
      } on PlatformException {
        // The platform may have detached before the route closed.
      } on MissingPluginException {
        // The platform may not support UAE PASS.
      }
    }
  }
}
