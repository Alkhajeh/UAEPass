import 'package:flutter/services.dart';

import '../authorization/configuration.dart';

final class UaePassPlatform {
  static const channel = MethodChannel('ae.uaepass/flutter_auth/callbacks');

  Future<bool> isAppInstalled(UaePassEnvironment environment) async =>
      await channel.invokeMethod<bool>('isAppInstalled', environment.name) ??
      false;

  Future<bool> launchApp(Uri uri) async =>
      await channel.invokeMethod<bool>('launchApp', uri.toString()) ?? false;

  Future<void> setCallbackScheme(String? scheme) =>
      channel.invokeMethod<void>('setCallbackScheme', scheme);

  void setCallbackHandler(void Function(String)? handler) {
    channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              final uri = call.arguments;
              if (call.method == 'onCallback' && uri is String) handler(uri);
            },
    );
  }
}
