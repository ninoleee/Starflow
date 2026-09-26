import Flutter
import AVFoundation
import AVKit
import MediaPlayer
import ObjectiveC.runtime
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var didInstallTouchRateCorrectionWorkaround = false
  private var platformChannel: FlutterMethodChannel?
  private var playbackSessionChannel: FlutterMethodChannel?
  private let systemVolumeView = MPVolumeView(
    frame: CGRect(x: -1000, y: -1000, width: 1, height: 1)
  )
  private let settingsDocumentExporter = SettingsDocumentExporter()
  private let nativePlaybackStore = NativePlaybackMemoryStore()
  private weak var activeNativePlaybackController: NativePlaybackViewController?
  private lazy var playbackSystemSessionBridge = PlaybackSystemSessionBridge {
    [weak self] in
    self?.resolveTopViewController()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    installFlutterTouchRateCorrectionWorkaroundIfNeeded()
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    ensurePlatformChannelInstalled()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ensurePlatformChannelInstalled()
  }

  func ensurePlatformChannelInstalled() {
    installPlatformChannelIfNeeded()
    installPlaybackSessionChannelIfNeeded()
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
    attachSystemVolumeViewIfNeeded()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "saveLoginQrImage":
        guard let bytes = call.arguments as? FlutterStandardTypedData,
          bytes.data.count <= 1024 * 1024,
          let image = UIImage(data: bytes.data) else {
          result(false)
          return
        }
        let save: (PHAuthorizationStatus) -> Void = { status in
          let hasPhotoAccess: Bool
          if #available(iOS 14, *) {
            hasPhotoAccess = status == .authorized || status == .limited
          } else {
            hasPhotoAccess = status == .authorized
          }
          guard hasPhotoAccess else {
            DispatchQueue.main.async { result(false) }
            return
          }
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
          }) { success, _ in
            DispatchQueue.main.async { result(success) }
          }
        }
        if #available(iOS 14, *) {
          PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: save)
        } else {
          PHPhotoLibrary.requestAuthorization(save)
        }
      case "readPlaybackMemory":
        NativePlaybackMemoryStore.readShared { result($0) }
      case "compareAndSetPlaybackMemory":
        let arguments = call.arguments as? [String: Any]
        NativePlaybackMemoryStore.compareAndSetShared(
          expected: arguments?["expected"] as? String,
          value: arguments?["value"] as? String
        ) { result($0) }
      case "getSystemBrightnessLevel":
        result(UIScreen.main.brightness)
      case "setSystemBrightnessLevel":
        let arguments = call.arguments as? [String: Any]
        let value = arguments?["value"] as? Double ?? 0.5
        DispatchQueue.main.async {
          UIScreen.main.brightness = max(0.0, min(1.0, CGFloat(value)))
          result(nil)
        }
      case "getSystemVolumeLevel":
        result(self?.currentSystemVolumeLevel() ?? AVAudioSession.sharedInstance().outputVolume)
      case "getPlaybackCacheFreeBytes":
        let path = NSTemporaryDirectory()
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
        result((attributes?[.systemFreeSize] as? NSNumber)?.int64Value)
      case "setSystemVolumeLevel":
        let arguments = call.arguments as? [String: Any]
        let value = arguments?["value"] as? Double ?? 0.5
        self?.setSystemVolumeLevel(value)
        result(nil)
      case "setBackgroundPlaybackEnabled":
        let arguments = call.arguments as? [String: Any]
        let enabled = arguments?["enabled"] as? Bool ?? false
        self?.configureBackgroundPlayback(enabled: enabled)
        result(true)
      case "launchNativePlaybackContainer":
        let arguments = call.arguments as? [String: Any]
        let rawUrl =
          (arguments?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title =
          (arguments?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headersJson =
          (arguments?["headersJson"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let playbackTargetJson =
          (arguments?["playbackTargetJson"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let playbackItemKey =
          (arguments?["playbackItemKey"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let seriesKey =
          (arguments?["seriesKey"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let episodeQueueJson =
          (arguments?["episodeQueueJson"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitlePreference =
          (arguments?["subtitlePreference"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "auto"
        let defaultSubtitle =
          (arguments?["defaultSubtitle"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "systemLanguage"
        let backgroundPlaybackEnabled =
          arguments?["backgroundPlaybackEnabled"] as? Bool ?? false
        self?.launchNativePlaybackContainer(
          rawUrl: rawUrl,
          title: title,
          headersJson: headersJson,
          playbackTargetJson: playbackTargetJson,
          playbackItemKey: playbackItemKey,
          seriesKey: seriesKey,
          episodeQueueJson: episodeQueueJson,
          resolverSessionId: arguments?["resolverSessionId"] as? String ?? "",
          backgroundPlaybackEnabled: backgroundPlaybackEnabled,
          subtitlePreference: subtitlePreference,
          defaultSubtitle: defaultSubtitle,
          result: result
        )
      case "openNativeSubtitleMenu":
        DispatchQueue.main.async {
          self?.activeNativePlaybackController?.openExternalSubtitleMenu()
          result(self?.activeNativePlaybackController != nil)
        }
      case "applyNativeExternalSubtitle":
        let arguments = call.arguments as? [String: Any]
        let path = (arguments?["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = (arguments?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
          guard let controller = self?.activeNativePlaybackController, !path.isEmpty else {
            result(false)
            return
          }
          controller.applyExternalSubtitlePath(path, displayName: displayName) { result($0) }
        }
      case "downloadNativeExternalSubtitle":
        let arguments = call.arguments as? [String: Any]
        let url = (arguments?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = (arguments?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "subtitle.srt"
        let headers = (arguments?["headers"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) {
          $0[$1.key] = "\($1.value)"
        }
        DispatchQueue.main.async {
          guard let controller = self?.activeNativePlaybackController, !url.isEmpty else {
            result(false)
            return
          }
          controller.downloadExternalSubtitle(urlString: url, headers: headers, displayName: displayName)
          result(true)
        }
      case "cancelNativeExternalSubtitle":
        DispatchQueue.main.async {
          guard let controller = self?.activeNativePlaybackController else {
            result(false)
            return
          }
          controller.cancelExternalSubtitleOperation(notifyResolver: true)
          result(true)
        }
      case "clearNativeExternalSubtitle":
        DispatchQueue.main.async {
          guard let controller = self?.activeNativePlaybackController else {
            result(false)
            return
          }
          controller.clearExternalSubtitle()
          result(true)
        }
      case "launchSystemVideoPlayer":
        let arguments = call.arguments as? [String: Any]
        let rawUrl =
          (arguments?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title =
          (arguments?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headersJson =
          (arguments?["headersJson"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self?.launchExternalVideoPlayer(
          rawUrl: rawUrl,
          title: title,
          headersJson: headersJson,
          result: result
        )
      case "exportDocument":
        let arguments = call.arguments as? [String: Any]
        let sourcePath =
          (arguments?["sourcePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          ?? ""
        self?.exportDocument(sourcePath: sourcePath, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    platformChannel = channel
  }

  private func attachSystemVolumeViewIfNeeded() {
    guard let controller = resolveFlutterViewController() else {
      return
    }
    if systemVolumeView.superview === controller.view {
      return
    }
    systemVolumeView.isHidden = true
    controller.view.addSubview(systemVolumeView)
  }

  private func currentSystemVolumeLevel() -> Float {
    if let sliderLevel = currentSystemVolumeSliderLevel() {
      return sliderLevel
    }
    return AVAudioSession.sharedInstance().outputVolume
  }

  private func setSystemVolumeLevel(_ value: Double) {
    let clamped = Float(max(0.0, min(1.0, value)))
    DispatchQueue.main.async { [weak self] in
      self?.attachSystemVolumeViewIfNeeded()
      guard
        let slider = self?.systemVolumeView.subviews.compactMap({ $0 as? UISlider }).first
      else {
        return
      }
      slider.setValue(clamped, animated: false)
      slider.sendActions(for: .valueChanged)
      slider.sendActions(for: .touchUpInside)
    }
  }

  private func currentSystemVolumeSliderLevel() -> Float? {
    if Thread.isMainThread {
      attachSystemVolumeViewIfNeeded()
      return systemVolumeView.subviews.compactMap { $0 as? UISlider }.first?.value
    }

    var sliderLevel: Float?
    DispatchQueue.main.sync { [weak self] in
      self?.attachSystemVolumeViewIfNeeded()
      sliderLevel = self?.systemVolumeView.subviews.compactMap { $0 as? UISlider }.first?.value
    }
    return sliderLevel
  }

  private func installPlaybackSessionChannelIfNeeded() {
    guard playbackSessionChannel == nil,
      let controller = resolveFlutterViewController()
    else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "starflow/playback_session",
      binaryMessenger: controller.binaryMessenger
    )
    playbackSystemSessionBridge.bind(to: channel)
    playbackSessionChannel = channel
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

  private func resolveTopViewController() -> UIViewController? {
    guard let root = resolveFlutterViewController() ?? resolveAnyRootViewController() else {
      return nil
    }

    var current = root
    while let presented = current.presentedViewController {
      current = presented
    }
    return current
  }

  private func resolveAnyRootViewController() -> UIViewController? {
    if let root = window?.rootViewController {
      return root
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else {
        continue
      }
      for window in windowScene.windows {
        if let root = window.rootViewController {
          return root
        }
      }
    }
    return nil
  }

  private func configureBackgroundPlayback(enabled: Bool) {
    StarflowAudioSession.configurePlayback(
      enabled: enabled,
      owner: "background-playback"
    )
  }

  private func exportDocument(
    sourcePath: String,
    result: @escaping FlutterResult
  ) {
    guard !sourcePath.isEmpty else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing sourcePath for document export.",
          details: nil
        )
      )
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self,
        let presenter = self.resolveTopViewController()
      else {
        result(
          FlutterError(
            code: "no_presenter",
            message: "Unable to present the document exporter.",
            details: nil
          )
        )
        return
      }

      self.settingsDocumentExporter.exportDocument(
        sourcePath: sourcePath,
        presenter: presenter,
        result: result
      )
    }
  }

  private func launchNativePlaybackContainer(
    rawUrl: String,
    title: String,
    headersJson: String,
    playbackTargetJson: String,
    playbackItemKey: String,
    seriesKey: String,
    episodeQueueJson: String,
    resolverSessionId: String,
    backgroundPlaybackEnabled: Bool,
    subtitlePreference: String,
    defaultSubtitle: String,
    result: @escaping FlutterResult
  ) {
    guard !rawUrl.isEmpty,
      let url = URL(string: rawUrl),
      url.scheme != nil
    else {
      result(false)
      return
    }

    let request = NativePlaybackRequest(
      url: url,
      title: title,
      headers: decodeHeadersJson(headersJson),
      playbackTargetJson: playbackTargetJson,
      playbackItemKey: playbackItemKey,
      seriesKey: seriesKey
    )

    DispatchQueue.main.async { [weak self] in
      guard let self,
        let presenter = self.resolveTopViewController()
      else {
        result(false)
        return
      }

      let controller = NativePlaybackViewController(
        request: request,
        episodeQueue: NativeEpisodeQueue.fromJsonString(episodeQueueJson),
        backgroundPlaybackEnabled: backgroundPlaybackEnabled,
        subtitlePreference: subtitlePreference,
        defaultSubtitle: defaultSubtitle,
        playbackStore: self.nativePlaybackStore,
        resolverSessionId: resolverSessionId,
        resolverChannel: self.resolveFlutterViewController().map {
          FlutterMethodChannel(name: "starflow/native_playback_resolver", binaryMessenger: $0.binaryMessenger)
        }
      )
      self.activeNativePlaybackController = controller
      controller.modalPresentationStyle = .fullScreen
      presenter.present(controller, animated: true) {
        result(true)
      }
    }
  }

  private func launchExternalVideoPlayer(
    rawUrl: String,
    title: String,
    headersJson: String,
    result: @escaping FlutterResult
  ) {
    guard !rawUrl.isEmpty,
      let streamUrl = URL(string: rawUrl),
      streamUrl.scheme != nil
    else {
      result(false)
      return
    }

    let headers = decodeHeadersJson(headersJson)
    let safeTitle = sanitizedPlaylistValue(title.isEmpty ? "Starflow" : title)
    var lines = ["#EXTM3U", "#EXTINF:-1,\(safeTitle)"]
    if !headers.isEmpty,
      let headersData = try? JSONSerialization.data(withJSONObject: headers),
      let headersValue = String(data: headersData, encoding: .utf8)
    {
      lines.append("#EXTHTTP:\(headersValue)")
    }
    for (key, value) in headers {
      let normalizedKey = key.lowercased()
      let safeValue = sanitizedPlaylistValue(value)
      switch normalizedKey {
      case "user-agent":
        lines.append("#EXTVLCOPT:http-user-agent=\(safeValue)")
      case "referer", "referrer":
        lines.append("#EXTVLCOPT:http-referrer=\(safeValue)")
      case "cookie":
        lines.append("#EXTVLCOPT:http-cookie=\(safeValue)")
      default:
        break
      }
    }
    lines.append(sanitizedPlaylistValue(streamUrl.absoluteString))
    lines.append("")

    let playlistUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("starflow-\(UUID().uuidString)")
      .appendingPathExtension("m3u")
    do {
      try lines.joined(separator: "\n").write(
        to: playlistUrl,
        atomically: true,
        encoding: .utf8
      )
    } catch {
      result(false)
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self,
        let presenter = self.resolveTopViewController()
      else {
        try? FileManager.default.removeItem(at: playlistUrl)
        result(false)
        return
      }
      let controller = UIActivityViewController(
        activityItems: [playlistUrl],
        applicationActivities: nil
      )
      controller.popoverPresentationController?.sourceView = presenter.view
      controller.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 1,
        height: 1
      )
      controller.completionWithItemsHandler = { _, completed, _, _ in
        try? FileManager.default.removeItem(at: playlistUrl)
        result(completed)
      }
      presenter.present(controller, animated: true)
    }
  }

  private func sanitizedPlaylistValue(_ raw: String) -> String {
    raw.replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }

  private func decodeHeadersJson(_ raw: String) -> [String: String] {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }

    var headers: [String: String] = [:]
    for (key, value) in object {
      headers[key] = "\(value)"
    }
    return headers
  }
}
