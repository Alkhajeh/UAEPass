import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'browser.dart';

/// Registers the browser implementation with Flutter Web.
class UaePassWebPlugin implements UaePassBrowser {
  static void registerWith(Registrar registrar) {
    UaePassBrowser.instance = UaePassWebPlugin();
  }

  @override
  Uri get location => Uri.parse(web.window.location.href);

  @override
  String? readSession(String key) => web.window.sessionStorage.getItem(key);

  @override
  void writeSession(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);

  @override
  void removeSession(String key) => web.window.sessionStorage.removeItem(key);

  @override
  void navigate(Uri uri) => web.window.location.assign(uri.toString());

  @override
  void replaceUrl(Uri uri) => web.window.history.replaceState(
    web.window.history.state,
    '',
    uri.toString(),
  );
}
