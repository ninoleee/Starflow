import Flutter
import AVFoundation
import AVKit
import ObjectiveC.runtime
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var didInstallTouchRateCorrectionWorkaround = false
  private var platformChannel: FlutterMethodChannel?
  private let nativePlaybackStore = NativePlaybackMemoryStore()

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
        self?.launchNativePlaybackContainer(
          rawUrl: rawUrl,
          title: title,
          headersJson: headersJson,
          playbackTargetJson: playbackTargetJson,
          playbackItemKey: playbackItemKey,
          seriesKey: seriesKey,
          result: result
        )
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

  private func launchNativePlaybackContainer(
    rawUrl: String,
    title: String,
    headersJson: String,
    playbackTargetJson: String,
    playbackItemKey: String,
    seriesKey: String,
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
        playbackStore: self.nativePlaybackStore
      )
      controller.modalPresentationStyle = .fullScreen
      presenter.present(controller, animated: true) {
        result(true)
      }
    }
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

private struct NativePlaybackRequest {
  let url: URL
  let title: String
  let headers: [String: String]
  let playbackTargetJson: String
  let playbackItemKey: String
  let seriesKey: String
}

private final class NativePlaybackViewController: AVPlayerViewController {
  private static let persistThresholdMs: Int64 = 4_000
  private static let subtitleSearchChannelName = "starflow/subtitle_search"

  private let playbackStore: NativePlaybackMemoryStore
  private let isoFormatter = ISO8601DateFormatter()
  private let request: NativePlaybackRequest
  private let onlineSubtitleButton = UIButton(type: .system)
  private var subtitleSearchEngine: FlutterEngine?
  private var subtitleSearchChannel: FlutterMethodChannel?
  private var subtitleSearchController: FlutterViewController?
  private var timeObserverToken: Any?
  private var endObserver: NSObjectProtocol?
  private var appObservers: [NSObjectProtocol] = []
  private var lastSavedPositionMs: Int64 = -1

  init(request: NativePlaybackRequest, playbackStore: NativePlaybackMemoryStore) {
    self.request = request
    self.playbackStore = playbackStore
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    cleanupSubtitleSearchSession()
    teardownPlayback()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    showsPlaybackControls = true
    allowsPictureInPicturePlayback = true
    updatesNowPlayingInfoCenter = true
    title = request.title
    configureOverlayButtons()
    configurePlayer()
    registerAppLifecycleObservers()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    persistPlaybackProgress(force: true)
  }

