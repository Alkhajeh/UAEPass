import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../signing/signing_transaction.dart';
import 'backend_response.dart';

const _localeKey = 'uaepass-example-locale';
const _backendKey = 'uaepass-example-local-backend';
const _transactionKey = 'uaepass-example-signing-transaction';
const _signingIntentKey = 'uaepass-example-sign-after-auth';

String? readLocale() {
  try {
    return web.window.sessionStorage.getItem(_localeKey);
  } catch (_) {
    return null;
  }
}

void saveLocale(String languageCode) {
  try {
    web.window.sessionStorage.setItem(_localeKey, languageCode);
  } catch (_) {
    // The in-app language still works if browser storage is unavailable.
  }
}

bool readBackendEnabled() {
  try {
    return web.window.sessionStorage.getItem(_backendKey) == 'true';
  } catch (_) {
    return false;
  }
}

void saveBackendEnabled(bool enabled) {
  try {
    if (enabled) {
      web.window.sessionStorage.setItem(_backendKey, 'true');
    } else {
      web.window.sessionStorage.removeItem(_backendKey);
    }
  } catch (_) {
    // The current screen can still use the setting if storage is unavailable.
  }
}

void navigate(Uri uri) => web.window.location.assign(uri.toString());

String? takeSigningIntent() {
  try {
    final pending = web.window.sessionStorage.getItem(_signingIntentKey);
    web.window.sessionStorage.removeItem(_signingIntentKey);
    return pending;
  } catch (_) {
    return null;
  }
}

void saveSigningIntent(String transaction) =>
    web.window.sessionStorage.setItem(_signingIntentKey, transaction);

SigningTransaction? takeApprovalTransaction(String id) {
  try {
    final transaction = SigningTransaction.decode(
      web.window.sessionStorage.getItem(_transactionKey),
    );
    if (transaction?.id != id) return null;
    web.window.sessionStorage.removeItem(_transactionKey);
    return transaction;
  } catch (_) {
    return null;
  }
}

void rememberApprovalTransaction(String id) =>
    web.window.sessionStorage.setItem(_transactionKey, id);

void clearSigningReturn() {
  takeSigningIntent();
  try {
    web.window.sessionStorage.removeItem(_transactionKey);
  } catch (_) {
    // Storage can be unavailable when the browser blocks it.
  }
}

Future<void> exchangeWithLocalBackend(String code) async {
  final result = await requestBackend(
    '/auth/uaepass',
    method: 'POST',
    body: {'code': code},
  );
  result.requireExchangeSuccess();
}

Future<BackendResponse> requestBackend(
  String path, {
  String method = 'GET',
  Map<String, String>? body,
  String? transactionToken,
}) async {
  final controller = web.AbortController();
  final headers = web.Headers();
  if (body != null) headers.set('Content-Type', 'application/json');
  if (transactionToken != null) {
    headers.set('Authorization', 'Bearer $transactionToken');
  }

  Future<BackendResponse> send() async {
    final response = await web.window
        .fetch(
          path.toJS,
          web.RequestInit(
            method: method,
            headers: headers,
            body: body == null ? null : jsonEncode(body).toJS,
            mode: 'same-origin',
            credentials: 'omit',
            redirect: 'error',
            signal: controller.signal,
          ),
        )
        .toDart;
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final contentType = response.headers.get('content-type');
    // A missing upstream can fall through to Flutter's page or 404 handler.
    if ((response.status == 200 &&
            contentType?.startsWith('text/html') == true) ||
        ({404, 500, 502, 503, 504}.contains(response.status) &&
            contentType?.startsWith('application/json') != true)) {
      throw const BackendConnectionException();
    }
    return BackendResponse(response.status, bytes);
  }

  try {
    return await send().timeout(const Duration(seconds: 30));
  } catch (_) {
    throw const BackendConnectionException();
  } finally {
    controller.abort();
  }
}
