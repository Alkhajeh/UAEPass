import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var methodChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    methodChannel = FlutterMethodChannel(
      name: "poc.uaepass/channel",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }

  fileprivate func handleUaePassCallback(_ url: URL) {
    methodChannel?.invokeMethod("didRecieveTranscript", arguments: url.absoluteString)
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let appDelegate = UIApplication.shared.delegate as? AppDelegate
    var otherContexts = URLContexts
    for context in URLContexts where context.url.scheme == "poc" {
      appDelegate?.handleUaePassCallback(context.url)
      otherContexts.remove(context)
    }
    if !otherContexts.isEmpty {
      super.scene(scene, openURLContexts: otherContexts)
    }
  }
}
