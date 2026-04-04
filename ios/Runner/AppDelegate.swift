import Flutter
import ObjectiveC.runtime
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var didInstallTouchRateCorrectionWorkaround = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    installFlutterTouchRateCorrectionWorkaroundIfNeeded()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
