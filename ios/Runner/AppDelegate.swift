import Flutter
import AVFoundation
import AVKit
import MediaPlayer
import ObjectiveC.runtime
import UIKit

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
        let subtitlePreferredLanguages =
          (arguments?["subtitlePreferredLanguages"] as? [String] ?? [])
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
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
          backgroundPlaybackEnabled: backgroundPlaybackEnabled,
          subtitlePreference: subtitlePreference,
          subtitlePreferredLanguages: subtitlePreferredLanguages,
          result: result
        )
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
    backgroundPlaybackEnabled: Bool,
    subtitlePreference: String,
    subtitlePreferredLanguages: [String],
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
        subtitlePreferredLanguages: subtitlePreferredLanguages,
        playbackStore: self.nativePlaybackStore
      )
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

private final class SettingsDocumentExporter: NSObject, UIDocumentPickerDelegate {
  private let fileManager: FileManager
  private var pendingResult: FlutterResult?
  private weak var picker: UIDocumentPickerViewController?

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func exportDocument(
    sourcePath: String,
    presenter: UIViewController,
    result: @escaping FlutterResult
  ) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "export_in_progress",
          message: "A document export is already in progress.",
          details: nil
        )
      )
      return
    }

    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      result(
        FlutterError(
          code: "source_not_found",
          message: "The export file could not be found.",
          details: sourcePath
        )
      )
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
    }

    picker.delegate = self
    picker.modalPresentationStyle = .formSheet
    pendingResult = result
    self.picker = picker
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finish(with: urls.first)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentAt url: URL
  ) {
    finish(with: url)
  }

  private func finish(with url: URL?) {
    let result = pendingResult
    cleanup()
    if let url {
      result?([
        "path": url.path,
      ])
      return
    }
    result?(nil)
  }

  private func cleanup() {
    picker?.delegate = nil
    picker = nil
    pendingResult = nil
  }
}

private struct NativePlaybackRequest {
  let url: URL
  let title: String
  let headers: [String: String]
  let playbackTargetJson: String
  let playbackItemKey: String
  let seriesKey: String

  var allowsResume: Bool {
    guard let data = playbackTargetJson.data(using: .utf8),
      let target = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return true
    }
    return target["allowResume"] as? Bool ?? true
  }
}

private struct NativeEpisodeQueueEntry {
  let request: NativePlaybackRequest

