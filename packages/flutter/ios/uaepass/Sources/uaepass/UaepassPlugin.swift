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
    switch call.method {
    case "setCallbackScheme":
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
    case "isAppInstalled":
      let url: URL?
      switch call.arguments as? String {
      case "staging": url = URL(string: "uaepassstg://")
      case "production": url = URL(string: "uaepass://")
      default: url = nil
      }
      result(url.map { UIApplication.shared.canOpenURL($0) } ?? false)
    case "launchApp":
      guard let rawURI = call.arguments as? String, let uri = URL(string: rawURI),
        uri.scheme == "uaepass" || uri.scheme == "uaepassstg"
      else {
        result(false)
        return
      }
      UIApplication.shared.open(uri, options: [:]) { opened in
        result(opened)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
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
