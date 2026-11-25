import 'package:flutter/services.dart';

import '../authorization/configuration.dart';

sealed class UaePassPlatformEvent {
  const UaePassPlatformEvent();
}

final class UaePassAppCallback extends UaePassPlatformEvent {
  const UaePassAppCallback(this.uri);

  final String uri;
}

final class UaePassMainFrameHttpError extends UaePassPlatformEvent {
  const UaePassMainFrameHttpError(this.state);

  final String state;
}

final class UaePassPlatform {
  static const channel = MethodChannel('ae.uaepass/flutter_auth/callbacks');

  Future<bool> isAppInstalled(UaePassEnvironment environment) async =>
      await channel.invokeMethod<bool>('isAppInstalled', environment.name) ??
      false;

  Future<bool> launchApp(Uri uri) async =>
      await channel.invokeMethod<bool>('launchApp', uri.toString()) ?? false;

  Future<void> setCallbackScheme(String? scheme) =>
      channel.invokeMethod<void>('setCallbackScheme', scheme);

  Future<void> observeMainFrameHttpErrors(int identifier, String state) =>
      channel.invokeMethod<void>('observeMainFrameHttpErrors', {
        'identifier': identifier,
        'state': state,
      });

  void setEventHandler(void Function(UaePassPlatformEvent)? handler) {
    channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              switch ((call.method, call.arguments)) {
                case ('onCallback', final String uri):
                  handler(UaePassAppCallback(uri));
                case ('onMainFrameHttpError', final String state):
                  handler(UaePassMainFrameHttpError(state));
              }
            },
    );
  }
}