  init?(json: [String: Any]) {
    let target = json["target"] as? [String: Any] ?? [:]
    let streamUrl = (target["streamUrl"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? ""
    guard let url = URL(string: streamUrl), url.scheme != nil else {
      return nil
    }

    let headers = (target["headers"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) {
      partialResult,
      item in
      partialResult[item.key] = "\(item.value)"
    }
    let targetData = (try? JSONSerialization.data(withJSONObject: target)) ?? Data("{}".utf8)
    let playbackTargetJson = String(data: targetData, encoding: .utf8) ?? "{}"
    request = NativePlaybackRequest(
      url: url,
      title: (target["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      headers: headers,
      playbackTargetJson: playbackTargetJson,
      playbackItemKey: (json["playbackItemKey"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      seriesKey: (json["seriesKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
    )
  }

  func toJsonObject() -> [String: Any] {
    return [
      "target": targetObject(),
      "playbackItemKey": request.playbackItemKey,
      "seriesKey": request.seriesKey,
    ]
  }

  private func targetObject() -> [String: Any] {
    guard let data = request.playbackTargetJson.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }
}

private struct NativeEpisodeQueue {
  let entries: [NativeEpisodeQueueEntry]
  let currentIndex: Int

  var hasPrevious: Bool {
    currentIndex > 0 && currentIndex < entries.count
  }

  var hasNext: Bool {
    currentIndex >= 0 && currentIndex + 1 < entries.count
  }

  var currentEntry: NativeEpisodeQueueEntry? {
    guard currentIndex >= 0 && currentIndex < entries.count else {
      return nil
    }
    return entries[currentIndex]
  }

  func moveToNext() -> NativeEpisodeQueue? {
    guard hasNext else {
      return nil
    }
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex + 1)
  }

  func moveToPrevious() -> NativeEpisodeQueue? {
    guard hasPrevious else {
      return nil
    }
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex - 1)
  }

  func toJsonString() -> String {
    let object: [String: Any] = [
      "currentIndex": currentIndex,
      "entries": entries.map { $0.toJsonObject() },
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else {
      return ""
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func fromJsonString(_ raw: String) -> NativeEpisodeQueue? {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    let entryObjects = object["entries"] as? [[String: Any]] ?? []
    let entries = entryObjects.compactMap(NativeEpisodeQueueEntry.init)
    guard !entries.isEmpty else {
      return nil
    }
    let currentIndex = min(
      max((object["currentIndex"] as? NSNumber)?.intValue ?? 0, 0),
      entries.count - 1
    )
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex)
  }
}

private struct NativeSubtitleTrackFingerprint {
  let label: String
  let language: String
  let isForced: Bool
}

private enum NativeSubtitleSessionPreference {
  case off
  case single(NativeSubtitleTrackFingerprint)
}

private final class NativePlaybackViewController: AVPlayerViewController {
  private static let persistThresholdMs: Int64 = 10_000
  private static let playbackStartupTimeoutSeconds: TimeInterval = 30

  private let playbackStore: NativePlaybackMemoryStore
  private let backgroundPlaybackEnabled: Bool
  private let subtitlePreference: String
  private let subtitlePreferredLanguages: [String]
  private let isoFormatter = ISO8601DateFormatter()
  private var request: NativePlaybackRequest
  private var episodeQueue: NativeEpisodeQueue?
  private var startupGate: NativePlaybackStartupGate?
  private var playbackStartupTimeoutWorkItem: DispatchWorkItem?
  private var playbackFailureAlert: UIAlertController?
  private let stallRecovery = NativePlaybackStallRecovery()
  private let metricsTracker = NativePlaybackMetricsTracker()
  private let artworkLoader = StarflowNowPlayingArtworkLoader()
  private var timeObserverToken: Any?
  private var endObserver: NSObjectProtocol?
  private var playbackStateObservation: NSKeyValueObservation?
  private var playbackItemStatusObservation: NSKeyValueObservation?
  private var appObservers: [NSObjectProtocol] = []
  private var lastSavedPositionMs: Int64 = -1
  private var remoteCommandsInstalled = false
  private var interruptionWasPlaying = false
  private var backgroundDisabledVideoTracks: [AVPlayerItemTrack] = []
  private var appIsInBackground = false
  private var subtitleSessionPreference: NativeSubtitleSessionPreference?

  init(
    request: NativePlaybackRequest,
    episodeQueue: NativeEpisodeQueue?,
    backgroundPlaybackEnabled: Bool,
    subtitlePreference: String,
    subtitlePreferredLanguages: [String],
    playbackStore: NativePlaybackMemoryStore
  ) {
    self.request = request
    self.episodeQueue = episodeQueue
    self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
    self.subtitlePreference = subtitlePreference
    self.subtitlePreferredLanguages = subtitlePreferredLanguages
    self.playbackStore = playbackStore
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit { teardownPlayback() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    showsPlaybackControls = true
    allowsPictureInPicturePlayback = true
    updatesNowPlayingInfoCenter = false
    title = request.title
    cleanupCustomOverlayIfNeeded()
    configurePlayer()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    persistPlaybackProgress(force: true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || presentingViewController == nil {
      teardownPlayback()
    }
  }

  private func configurePlayer() {
    captureCurrentSubtitleSessionPreference()
    teardownPlayback()
    configureAudioSession(enabled: true)

    let resumePositionMs = request.allowsResume
      ? playbackStore.loadResumePositionMs(itemKey: request.playbackItemKey)
      : 0
    let assetOptions: [String: Any]? = request.headers.isEmpty
      ? nil
      : ["AVURLAssetHTTPHeaderFieldsKey": request.headers]
    let asset = AVURLAsset(url: request.url, options: assetOptions)
    let item = AVPlayerItem(asset: asset)
    applyAutomaticSubtitleSelection(to: item, asset: asset)

    if !request.title.isEmpty {
      let metadataItem = AVMutableMetadataItem()
      metadataItem.identifier = .commonIdentifierTitle
      metadataItem.value = request.title as NSString
      metadataItem.extendedLanguageTag = "und"
      item.externalMetadata = [metadataItem]
    }

    let player = AVPlayer(playerItem: item)
    let bufferingContext = NativePlaybackBufferingTuning.Context(
      url: request.url,
      headers: request.headers
    )
    NativePlaybackBufferingTuning.apply(
      playerItem: item,
      player: player,
      context: bufferingContext,
      peakBitRateProfile: .unlimited
    )
    self.player = player
    metricsTracker.attach(player: player, item: item)

    installRemoteCommands()
    registerAppLifecycleObservers()
    installEndObserver(for: item)
    installTimeObserver(for: player)
    installPlaybackStateObserver(for: player)
    installPlaybackItemStatusObserver(for: item)
    stallRecovery.start(player: player, item: item)
    schedulePlaybackStartupTimeout()

    let startupGate = NativePlaybackStartupGate(
      player: player,
      item: item,
      configuration: makeStartupGateConfiguration(for: bufferingContext)
    )
    self.startupGate = startupGate

    let resumeSeekTime: CMTime? =
      resumePositionMs > 5_000
      ? CMTime(value: CMTimeValue(resumePositionMs), timescale: CMTimeScale(1000))
      : nil

    startupGate.start(resumeSeekTime: resumeSeekTime) { [weak self, weak player, weak item] result in
      guard let self = self else {
        return
      }
      if self.startupGate === startupGate {
        self.startupGate = nil
      }
      guard let player = player, self.player === player else {
        return
      }
      if let item = item {
        self.metricsTracker.refreshAccessErrorLog(item: item)
      }
      switch result {
      case .started:
        self.updateNowPlayingInfo()
      case .failed(let error):
        self.showPlaybackFailure(error: error)
      case .cancelled:
        break
      }
    }
    refreshRemoteCommandAvailability()
  }

  private func applyAutomaticSubtitleSelection(
    to item: AVPlayerItem,
    asset: AVURLAsset
  ) {
    asset.loadValuesAsynchronously(
      forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"]
    ) { [weak self, weak item] in
      DispatchQueue.main.async {
        guard let self, let item, self.player?.currentItem === item,
          let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else {
          return
        }
        if let sessionPreference = self.subtitleSessionPreference {
          switch sessionPreference {
          case .off:
            item.select(nil, in: group)
            return
          case .single(let fingerprint):
            if let restored = self.matchSubtitleOption(
              in: group.options,
              fingerprint: fingerprint
            ) {
              item.select(restored, in: group)
              return
            }
          }
        }

        if self.subtitlePreference == "off" {
          item.select(nil, in: group)
          return
        }

        let preferredLanguages = self.subtitlePreferredLanguages.isEmpty
          ? Array(Locale.preferredLanguages.prefix(1))
          : self.subtitlePreferredLanguages
        let preferredOption = preferredLanguages.lazy.compactMap { language in
          group.options.first { option in
            self.subtitleOption(option, matches: language)
          }
        }.first
        let forcedOption = group.options.first { option in
          option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            || self.isForcedSubtitleLabel(option.displayName)
        }
        item.select(preferredOption ?? forcedOption ?? group.defaultOption, in: group)
      }
    }
  }

  private func captureCurrentSubtitleSessionPreference() {
    guard let item = player?.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else {
      return
    }
    guard let selected = item.currentMediaSelection.selectedMediaOption(in: group) else {
      subtitleSessionPreference = .off
      return
    }
    subtitleSessionPreference = .single(
      NativeSubtitleTrackFingerprint(
        label: selected.displayName,
        language: selected.locale?.identifier ?? "",
        isForced: selected.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
          || isForcedSubtitleLabel(selected.displayName)
      )
    )
  }

  private func matchSubtitleOption(
    in options: [AVMediaSelectionOption],
    fingerprint: NativeSubtitleTrackFingerprint
  ) -> AVMediaSelectionOption? {
    var bestOption: AVMediaSelectionOption?
    var bestScore = 0
    for option in options {
      let optionLanguage = canonicalSubtitleLanguage(option.locale?.identifier ?? "")
      let preferredLanguage = canonicalSubtitleLanguage(fingerprint.language)
      let optionLabel = normalizedSubtitleLabel(option.displayName)
      let preferredLabel = normalizedSubtitleLabel(fingerprint.label)
      let optionForced = option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
        || isForcedSubtitleLabel(option.displayName)
      var score = 0
      if !optionLanguage.isEmpty, !preferredLanguage.isEmpty {
        if optionLanguage == preferredLanguage {
          score += 120
        } else if optionLanguage.split(separator: "-").first
          == preferredLanguage.split(separator: "-").first
        {
          score += 72
          } else {
            score -= 200
        }
      }
      if !optionLabel.isEmpty, !preferredLabel.isEmpty {
        if optionLabel == preferredLabel {
          score += 100
        } else if optionLabel.contains(preferredLabel) || preferredLabel.contains(optionLabel) {
          score += 54
        }
      }
      if optionForced == fingerprint.isForced {
        score += 5
      }
      if score > bestScore {
        bestOption = option
        bestScore = score
      }
    }
    return bestScore >= 30 ? bestOption : nil
  }

  private func subtitleOption(
    _ option: AVMediaSelectionOption,
    matches rawPreference: String
  ) -> Bool {
    let preference = canonicalSubtitleLanguage(rawPreference)
    guard !preference.isEmpty else {
      return false
    }
    let optionLanguage = canonicalSubtitleLanguage(option.locale?.identifier ?? "")
    if optionLanguage == preference {
      return true
    }
    let optionRoot = optionLanguage.split(separator: "-").first.map(String.init) ?? ""
    let preferenceRoot = preference.split(separator: "-").first.map(String.init) ?? ""
    if !optionRoot.isEmpty, optionRoot == preferenceRoot,
      optionRoot != "zh" || optionLanguage == "zh" || preference == "zh"
    {
      return true
    }

    let label = normalizedSubtitleLabel(option.displayName)
    return subtitleLanguageTokens(preference).contains { label.contains($0) }
  }

  private func canonicalSubtitleLanguage(_ raw: String) -> String {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
    switch normalized {
    case "", "und", "zxx", "null", "unknown": return ""
    case "english", "eng": return "en"
    case "japanese", "jpn": return "ja"
    case "korean", "kor": return "ko"
    case "chinese", "chi", "zho": return "zh"
    case "zh-hans", "zh-sg": return "zh-cn"
    case "zh-hant", "zh-hk", "zh-mo": return "zh-tw"
    default: return normalized
    }
  }

  private func subtitleLanguageTokens(_ language: String) -> [String] {
    switch language {
    case "zh-cn": return ["zhcn", "zhhans", "chs", "简体", "簡體", "简中"]
    case "zh-tw": return ["zhtw", "zhhant", "cht", "繁体", "繁體", "繁中"]
    case "zh": return ["chinese", "中文", "国语", "國語"]
    case "en": return ["english", " eng ", "英语", "英語", "英文"]
    case "ja": return ["japanese", " jpn ", "日语", "日語", "日本語"]
    case "ko": return ["korean", " kor ", "韩语", "韓語", "한국어"]
    default: return [language.replacingOccurrences(of: "-", with: "")]
    }
  }

  private func isForcedSubtitleLabel(_ label: String) -> Bool {
    let normalized = normalizedSubtitleLabel(label)
    return [
      "forced", "force", "signs", "强制", "強制", "强迫",
      "仅外语", "僅外語", "外语对白", "外語對白",
    ].contains { normalized.contains($0) }
  }

  private func normalizedSubtitleLabel(_ label: String) -> String {
    return label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func makeStartupGateConfiguration(
    for bufferingContext: NativePlaybackBufferingTuning.Context
  ) -> NativePlaybackStartupGate.Configuration {
    guard bufferingContext.isRemoteURL else {
      return NativePlaybackStartupGate.Configuration(
        waitForLikelyToKeepUp: false,
        usePreroll: false,
        prerollRate: 1.0,
        keepUpTimeout: 0
      )
    }

    if bufferingContext.isLiveStream {
      return NativePlaybackStartupGate.Configuration(
        waitForLikelyToKeepUp: true,
        usePreroll: false,
        prerollRate: 1.0,
        keepUpTimeout: 1.2
      )
    }

    return .balanced
  }

  private func cleanupCustomOverlayIfNeeded() {
    guard let overlayView = contentOverlayView else {
      return
    }

    for subview in overlayView.subviews {
      if let button = subview as? UIButton,
        let title = button.title(for: .normal),
        title.contains("查字幕")
      {
        subview.removeFromSuperview()
        continue
      }
      if subview is AVRoutePickerView {
        subview.removeFromSuperview()
      }
    }
  }

  private func configureAudioSession(enabled: Bool) {
    StarflowAudioSession.configurePlayback(
      enabled: enabled,
      owner: "native-playback-container"
    )
  }

  private func installRemoteCommands() {
    guard !remoteCommandsInstalled else {
      return
    }

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.stopCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.stopCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [10]
    commandCenter.skipBackwardCommand.preferredIntervals = [10]

    commandCenter.playCommand.addTarget { [weak self] _ in
      guard let self, self.canStartPlaybackFromCurrentAppState else {
        return .commandFailed
      }
      self.configureAudioSession(enabled: true)
      self.player?.play()
      self.updateNowPlayingInfo()
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.player?.pause()
      self?.configureAudioSession(enabled: false)
      self?.updateNowPlayingInfo()
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self, let player = self.player else {
        return .commandFailed
      }
      if player.timeControlStatus == .paused {
        guard self.canStartPlaybackFromCurrentAppState else {
          return .commandFailed
        }
        self.configureAudioSession(enabled: true)
        player.play()
      } else {
        player.pause()
        self.configureAudioSession(enabled: false)
      }
      self.updateNowPlayingInfo()
      return .success
    }
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.seekBy(seconds: 10)
      return .success
    }
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.seekBy(seconds: -10)
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      guard let self else {
        return .commandFailed
      }
      return self.advanceToAdjacentEpisode(forward: true)
        ? .success
        : .commandFailed
    }
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      guard let self else {
        return .commandFailed
      }
      return self.advanceToAdjacentEpisode(forward: false)
        ? .success
        : .commandFailed
    }
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let time = CMTime(seconds: event.positionTime, preferredTimescale: 600)
      self.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
      self.updateNowPlayingInfo()
      return .success
    }

    remoteCommandsInstalled = true
    refreshRemoteCommandAvailability()
  }

  private func uninstallRemoteCommands() {
    guard remoteCommandsInstalled else {
      return
    }
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.stopCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    remoteCommandsInstalled = false
  }

  private func refreshRemoteCommandAvailability() {
    let commandCenter = MPRemoteCommandCenter.shared()
    let hasEpisodeQueue = (episodeQueue?.entries.count ?? 0) > 1
    commandCenter.skipForwardCommand.isEnabled = !hasEpisodeQueue
    commandCenter.skipBackwardCommand.isEnabled = !hasEpisodeQueue
    commandCenter.nextTrackCommand.isEnabled =
      hasEpisodeQueue && episodeQueue?.hasNext == true
    commandCenter.previousTrackCommand.isEnabled =
      hasEpisodeQueue && episodeQueue?.hasPrevious == true
  }

  private func seekBy(seconds: Double) {
    guard let player else {
      return
    }
    let currentSeconds = player.currentTime().seconds
    let nextSeconds = max(currentSeconds.isFinite ? currentSeconds + seconds : seconds, 0.0)
    let time = CMTime(seconds: nextSeconds, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    updateNowPlayingInfo()
  }

  @discardableResult
  private func advanceToAdjacentEpisode(forward: Bool) -> Bool {
    let nextQueue = forward ? episodeQueue?.moveToNext() : episodeQueue?.moveToPrevious()
    guard let nextQueue, let nextEntry = nextQueue.currentEntry else {
      return false
    }

    persistPlaybackProgress(force: true)
    episodeQueue = nextQueue
    request = nextEntry.request
    title = request.title
    configurePlayer()
    updateNowPlayingInfo()
    return true
  }

  private func updateNowPlayingInfo() {
    guard backgroundPlaybackEnabled || !appIsInBackground else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    guard let player else {
      return
    }

    let targetObject = playbackStore.decodeTargetJson(request.playbackTargetJson)
    let seriesTitle = (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed ?? ""
    let sourceName = (targetObject["sourceName"] as? String)?.nonEmptyTrimmed ?? ""
    let artworkCandidates = resolveNowPlayingArtworkCandidates(from: targetObject)
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = request.title.isEmpty ? "Starflow" : request.title

    let subtitle = !seriesTitle.isEmpty ? seriesTitle : sourceName
    if subtitle.isEmpty {
      info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
      info.removeValue(forKey: MPMediaItemPropertyArtist)
    } else {
      info[MPMediaItemPropertyAlbumTitle] = subtitle
      info[MPMediaItemPropertyArtist] = subtitle
    }

    let durationSeconds = player.currentItem?.duration.seconds ?? 0
    if durationSeconds.isFinite && durationSeconds > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
    } else {
      info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
    }

    let elapsedSeconds = player.currentTime().seconds
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      elapsedSeconds.isFinite ? max(elapsedSeconds, 0.0) : 0.0
    let playbackRate = Double(player.rate)
    info[MPNowPlayingInfoPropertyPlaybackRate] =
      player.timeControlStatus == .playing ? max(playbackRate, 0.01) : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] =
      playbackRate > 0 ? playbackRate : 1.0
    artworkLoader.applyArtwork(
      to: &info,
      candidates: artworkCandidates
    ) { [weak self] in
      self?.updateNowPlayingInfo()
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func resolveNowPlayingArtworkCandidates(
    from targetObject: [String: Any]
  ) -> [StarflowNowPlayingArtworkCandidate] {
    var candidates: [StarflowNowPlayingArtworkCandidate] = []
    let posterUrl = (targetObject["posterUrl"] as? String)?.nonEmptyTrimmed ?? ""
    if !posterUrl.isEmpty {
      candidates.append(
        StarflowNowPlayingArtworkCandidate(
          urlString: posterUrl,
          headers: normalizedStringMap(targetObject["posterHeaders"] as? [String: Any])
        )
      )
    }

    let backdropUrl = (targetObject["backdropUrl"] as? String)?.nonEmptyTrimmed ?? ""
    if !backdropUrl.isEmpty {
      candidates.append(
        StarflowNowPlayingArtworkCandidate(
          urlString: backdropUrl,
          headers: normalizedStringMap(targetObject["backdropHeaders"] as? [String: Any])
        )
      )
    }

    return normalizedNowPlayingArtworkCandidates(candidates)
  }

  private func installPlaybackStateObserver(for player: AVPlayer) {
    playbackStateObservation = player.observe(
      \.timeControlStatus,
      options: [.initial, .new]
    ) { [weak self] player, _ in
      DispatchQueue.main.async {
        self?.syncAudioSessionForPlaybackState(player)
        self?.updateNowPlayingInfo()
      }
    }
  }

  private func registerAppLifecycleObservers() {
    guard appObservers.isEmpty else {
      return
    }
    let center = NotificationCenter.default
    appObservers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else {
          return
        }
        self.appIsInBackground = true
        self.persistPlaybackProgress(force: true)
        if self.backgroundPlaybackEnabled {
          self.setBackgroundAudioOnly(self.player?.timeControlStatus != .paused)
        } else {
          self.player?.pause()
          self.configureAudioSession(enabled: false)
          self.uninstallRemoteCommands()
          self.artworkLoader.reset()
          MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
      }
    )
    appObservers.append(
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else {
          return
        }
        self.appIsInBackground = false
        self.setBackgroundAudioOnly(false)
        self.installRemoteCommands()
        self.updateNowPlayingInfo()
      }
    )
    appObservers.append(
      center.addObserver(
        forName: UIApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.persistPlaybackProgress(force: true)
      }
    )
    appObservers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioSessionInterruption(notification)
      }
    )
    appObservers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioRouteChange(notification)
      }
    )
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
    guard let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType) else {
      return
    }

    switch interruptionType {
    case .began:
      interruptionWasPlaying = player?.timeControlStatus != .paused
      if interruptionWasPlaying {
        player?.pause()
        configureAudioSession(enabled: false)
        updateNowPlayingInfo()
      }
    case .ended:
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      let shouldResume = interruptionWasPlaying && options.contains(.shouldResume)
      interruptionWasPlaying = false
      if shouldResume && (backgroundPlaybackEnabled || !appIsInBackground) {
        configureAudioSession(enabled: true)
        player?.play()
        updateNowPlayingInfo()
      }
    @unknown default:
      break
    }
  }

  private func handleAudioRouteChange(_ notification: Notification) {
    let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
    guard let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
      reason == .oldDeviceUnavailable
    else {
      return
    }

    let previousRoute =
      notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
    let shouldPause = previousRoute?.outputs.contains(where: { output in
      switch output.portType {
      case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .lineOut, .usbAudio:
        return true
      default:
        return false
      }
    }) ?? false
    if shouldPause {
      player?.pause()
      configureAudioSession(enabled: false)
      updateNowPlayingInfo()
    }
  }

  private func syncAudioSessionForPlaybackState(_ player: AVPlayer) {
    guard canStartPlaybackFromCurrentAppState else {
      if player.timeControlStatus != .paused {
        player.pause()
      }
      configureAudioSession(enabled: false)
      return
    }
    configureAudioSession(enabled: player.timeControlStatus != .paused)
  }

  private var canStartPlaybackFromCurrentAppState: Bool {
    return backgroundPlaybackEnabled || !appIsInBackground
  }

  private func setBackgroundAudioOnly(_ enabled: Bool) {
    guard let item = player?.currentItem else {
      backgroundDisabledVideoTracks.removeAll()
      return
    }
    if enabled {
      guard backgroundDisabledVideoTracks.isEmpty else {
        return
      }
      let activeVideoTracks = item.tracks.filter { track in
        track.isEnabled && track.assetTrack?.mediaType == .video
      }
      backgroundDisabledVideoTracks = activeVideoTracks
      for track in activeVideoTracks {
        track.isEnabled = false
      }
      return
    }
    for track in backgroundDisabledVideoTracks where item.tracks.contains(where: { $0 === track }) {
      track.isEnabled = true
    }
    backgroundDisabledVideoTracks.removeAll()
  }

  private func installTimeObserver(for player: AVPlayer) {
    let interval = CMTime(seconds: 2, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      if time.seconds.isFinite && time.seconds > 0 {
        self?.markPlaybackFirstFrameReady()
      }
      self?.persistPlaybackProgress()
    }
  }

  private func installPlaybackItemStatusObserver(for item: AVPlayerItem) {
    playbackItemStatusObservation = item.observe(\.status, options: [.new]) {
      [weak self] item, _ in
      guard item.status == .failed else {
        return
      }
      DispatchQueue.main.async {
        self?.showPlaybackFailure(error: item.error)
      }
    }
  }

  private func schedulePlaybackStartupTimeout() {
    playbackStartupTimeoutWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.showPlaybackFailure(
        message: "30 秒内未显示视频画面，请检查网络或重试播放。"
      )
    }
    playbackStartupTimeoutWorkItem = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.playbackStartupTimeoutSeconds,
      execute: work
    )
  }

  private func markPlaybackFirstFrameReady() {
    playbackStartupTimeoutWorkItem?.cancel()
    playbackStartupTimeoutWorkItem = nil
  }

  private func showPlaybackFailure(error: Error? = nil, message: String? = nil) {
    guard playbackFailureAlert == nil, viewIfLoaded?.window != nil else {
      return
    }
    playbackStartupTimeoutWorkItem?.cancel()
    playbackStartupTimeoutWorkItem = nil
    let detail = message ?? (error?.localizedDescription.nonEmptyTrimmed)
      ?? "当前终端无法解码此视频，请重试或退出。"

    teardownPlayback()
    player = nil

    let alert = UIAlertController(
      title: "播放失败",
      message: detail,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: "重试", style: .default) { [weak self] _ in
        guard let self else {
          return
        }
        self.playbackFailureAlert = nil
        self.configurePlayer()
      }
    )
    alert.addAction(
      UIAlertAction(title: "退出", style: .cancel) { [weak self] _ in
        guard let self else {
          return
        }
        self.playbackFailureAlert = nil
        self.dismiss(animated: true)
      }
    )
    playbackFailureAlert = alert
    present(alert, animated: true)
  }

