import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../authorization/configuration.dart';
import '../authorization/flow.dart';
import '../platform/browser.dart';
import '../platform/webview_page.dart';

/// Why a UAE PASS approval session could not be opened or completed.
enum UaePassSigningLaunchFailure {
  invalidApprovalUri,
  invalidFinishCallbackUri,
  invalidCallbackScheme,
  launchFailed,
}

/// A failure in the browser handoff.
final class UaePassSigningLaunchException implements Exception {
  const UaePassSigningLaunchException(this.reason);

  final UaePassSigningLaunchFailure reason;

  @override
  String toString() => 'UaePassSigningLaunchException(${reason.name})';
}

/// Opens UAE PASS signing approval pages issued by the host app's backend.
final class UaePassSigningClient {
  const UaePassSigningClient({required this.environment});

  final UaePassEnvironment environment;

  static final _processId = RegExp(r'^[a-zA-Z0-9_-]+$');

  /// Opens the current tab on web or an embedded WebView on Android and iOS.
  ///
  /// [finishCallbackUri] must match the URL sent to UAE PASS when creating the
  /// signing process. On mobile pass the same registered [callbackScheme] used
  /// for UAE PASS sign-in so the browser can resume after an app handoff.
  ///
  /// On mobile this returns when the matching finish redirect is intercepted
  /// or the user dismisses the WebView. On web it returns after navigation
  /// starts. Query the authenticated backend for the signing result.
  Future<void> openApproval(
    BuildContext context,
    Uri approvalUri, {
    required Uri finishCallbackUri,
    String? callbackScheme,
  }) async {
    final processId = _approvalProcessId(approvalUri);
    if (processId == null) {
      throw const UaePassSigningLaunchException(
        UaePassSigningLaunchFailure.invalidApprovalUri,
      );
    }
    final finishQuery = readUaePassQuery(finishCallbackUri);
    if (!_isFinishCallbackUri(finishCallbackUri) ||
        finishQuery == null ||
        finishQuery.keys.any(const {'signer_process_id', 'status'}.contains)) {
      throw const UaePassSigningLaunchException(
        UaePassSigningLaunchFailure.invalidFinishCallbackUri,
      );
    }

    final browser = UaePassBrowser.instance;
    if (browser == null &&
        !kIsWeb &&
        (callbackScheme == null ||
            !isValidUaePassCallbackScheme(callbackScheme))) {
      throw const UaePassSigningLaunchException(
        UaePassSigningLaunchFailure.invalidCallbackScheme,
      );
    }
    try {
      if (browser != null) {
        browser.navigate(approvalUri);
        return;
      }
      if (!kIsWeb && callbackScheme != null) {
        final result = await openUaePassWebView<bool>(
          context,
          flow: UaePassAppFlow(
            environment: environment,
            callbackScheme: callbackScheme,
          ),
          initialUri: (_, _) => approvalUri,
          isReviewDocument: (uri) => _isReviewDocument(uri, approvalUri),
          onRedirect: (uri, _) {
            if (!matchesUaePassRedirect(uri, finishCallbackUri)) return null;
            final query = readUaePassQuery(uri);
            return !uri.authority.contains('@') &&
                !uri.hasFragment &&
                query != null &&
                listEquals(query['signer_process_id'], [processId]) &&
                finishQuery.entries.every(
                  (entry) => listEquals(query[entry.key], entry.value),
                );
          },
          failure: false,
        );
        if (result != false) return;
      }
    } catch (_) {
      // Platform errors can contain the URL and its provider process ID.
    }
    throw const UaePassSigningLaunchException(
      UaePassSigningLaunchFailure.launchFailed,
    );
  }

  String? _approvalProcessId(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != uaePassApiHost(environment) ||
        uri.port != 443 ||
        uri.authority.contains('@') ||
        uri.hasFragment ||
        uri.path != '/trustedx-resources/esignsp/v2/ui') {
      return null;
    }
    final ids = readUaePassQuery(uri)?['signerProcessId'];
    return ids != null && ids.length == 1 && _processId.hasMatch(ids.single)
        ? ids.single
        : null;
  }

  bool _isReviewDocument(Uri uri, Uri approvalUri) {
    if (!sharesUaePassOrigin(uri, approvalUri) ||
        uri.authority.contains('@') ||
        uri.hasFragment ||
        uri.path != '/trustedx-resources/esignsp/v2/ui/documents/0') {
      return false;
    }
    final query = readUaePassQuery(uri);
    final correlation = query?['x_correlation_id'];
    return query?.length == 1 &&
        correlation != null &&
        correlation.length == 1 &&
        correlation.single.isNotEmpty;
  }

  bool _isFinishCallbackUri(Uri uri) =>
      uri.host.isNotEmpty &&
      !uri.authority.contains('@') &&
      !uri.hasFragment &&
      (uri.scheme == 'https' ||
          (environment == UaePassEnvironment.staging &&
              uri.scheme == 'http' &&
              uri.host == 'localhost'));
}
