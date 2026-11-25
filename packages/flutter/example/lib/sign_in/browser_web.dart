import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _localeKey = 'uaepass-example-locale';

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

void navigate(Uri uri) => web.window.location.assign(uri.toString());

Future<void> exchangeWithLocalBackend(String code) async {
  final controller = web.AbortController();
  final headers = web.Headers()..set('Content-Type', 'application/json');

  Future<void> exchange() async {
    final response = await web.window
        .fetch(
          '/auth/uaepass'.toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers,
            body: jsonEncode({'code': code}).toJS,
            mode: 'same-origin',
            redirect: 'error',
            signal: controller.signal,
          ),
        )
        .toDart;
    if (response.status != 200) {
      throw StateError('The local backend rejected the exchange.');
    }
    final result = jsonDecode((await response.text().toDart).toDart);
    if (result is! Map<String, Object?> || result['ok'] != true) {
      throw const FormatException('Unexpected local backend response.');
    }
  }

  try {
    await exchange().timeout(const Duration(seconds: 12));
  } finally {
    controller.abort();
  }
}