  private func installEndObserver(for item: AVPlayerItem) {
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      if self?.advanceToAdjacentEpisode(forward: true) == true {
        return
      }
      self?.persistPlaybackProgress(force: true)
      self?.updateNowPlayingInfo()
    }
  }

  private func teardownPlayback() {
    let hadPlayback = !appObservers.isEmpty || player != nil
    if hadPlayback {
      persistPlaybackProgress(force: true)
    }

    startupGate?.cancel()
    startupGate = nil
    playbackStartupTimeoutWorkItem?.cancel()
    playbackStartupTimeoutWorkItem = nil
    stallRecovery.stop()
    metricsTracker.detach()
    playbackStateObservation = nil
    playbackItemStatusObservation = nil

    if let token = timeObserverToken,
      let currentPlayer = player
    {
      currentPlayer.removeTimeObserver(token)
    }
    timeObserverToken = nil

    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    endObserver = nil

    for observer in appObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    appObservers.removeAll()

    setBackgroundAudioOnly(false)
    player?.pause()
    interruptionWasPlaying = false
    appIsInBackground = false
    uninstallRemoteCommands()
    artworkLoader.reset()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if hadPlayback {
      configureAudioSession(enabled: false)
    }
  }

  private func persistPlaybackProgress(force: Bool = false) {
    guard let player else {
      return
    }

    let positionMs = player.currentTime().milliseconds.clampedToNonNegative
    let durationMs = player.currentItem?.duration.milliseconds.clampedToNonNegative ?? 0
    if !force && abs(positionMs - lastSavedPositionMs) < Self.persistThresholdMs {
      return
    }
    lastSavedPositionMs = positionMs

    playbackStore.savePlaybackEntry(
      targetJson: request.playbackTargetJson,
      itemKey: request.playbackItemKey,
      seriesKey: request.seriesKey,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: isoFormatter.string(from: Date())
    )
  }
}

