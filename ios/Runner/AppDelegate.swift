import Flutter
import AVFoundation
import ObjectiveC.runtime
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var didInstallTouchRateCorrectionWorkaround = false
  private var platformChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    installFlutterTouchRateCorrectionWorkaroundIfNeeded()
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    installPlatformChannelIfNeeded()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func installFlutterTouchRateCorrectionWorkaroundIfNeeded() {
    guard #available(iOS 18.4, *),
      !Self.didInstallTouchRateCorrectionWorkaround
    else {
      return
    }

    let selector = NSSelectorFromString("createTouchRateCorrectionVSyncClientIfNeeded")
    guard let method = class_getInstanceMethod(FlutterViewController.self, selector) else {
      return
    }

    // Work around a Flutter iOS engine crash in VSyncClient on high-refresh devices.
    let noOpBlock: @convention(block) (AnyObject) -> Void = { _ in }
    method_setImplementation(method, imp_implementationWithBlock(noOpBlock))
    Self.didInstallTouchRateCorrectionWorkaround = true
  }

  private func installPlatformChannelIfNeeded() {
    guard platformChannel == nil,
      let controller = resolveFlutterViewController()
    else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "starflow/platform",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setBackgroundPlaybackEnabled":
        let arguments = call.arguments as? [String: Any]
        let enabled = arguments?["enabled"] as? Bool ?? false
        self?.configureBackgroundPlayback(enabled: enabled)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    platformChannel = channel
  }

  private func resolveFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else {
        continue
      }
      for window in windowScene.windows {
        if let controller = window.rootViewController as? FlutterViewController {
          return controller
        }
      }
    }
    return nil
  }

  private func configureBackgroundPlayback(enabled: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      if enabled {
        try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try session.setActive(true)
      } else {
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
      }
    } catch {
      NSLog("Starflow background playback configuration failed: \(error)")
    }
  }
}