  private func configurePlayer() {
    teardownPlayback()

    let resumePositionMs = playbackStore.loadResumePositionMs(itemKey: request.playbackItemKey)
    let assetOptions: [String: Any]? = request.headers.isEmpty
      ? nil
      : ["AVURLAssetHTTPHeaderFieldsKey": request.headers]
    let asset = AVURLAsset(url: request.url, options: assetOptions)
    let item = AVPlayerItem(asset: asset)

    if !request.title.isEmpty {
      let metadataItem = AVMutableMetadataItem()
      metadataItem.identifier = .commonIdentifierTitle
      metadataItem.value = request.title as NSString
      metadataItem.extendedLanguageTag = "und"
      item.externalMetadata = [metadataItem]
    }

    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    self.player = player

    installEndObserver(for: item)
    installTimeObserver(for: player)

    if resumePositionMs > 5_000 {
      let seekTime = CMTime(value: CMTimeValue(resumePositionMs), timescale: CMTimeScale(1000))
      player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        player.play()
      }
    } else {
      player.play()
    }
  }

  private func configureOverlayButtons() {
    guard let overlayView = contentOverlayView else {
      return
    }

    onlineSubtitleButton.removeFromSuperview()
    onlineSubtitleButton.translatesAutoresizingMaskIntoConstraints = false
    onlineSubtitleButton.tintColor = .white
    onlineSubtitleButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    onlineSubtitleButton.layer.cornerRadius = 18
    onlineSubtitleButton.layer.cornerCurve = .continuous
    onlineSubtitleButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    onlineSubtitleButton.setTitle(" 查字幕", for: .normal)
    if #available(iOS 13.0, *) {
      onlineSubtitleButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
    }
    onlineSubtitleButton.addTarget(self, action: #selector(openOnlineSubtitleSearch), for: .touchUpInside)
    overlayView.addSubview(onlineSubtitleButton)

    NSLayoutConstraint.activate([
      onlineSubtitleButton.trailingAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      onlineSubtitleButton.topAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.topAnchor, constant: 16),
      onlineSubtitleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
  }

  @objc
  private func openOnlineSubtitleSearch() {
    let query = buildSubtitleSearchQuery()
    guard !query.isEmpty else {
      return
    }

    if subtitleSearchController != nil {
      return
    }

    let initialRoute = buildSubtitleSearchRoute(query: query)
    let engine = FlutterEngine(name: "subtitle-search-\(UUID().uuidString)")
    guard engine.run(withEntrypoint: nil, initialRoute: initialRoute) else {
      presentSubtitleSearchNotice(
        title: "打开字幕搜索失败",
        message: "暂时无法启动应用内字幕搜索。"
      )
      return
    }
    GeneratedPluginRegistrant.register(with: engine)

    let channel = FlutterMethodChannel(
      name: Self.subtitleSearchChannelName,
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleSubtitleSearchMethodCall(call, result: result)
    }

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.modalPresentationStyle = .fullScreen

    subtitleSearchEngine = engine
    subtitleSearchChannel = channel
    subtitleSearchController = controller

    present(controller, animated: true)
  }

  private func buildSubtitleSearchQuery() -> String {
    let targetObject = playbackStore.decodeTargetJson(request.playbackTargetJson)
    let seriesTitle = (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed ?? ""
    let title = (targetObject["title"] as? String)?.nonEmptyTrimmed ?? ""
    let itemType =
      ((targetObject["itemType"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let seasonNumber = targetObject.intValue(for: "seasonNumber")
    let episodeNumber = targetObject.intValue(for: "episodeNumber")
    let year = targetObject.intValue(for: "year")

    var parts: [String] = []
    let baseTitle = !seriesTitle.isEmpty ? seriesTitle : title
    if !baseTitle.isEmpty {
      parts.append(baseTitle)
    }
    if seasonNumber > 0, episodeNumber > 0 {
      parts.append(
        "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
      )
    }
    if itemType != "episode", year > 0 {
      parts.append("\(year)")
    }
    return parts.joined(separator: " ")
  }

  private func buildSubtitleSearchRoute(query: String) -> String {
    var components = URLComponents()
    components.path = "/subtitle-search"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "title", value: buildSubtitleSearchTitle()),
      URLQueryItem(name: "mode", value: "downloadOnly"),
      URLQueryItem(name: "standalone", value: "1"),
    ]
    return components.string ?? "/subtitle-search"
  }

  private func buildSubtitleSearchTitle() -> String {
    let targetObject = playbackStore.decodeTargetJson(request.playbackTargetJson)
    let seriesTitle = (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed ?? ""
    let title = (targetObject["title"] as? String)?.nonEmptyTrimmed ?? ""
    return !seriesTitle.isEmpty ? seriesTitle : title
  }

  private func handleSubtitleSearchMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "finishSubtitleSearch":
      let arguments = call.arguments as? [String: Any] ?? [:]
      let cachedPath =
        (arguments["cachedPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let subtitleFilePath =
        (arguments["subtitleFilePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
      let displayName =
        (arguments["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      dismissSubtitleSearch {
        let resolvedName = displayName.isEmpty
          ? URL(fileURLWithPath: subtitleFilePath.isEmpty ? cachedPath : subtitleFilePath)
            .lastPathComponent
          : displayName
        self.presentSubtitleSearchNotice(
          title: "字幕已下载",
          message: resolvedName.isEmpty
            ? "字幕已下载到本地缓存。当前 iOS 原生播放器暂未自动加载外挂字幕。"
            : "已缓存字幕：\(resolvedName)\n当前 iOS 原生播放器暂未自动加载外挂字幕。"
        )
      }
      result(true)
    case "cancelSubtitleSearch":
      dismissSubtitleSearch()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func dismissSubtitleSearch(completion: (() -> Void)? = nil) {
    let controller = subtitleSearchController
    cleanupSubtitleSearchSession()
    if let controller {
      controller.dismiss(animated: true) {
        completion?()
      }
    } else {
      completion?()
    }
  }

  private func cleanupSubtitleSearchSession() {
    subtitleSearchChannel?.setMethodCallHandler(nil)
    subtitleSearchChannel = nil
    subtitleSearchController = nil
    subtitleSearchEngine = nil
  }

  private func presentSubtitleSearchNotice(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func registerAppLifecycleObservers() {
    let center = NotificationCenter.default
    appObservers.append(
      center.addObserver(
        forName: UIApplication.willResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.persistPlaybackProgress(force: true)
      }
    )
    appObservers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.persistPlaybackProgress(force: true)
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
  }

  private func installTimeObserver(for player: AVPlayer) {
    let interval = CMTime(seconds: 2, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] _ in
      self?.persistPlaybackProgress()
    }
  }

  private func installEndObserver(for item: AVPlayerItem) {
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      self?.persistPlaybackProgress(force: true)
    }
  }

  private func teardownPlayback() {
    if !appObservers.isEmpty || player != nil {
      persistPlaybackProgress(force: true)
    }

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

    player?.pause()
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
    return max(self, 0)
  }
}