private final class NativePlaybackMemoryStore {
  private static let storageKey = "flutter.starflow.playback.memory.v1"
  private static let recentEntryLimit = 20

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func loadResumePositionMs(itemKey: String) -> Int64 {
    guard let entry = loadPlaybackEntry(itemKey: itemKey) else {
      return 0
    }

    let positionMs = entry.int64Value(for: "positionMs")
    let durationMs = entry.int64Value(for: "durationMs")
    let progress = entry.doubleValue(for: "progress")
    let completed = entry.boolValue(for: "completed")

    if completed || positionMs < 5_000 {
      return 0
    }
    if durationMs > 0, durationMs - positionMs <= 12_000 {
      return 0
    }
    if progress >= 0.985 {
      return 0
    }
    return positionMs
  }

  func savePlaybackEntry(
    targetJson: String,
    itemKey: String,
    seriesKey: String,
    positionMs: Int64,
    durationMs: Int64,
    updatedAt: String
  ) {
    guard !itemKey.isEmpty else {
      return
    }

    let clampedDuration = max(durationMs, 0)
    let safePosition = clampedDuration > 0
      ? min(max(positionMs, 0), clampedDuration)
      : max(positionMs, 0)
    let progress = clampedDuration <= 0
      ? 0.0
      : min(max(Double(safePosition) / Double(clampedDuration), 0.0), 1.0)
    let completed = isCompleted(positionMs: safePosition, durationMs: clampedDuration, progress: progress)

    var snapshot = loadPlaybackSnapshot()
    var items = snapshot["items"] as? [String: Any] ?? [:]
    var series = snapshot["series"] as? [String: Any] ?? [:]
    let skipPreferences = snapshot["skipPreferences"] as? [String: Any] ?? [:]

    let targetObject = decodeTargetJson(targetJson)
    let itemType =
      (targetObject["itemType"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    let seriesTitle =
      (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed
      ?? (itemType == "series" ? ((targetObject["title"] as? String)?.nonEmptyTrimmed ?? "") : "")

    let entry: [String: Any] = [
      "key": itemKey,
      "target": targetObject,
      "updatedAt": updatedAt,
      "seriesKey": seriesKey,
      "seriesTitle": seriesTitle,
      "positionMs": NSNumber(value: safePosition),
      "durationMs": NSNumber(value: clampedDuration),
      "progress": NSNumber(value: progress),
      "completed": completed,
    ]

    items[itemKey] = entry
    pruneRecentItems(items: &items)
    if !seriesKey.isEmpty {
      series[seriesKey] = entry
    }

    snapshot["items"] = items
    snapshot["series"] = series
    snapshot["skipPreferences"] = skipPreferences
    savePlaybackSnapshot(snapshot)
  }

  private func loadPlaybackEntry(itemKey: String) -> [String: Any]? {
    guard !itemKey.isEmpty else {
      return nil
    }
    let snapshot = loadPlaybackSnapshot()
    let items = snapshot["items"] as? [String: Any] ?? [:]
    return items[itemKey] as? [String: Any]
  }

  private func loadPlaybackSnapshot() -> [String: Any] {
    guard let raw = userDefaults.string(forKey: Self.storageKey),
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }

  private func savePlaybackSnapshot(_ snapshot: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(snapshot),
      let data = try? JSONSerialization.data(withJSONObject: snapshot),
      let raw = String(data: data, encoding: .utf8)
    else {
      return
    }
    userDefaults.set(raw, forKey: Self.storageKey)
  }

  func decodeTargetJson(_ raw: String) -> [String: Any] {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }

  private func pruneRecentItems(items: inout [String: Any]) {
    guard items.count > Self.recentEntryLimit else {
      return
    }

    let sortedKeys = items
      .compactMap { key, value -> (String, String)? in
        guard let entry = value as? [String: Any] else {
          return nil
        }
        return (key, entry["updatedAt"] as? String ?? "")
      }
      .sorted { left, right in
        left.1 > right.1
      }

    for entry in sortedKeys.dropFirst(Self.recentEntryLimit) {
      items.removeValue(forKey: entry.0)
    }
  }

  private func isCompleted(positionMs: Int64, durationMs: Int64, progress: Double) -> Bool {
    if durationMs <= 0 {
      return progress >= 0.995
    }
    let remaining = durationMs - positionMs
    return progress >= 0.985 || remaining <= 8_000
  }
}

private extension Dictionary where Key == String, Value == Any {
  func intValue(for key: String) -> Int {
    if let value = self[key] as? NSNumber {
      return value.intValue
    }
    if let value = self[key] as? String {
      return Int(value) ?? 0
    }
    return 0
  }

  func int64Value(for key: String) -> Int64 {
    if let value = self[key] as? NSNumber {
      return value.int64Value
    }
    if let value = self[key] as? String {
      return Int64(value) ?? 0
    }
    return 0
  }

  func doubleValue(for key: String) -> Double {
    if let value = self[key] as? NSNumber {
      return value.doubleValue
    }
    if let value = self[key] as? String {
      return Double(value) ?? 0
    }
    return 0
  }

  func boolValue(for key: String) -> Bool {
    if let value = self[key] as? Bool {
      return value
    }
    if let value = self[key] as? NSNumber {
      return value.boolValue
    }
    if let value = self[key] as? String {
      return NSString(string: value).boolValue
    }
    return false
  }
}

private extension String {
  var nonEmptyTrimmed: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension CMTime {
  var milliseconds: Int64 {
    guard isValid, !isIndefinite else {
      return 0
    }

    let seconds = CMTimeGetSeconds(self)
    guard seconds.isFinite else {
      return 0
    }
    return Int64((seconds * 1000.0).rounded())
  }
}

private extension Int64 {
  var clampedToNonNegative: Int64 {
    return Swift.max(self, 0)
  }
}
