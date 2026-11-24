import Flutter
import UIKit

public final class UaepassPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel
  private var callbackScheme: String?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ae.uaepass/flutter_auth/callbacks", binaryMessenger: registrar.messenger())
    let plugin = UaepassPlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addApplicationDelegate(plugin)
    registrar.addSceneDelegate(plugin)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setCallbackScheme" else {
      result(FlutterMethodNotImplemented)
      return
    }

    if call.arguments == nil || call.arguments is NSNull {
      callbackScheme = nil
    } else if let scheme = call.arguments as? String, !scheme.isEmpty {
      callbackScheme = scheme
    } else {
      result(FlutterError(
        code: "invalid_scheme", message: "Expected a nonempty callback scheme or null.", details: nil))
      return
    }
    result(nil)
  }

  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    handleCallback(url)
  }

  public func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) -> Bool {
    for context in contexts {
      if handleCallback(context.url) {
        return true
      }
    }
    return false
  }

  private func handleCallback(_ url: URL) -> Bool {
    guard let callbackScheme, url.scheme == callbackScheme,
      url.host == "success" || url.host == "failure"
    else {
      return false
    }
    channel.invokeMethod("onCallback", arguments: url.absoluteString)
    return true
  }
}
