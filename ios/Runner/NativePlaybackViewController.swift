import AVFoundation
import AVKit
import MediaPlayer
import UIKit
import Flutter
import UniformTypeIdentifiers

final class NativePlaybackViewController: AVPlayerViewController,
  AVPlayerViewControllerDelegate,
  UIDocumentPickerDelegate
{
  private static let persistThresholdMs: Int64 = 10_000
  private static let playbackStartupTimeoutSeconds: TimeInterval = 30

  private let playbackStore: NativePlaybackMemoryStore
  private let backgroundPlaybackEnabled: Bool
  private let subtitlePreference: String
  private let defaultSubtitle: String
  private let resolverSessionId: String
  private let resolverChannel: FlutterMethodChannel?
  private let episodeIntent = NativePlaybackEpisodeIntent()
  private var playbackGeneration = 0
  private var playbackSessionClosed = false
  private var cacheGeneration = 0
  private var cacheTransportURL: String?
  private var cachePlaybackActive: Bool?
  private var cacheMemoryReadiness = NativePlaybackMemoryReadiness()
  private var cacheMetricsTimer: Timer?
  private var cacheMetricsVisible = false
  private var cacheMetricsRequest: Int?
  private let cacheMetricsLabel = UILabel()
  private var showDiskCache = false
  private var episodeResolutionTimeout: DispatchWorkItem?
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
  private var playbackBufferEmptyObservation: NSKeyValueObservation?
  private var appObservers: [NSObjectProtocol] = []
  private var lastSavedPositionMs: Int64 = -1
  private var remoteCommandsInstalled = false
  private var interruptionWasPlaying = false
  private var backgroundDisabledVideoTracks: [AVPlayerItemTrack] = []
  private var appIsInBackground = false
  private var subtitleSessionPreference: NativeSubtitleSessionPreference?
  private var automaticallyAppliedSubtitlePreference: NativeSubtitleSessionPreference?
  private var externalSubtitleOverlay: NativeExternalSubtitleOverlay?
  private(set) var externalSubtitleTrack: NativeExternalSubtitleTrack?
  private var externalSubtitleTimeObserverToken: Any?
  private var externalSubtitleDownloadTask: URLSessionDataTask?
  private var externalSubtitleDownloader: NativeExternalSubtitleDownloader?
  private var externalSubtitleOperationId = 0
  private let externalSubtitleWorker = DispatchQueue(label: "starflow.subtitle.parse", qos: .userInitiated)
  private weak var externalSubtitlePicker: UIDocumentPickerViewController?
  private var externalSubtitlePickerGeneration = 0
  private var subtitleSearchEngine: FlutterEngine?
  private var subtitleSearchChannel: FlutterMethodChannel?
  private weak var subtitleSearchController: FlutterViewController?
  private var externalSubtitleIsInPictureInPicture = false

  init(
    request: NativePlaybackRequest,
    episodeQueue: NativeEpisodeQueue?,
    backgroundPlaybackEnabled: Bool,
    subtitlePreference: String,
    defaultSubtitle: String,
    playbackStore: NativePlaybackMemoryStore,
    resolverSessionId: String = "",
    resolverChannel: FlutterMethodChannel? = nil
  ) {
    self.request = request
    self.episodeQueue = episodeQueue
    self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
    self.subtitlePreference = subtitlePreference
    self.defaultSubtitle = defaultSubtitle
    self.playbackStore = playbackStore
    self.resolverSessionId = resolverSessionId
    self.resolverChannel = resolverChannel
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit { closePlaybackSession() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    showsPlaybackControls = true
    allowsPictureInPicturePlayback = true
    delegate = self
    updatesNowPlayingInfoCenter = false
    title = request.title
    cleanupCustomOverlayIfNeeded()
    installExternalSubtitleControls()
    installCacheMetricsLabel()
    configurePlayer()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    cacheMetricsVisible = true
    startCacheMetrics()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    cacheMetricsVisible = false
    stopCacheMetrics()
    captureCurrentSubtitleSessionPreference()
    persistPlaybackProgress(force: true)
    if isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true {
      playbackGeneration += 1
      cancelPendingPlaybackWork()
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || isMovingFromParent || presentingViewController == nil {
      closePlaybackSession()
    }
  }

  override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
    if presentedViewController == nil {
      closePlaybackSession()
    }
    super.dismiss(animated: flag, completion: completion)
  }

  private func closePlaybackSession() {
    guard !playbackSessionClosed else { return }
    endCacheTransport()
    playbackSessionClosed = true
    resolverChannel?.invokeMethod("closeNativePlaybackTransports", arguments: ["resolverSessionId": resolverSessionId])
    cancelExternalSubtitleOperation(notifyResolver: true)
    cleanupExternalSubtitleFiles()
    teardownPlayback()
    resolverChannel?.invokeMethod("closeNativeFntvSession", arguments: ["resolverSessionId": resolverSessionId])
  }

  private func configurePlayer() {
    guard !playbackSessionClosed else { return }
    captureCurrentSubtitleSessionPreference()
    teardownPlayback()
    let generation = playbackGeneration
    playbackStore.preparePlayback(itemKey: request.playbackItemKey, seriesKey: request.seriesKey) {
      [weak self] position, subtitle in
      guard let self, !self.playbackSessionClosed, self.playbackGeneration == generation else { return }
      self.configurePreparedPlayer(resumePositionMs: self.request.allowsResume ? position : 0,
        subtitle: subtitle)
    }
  }

  private func configurePreparedPlayer(resumePositionMs: Int64,
    subtitle: NativeSubtitleSessionPreference?) {
    subtitleSessionPreference = subtitle
    automaticallyAppliedSubtitlePreference = nil
    configureAudioSession(enabled: true)

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

    let player = NativePlaybackIntentPlayer(playerItem: item)
    player.onUserCommand = { [weak self, weak player] in
      guard let self, let player, self.player === player else { return }
      self.cancelPendingPlaybackWork()
    }
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
    cacheTransportURL = request.url.absoluteString
    cachePlaybackActive = nil
    invalidateCacheMemoryReadiness()
    setCachePlaybackActive(true)
    player.onPlaybackActive = { [weak self, weak player] active in
      guard let self, let player, self.player === player else { return }
      self.setCachePlaybackActive(active)
    }
    player.onSeek = { [weak self, weak player] in
      guard let self, let player, self.player === player else { return }
      self.cancelCacheReadAhead()
    }
    startCacheMetrics()
    updateExternalSubtitleOverlay()
    let target = playbackStore.decodeTargetJson(request.playbackTargetJson)
    if let path = target["externalSubtitleFilePath"] as? String, !path.isEmpty {
      applyExternalSubtitlePath(path, displayName: target["externalSubtitleDisplayName"] as? String ?? "")
    }
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
        self.playbackStartupTimeoutWorkItem?.cancel()
        self.playbackStartupTimeoutWorkItem = nil
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
          self.externalSubtitleTrack == nil,
          let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else {
          return
        }
        if let sessionPreference = self.subtitleSessionPreference {
          switch sessionPreference {
          case .off:
            item.select(nil, in: group)
            self.automaticallyAppliedSubtitlePreference = .off
            return
          case .single(let fingerprint):
            if let restored = self.matchSubtitleOption(
              in: group.options,
              fingerprint: fingerprint
            ) {
              item.select(restored, in: group)
              self.automaticallyAppliedSubtitlePreference = .single(self.subtitleFingerprint(for: restored))
              return
            }
          }
        }

        if self.subtitlePreference == "off" {
          item.select(nil, in: group)
          self.automaticallyAppliedSubtitlePreference = .off
          return
        }

        let configuredOption = self.defaultSubtitleLanguages.lazy.compactMap { language in
          group.options.first { option in
            self.subtitleOption(option, matches: language)
          }
        }.first
        let systemOption = Locale.preferredLanguages.prefix(1).lazy.compactMap { language in
          group.options.first { option in
            self.subtitleOption(option, matches: language)
          }
        }.first
        let forcedOption = group.options.first { option in
          option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            || self.isForcedSubtitleLabel(option.displayName)
        }
        let selected = configuredOption ?? systemOption ?? forcedOption ?? group.defaultOption
        item.select(selected, in: group)
        self.automaticallyAppliedSubtitlePreference = selected.map {
          .single(self.subtitleFingerprint(for: $0))
        } ?? .off
      }
    }
  }

  private func captureCurrentSubtitleSessionPreference() {
    guard externalSubtitleTrack == nil else { return }
    guard let item = player?.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else {
      return
    }
    let selectedPreference = item.currentMediaSelection
      .selectedMediaOption(in: group)
      .map { NativeSubtitleSessionPreference.single(subtitleFingerprint(for: $0)) }
      ?? .off
    if selectedPreference == automaticallyAppliedSubtitlePreference {
      return
    }
    subtitleSessionPreference = selectedPreference
    playbackStore.saveSubtitlePreference(
      selectedPreference,
      seriesKey: request.seriesKey
    )
  }

  private func subtitleFingerprint(
    for option: AVMediaSelectionOption
  ) -> NativeSubtitleTrackFingerprint {
    return NativeSubtitleTrackFingerprint(
      label: option.displayName,
      language: option.locale?.identifier ?? "",
      isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
        || isForcedSubtitleLabel(option.displayName)
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
    return NativeSubtitleLanguagePolicy.matches(
      language: option.locale?.identifier ?? "", label: option.displayName, preference: rawPreference)
  }

  private var defaultSubtitleLanguages: [String] {
    switch defaultSubtitle {
    case "simplifiedChinese": return ["zh-cn"]
    case "traditionalChinese": return ["zh-tw"]
    case "english": return ["en"]
    case "japanese": return ["ja"]
    case "korean": return ["ko"]
    default: return []
    }
  }

  private func canonicalSubtitleLanguage(_ raw: String) -> String {
    return NativeSubtitleLanguagePolicy.canonical(raw)
  }

  private func isForcedSubtitleLabel(_ label: String) -> Bool {
    let normalized = normalizedSubtitleLabel(label)
    return [
      "forced", "force", "signs", "强制", "強制", "强迫",
      "仅外语", "僅外語", "外语对白", "外語對白",
    ].contains { NativeSubtitleLanguagePolicy.contains(normalized, token: $0) }
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

  private func installCacheMetricsLabel() {
    guard let overlay = contentOverlayView else { return }
    cacheMetricsLabel.text = "不可用"
    cacheMetricsLabel.textColor = .white
    cacheMetricsLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    cacheMetricsLabel.shadowColor = .black
    cacheMetricsLabel.shadowOffset = CGSize(width: 0, height: 1)
    cacheMetricsLabel.numberOfLines = 1
    cacheMetricsLabel.lineBreakMode = .byTruncatingTail
    cacheMetricsLabel.textAlignment = .right
    cacheMetricsLabel.adjustsFontSizeToFitWidth = false
    cacheMetricsLabel.accessibilityIdentifier = "starflow-native-cache-metrics"
    cacheMetricsLabel.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(cacheMetricsLabel)
    NSLayoutConstraint.activate([
      cacheMetricsLabel.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -72),
      cacheMetricsLabel.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 16),
      cacheMetricsLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
      cacheMetricsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 64),
      cacheMetricsLabel.heightAnchor.constraint(equalToConstant: 36),
    ])
  }

  private func cacheArguments(invalidateMetrics: Bool = true) -> [String: Any]? {
    guard !playbackSessionClosed, !resolverSessionId.isEmpty,
      let url = cacheTransportURL else { return nil }
    cacheGeneration += 1
    if invalidateMetrics { cacheMetricsRequest = nil }
    return ["resolverSessionId": resolverSessionId, "currentURL": url, "generation": cacheGeneration]
  }

  private func setCachePlaybackActive(_ active: Bool) {
    if !active { invalidateCacheMemoryReadiness() }
    guard cachePlaybackActive != active, var args = cacheArguments() else { return }
    cachePlaybackActive = active
    args["active"] = active
    resolverChannel?.invokeMethod("setNativePlaybackActive", arguments: args)
  }

  private func cancelCacheReadAhead() {
    invalidateCacheMemoryReadiness()
    guard let args = cacheArguments() else { return }
    resolverChannel?.invokeMethod("cancelNativePlaybackReadAhead", arguments: args)
  }

  private func reportCacheMemoryReady(_ ready: Bool) {
    guard var args = cacheArguments(invalidateMetrics: false) else { return }
    args["memoryReady"] = ready
    // Main owns the four-second lease; renew even when controls are hidden.
    resolverChannel?.invokeMethod("setNativePlaybackBufferState", arguments: args)
  }

  private func invalidateCacheMemoryReadiness() {
    cacheMemoryReadiness.invalidate()
    reportCacheMemoryReady(false)
  }

  private func sampleCacheMemoryReadiness(for player: AVPlayer) {
    guard let item = player.currentItem else {
      invalidateCacheMemoryReadiness()
      return
    }
    let position = player.currentTime().seconds
    // Only the loaded range containing the playhead supplies forward evidence;
    // disconnected ranges and unknown/live durations are not memory capacity.
    let bufferedAhead = item.loadedTimeRanges.compactMap { value -> Double? in
      let range = value.timeRangeValue
      let start = range.start.seconds
      let end = CMTimeRangeGetEnd(range).seconds
      guard start.isFinite, end.isFinite, start <= position, end > position else { return nil }
      return end - position
    }.max()
    let ready = cacheMemoryReadiness.sample(position: position, bufferedAhead: bufferedAhead,
      itemReady: item.status == .readyToPlay,
      playing: player.timeControlStatus == .playing && player.rate > 0 && cachePlaybackActive == true,
      startupPending: startupGate != nil, bufferEmpty: item.isPlaybackBufferEmpty,
      bufferFull: item.isPlaybackBufferFull, likelyToKeepUp: item.isPlaybackLikelyToKeepUp)
    reportCacheMemoryReady(ready)
  }

  private func endCacheTransport() {
    stopCacheMetrics()
    setCachePlaybackActive(false)
    cancelCacheReadAhead()
    cacheTransportURL = nil
    cachePlaybackActive = nil
    showDiskCache = false
    cacheMetricsLabel.text = "不可用"
  }

  private func startCacheMetrics() {
    guard cacheMetricsVisible, !appIsInBackground, !externalSubtitleIsInPictureInPicture, !playbackSessionClosed,
      cacheTransportURL != nil, cacheMetricsTimer == nil else { return }
    cacheMetricsLabel.isHidden = false
    sampleCacheMetrics()
    cacheMetricsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.sampleCacheMetrics()
    }
  }

  private func stopCacheMetrics() {
    cacheMetricsTimer?.invalidate()
    cacheMetricsTimer = nil
    cacheGeneration += 1
    cacheMetricsRequest = nil
    cacheMetricsLabel.isHidden = true
  }

  private func sampleCacheMetrics() {
    guard cacheMetricsVisible, !appIsInBackground, !cacheMetricsLabel.isHidden,
      cacheMetricsRequest == nil, let resolverChannel,
      let args = cacheArguments(), let url = cacheTransportURL else { return }
    let generation = cacheGeneration
    cacheMetricsRequest = generation
    resolverChannel.invokeMethod("nativePlaybackCacheSnapshot", arguments: args) { [weak self] result in
      guard let self else { return }
      guard self.cacheMetricsRequest == generation else { return }
      self.cacheMetricsRequest = nil
      guard !self.playbackSessionClosed, self.cacheMetricsVisible, !self.appIsInBackground,
        self.cacheTransportURL == url else { return }
      guard let value = result as? [String: Any], value["ok"] as? Bool == true,
        value["resolverSessionId"] as? String == self.resolverSessionId,
        value["currentURL"] as? String == url,
        (value["generation"] as? NSNumber)?.intValue == generation else {
        self.cacheMetricsLabel.text = self.showDiskCache ? "不可用 | --" : "不可用"
        return
      }
      let bytes = (value["storedBytes"] as? NSNumber)?.int64Value
      self.showDiskCache = value["showDiskCache"] as? Bool == true
      let disk = bytes.flatMap { $0 >= 0 ? ByteCountFormatter.string(fromByteCount: $0, countStyle: .binary) : nil } ?? "--"
      self.cacheMetricsLabel.text = self.showDiskCache ? "不可用 | \(disk)" : "不可用"
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, self.cacheMetricsRequest == generation else { return }
      self.cacheMetricsRequest = nil
      self.cacheGeneration += 1
      self.cacheMetricsLabel.text = self.showDiskCache ? "不可用 | --" : "不可用"
    }
  }

  private func installExternalSubtitleControls() {
    guard let overlay = contentOverlayView else { return }
    let subtitleButton = UIButton(type: .system)
    subtitleButton.accessibilityIdentifier = "starflow-native-subtitle-button"
    subtitleButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
    subtitleButton.accessibilityLabel = "字幕"
    subtitleButton.setTitleColor(.white, for: .normal)
    subtitleButton.backgroundColor = UIColor.black.withAlphaComponent(0.58)
    subtitleButton.layer.cornerRadius = 5
    subtitleButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    subtitleButton.translatesAutoresizingMaskIntoConstraints = false
    subtitleButton.addTarget(self, action: #selector(openExternalSubtitleMenu), for: .touchUpInside)
    view.addSubview(subtitleButton)
    NSLayoutConstraint.activate([
      subtitleButton.widthAnchor.constraint(equalToConstant: 44),
      subtitleButton.heightAnchor.constraint(equalToConstant: 44),
      subtitleButton.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 16),
      subtitleButton.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
    ])

    let subtitleOverlay = NativeExternalSubtitleOverlay(frame: .zero)
    subtitleOverlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(subtitleOverlay)
    NSLayoutConstraint.activate([
      subtitleOverlay.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
      subtitleOverlay.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
      subtitleOverlay.topAnchor.constraint(equalTo: overlay.topAnchor),
      subtitleOverlay.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
    ])
    self.externalSubtitleOverlay = subtitleOverlay
    overlay.bringSubviewToFront(subtitleOverlay)
    view.bringSubviewToFront(subtitleButton)
  }

  @objc func openExternalSubtitleMenu() {
    guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
    let alert = UIAlertController(title: "外挂字幕", message: nil, preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "选择本地字幕", style: .default) { [weak self] _ in
      self?.presentExternalSubtitlePicker()
    })
    alert.addAction(UIAlertAction(title: "在线搜索字幕", style: .default) { [weak self] _ in
      self?.requestExternalSubtitleSearch()
    })
    if externalSubtitleTrack != nil {
      alert.addAction(UIAlertAction(title: "关闭外挂字幕", style: .destructive) { [weak self] _ in
        self?.clearExternalSubtitle()
      })
      alert.addAction(UIAlertAction(title: "恢复系统字幕", style: .default) { [weak self] _ in
        guard let self else { return }
        self.clearExternalSubtitle()
        if let item = self.player?.currentItem, let asset = item.asset as? AVURLAsset {
          self.applyAutomaticSubtitleSelection(to: item, asset: asset)
        }
      })
    }
    if externalSubtitleDownloadTask != nil {
      alert.addAction(UIAlertAction(title: "取消下载", style: .destructive) { [weak self] _ in
        self?.cancelExternalSubtitleOperation(notifyResolver: true)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func presentExternalSubtitlePicker() {
    cancelExternalSubtitleOperation(notifyResolver: false)
    externalSubtitlePickerGeneration = externalSubtitleOperationId
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .open)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    externalSubtitlePicker = picker
    present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === externalSubtitlePicker,
      externalSubtitlePickerGeneration == externalSubtitleOperationId,
      !playbackSessionClosed, let url = urls.first else { return }
    externalSubtitlePicker = nil
    applyExternalSubtitleFile(url: url, displayName: url.lastPathComponent)
  }

  private func requestExternalSubtitleSearch() {
    guard !playbackSessionClosed, subtitleSearchEngine == nil else { return }
    cancelExternalSubtitleOperation(notifyResolver: false)
    let generation = playbackGeneration
    let target = playbackStore.decodeTargetJson(request.playbackTargetJson)
    let name = (target["seriesTitle"] as? String)?.nonEmptyTrimmed ?? request.title
    var route = URLComponents()
    route.path = "/subtitle-search"
    route.queryItems = [URLQueryItem(name: "standalone", value: "1"),
      URLQueryItem(name: "mode", value: "downloadAndApply"),
      URLQueryItem(name: "q", value: name), URLQueryItem(name: "title", value: name),
      URLQueryItem(name: "input", value: name)]
    for (key, queryKey) in [("originalTitle", "originalTitle"), ("year", "year"),
      ("imdbId", "imdbId"), ("tmdbId", "tmdbId"),
      ("seasonNumber", "season"), ("episodeNumber", "episode")] {
      if let value = target[key], !(value is NSNull) {
        route.queryItems?.append(URLQueryItem(name: queryKey, value: "\(value)"))
      }
    }
    let engine = FlutterEngine(name: "starflow-subtitles-\(UUID().uuidString)", project: nil,
      allowHeadlessExecution: false)
    guard engine.run(withEntrypoint: nil, initialRoute: route.string) else {
      notifyExternalSubtitleError("无法打开字幕搜索")
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    let channel = FlutterMethodChannel(name: "starflow/subtitle_search", binaryMessenger: engine.binaryMessenger)
    subtitleSearchEngine = engine
    subtitleSearchChannel = channel
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self, !self.playbackSessionClosed,
        self.playbackGeneration == generation else { reply(false); return }
      switch call.method {
      case "finishSubtitleSearch":
        let args = call.arguments as? [String: Any] ?? [:]
        let path = args["subtitleFilePath"] as? String ?? ""
        guard !path.isEmpty else { reply(false); return }
        self.applyExternalSubtitlePath(path, displayName: args["displayName"] as? String ?? "") { [weak self, weak engine] accepted in
          NativeExternalSubtitleParser.discardOnlineDownload(path: path)
          guard let self, let engine, self.subtitleSearchEngine === engine else { return }
          reply(true)
          self.closeExternalSubtitleSearch { [weak self] in
            if !accepted { self?.notifyExternalSubtitleError("此字幕无法挂载，原字幕保持不变。") }
          }
        }
      case "cancelSubtitleSearch":
        reply(true)
        self.closeExternalSubtitleSearch()
      default: reply(FlutterMethodNotImplemented)
      }
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.modalPresentationStyle = .fullScreen
    subtitleSearchController = controller
    present(controller, animated: true)
  }

  private func closeExternalSubtitleSearch(completion: (() -> Void)? = nil) {
    if subtitleSearchEngine != nil { cancelExternalSubtitleOperation(notifyResolver: false) }
    subtitleSearchChannel?.setMethodCallHandler(nil)
    subtitleSearchChannel = nil
    let engine = subtitleSearchEngine
    subtitleSearchEngine = nil
    if let controller = subtitleSearchController {
      controller.dismiss(animated: true) {
        engine?.destroyContext()
        completion?()
      }
    } else {
      engine?.destroyContext()
      completion?()
    }
    subtitleSearchController = nil
  }

  func applyExternalSubtitlePath(_ path: String, displayName: String = "",
    completion: @escaping (Bool) -> Void = { _ in }) {
    let url = URL(fileURLWithPath: path)
    applyExternalSubtitleFile(url: url, displayName: displayName.isEmpty ? url.lastPathComponent : displayName,
      completion: completion)
  }

  func downloadExternalSubtitle(
    urlString: String,
    headers: [String: String] = [:],
    displayName: String = "subtitle.srt"
  ) {
    guard !playbackSessionClosed,
      let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else {
      notifyExternalSubtitleError("字幕下载地址无效")
      return
    }
    cancelExternalSubtitleOperation(notifyResolver: false)
    let operationId = externalSubtitleOperationId
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    for (key, value) in headers where !key.isEmpty { request.setValue(value, forHTTPHeaderField: key) }
    let downloader = NativeExternalSubtitleDownloader { [weak self] result in
      DispatchQueue.main.async {
        guard let self, self.externalSubtitleOperationId == operationId, !self.playbackSessionClosed else { return }
        self.externalSubtitleDownloadTask = nil
        self.externalSubtitleDownloader = nil
        switch result {
        case .success(let data): self.applyExternalSubtitleData(data, fileName: displayName)
        case .failure(let error):
          if !(error is CancellationError) { self.notifyExternalSubtitleError(error.localizedDescription) }
        }
      }
    }
    externalSubtitleDownloader = downloader
    externalSubtitleDownloadTask = downloader.start(request: request)
    resolverChannel?.invokeMethod("nativeExternalSubtitleState", arguments: [
      "resolverSessionId": resolverSessionId, "state": "downloading",
    ])
  }

  private func applyExternalSubtitleFile(url: URL, displayName: String,
    completion: @escaping (Bool) -> Void = { _ in }) {
    guard !playbackSessionClosed, url.isFileURL else { completion(false); return }
    cancelExternalSubtitleOperation(notifyResolver: false)
    let generation = externalSubtitleOperationId
    externalSubtitleWorker.async { [weak self] in
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let result = Result { () throws -> NativeExternalSubtitleTrack in
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data: Data
        if #available(iOS 13.4, *) {
          data = try handle.read(upToCount: NativeExternalSubtitleParser.maxBytes + 1) ?? Data()
        } else {
          data = handle.readData(ofLength: NativeExternalSubtitleParser.maxBytes + 1)
        }
        return try NativeExternalSubtitleParser.parse(data: data, fileName: url.lastPathComponent)
      }
      DispatchQueue.main.async {
        guard let self, !self.playbackSessionClosed,
          self.externalSubtitleOperationId == generation else { completion(false); return }
        completion(self.mountExternalSubtitle(result, displayName: displayName))
      }
    }
  }

  private func applyExternalSubtitleData(_ data: Data, fileName: String) {
    cancelExternalSubtitleOperation(notifyResolver: false)
    let generation = externalSubtitleOperationId
    externalSubtitleWorker.async { [weak self] in
      let result = Result { try NativeExternalSubtitleParser.parse(data: data, fileName: fileName) }
      DispatchQueue.main.async {
        guard let self, !self.playbackSessionClosed,
          self.externalSubtitleOperationId == generation else { return }
        _ = self.mountExternalSubtitle(result, displayName: fileName)
      }
    }
  }

  private func mountExternalSubtitle(_ result: Result<NativeExternalSubtitleTrack, Error>,
    displayName: String) -> Bool {
    switch result {
    case .success(let parsed):
      externalSubtitleTrack = NativeExternalSubtitleTrack(
        format: parsed.format, displayName: displayName, cues: parsed.cues)
      if let item = player?.currentItem,
        let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
        item.select(nil, in: group)
      }
      externalSubtitleOverlay?.setTrack(externalSubtitleTrack)
      externalSubtitleOverlay?.update(time: player?.currentTime().seconds ?? 0)
      resolverChannel?.invokeMethod("nativeExternalSubtitleState", arguments: [
        "resolverSessionId": resolverSessionId, "state": "applied", "displayName": displayName,
      ])
      return true
    case .failure(let error):
      notifyExternalSubtitleError(error.localizedDescription)
      return false
    }
  }

  func clearExternalSubtitle() {
    cancelExternalSubtitleOperation(notifyResolver: false)
    externalSubtitleTrack = nil
    externalSubtitleOverlay?.setTrack(nil)
    resolverChannel?.invokeMethod("nativeExternalSubtitleState", arguments: [
      "resolverSessionId": resolverSessionId, "state": "cleared",
    ])
  }

  func cancelExternalSubtitleOperation(notifyResolver: Bool) {
    externalSubtitleOperationId += 1
    externalSubtitleDownloadTask?.cancel()
    externalSubtitleDownloader?.cancel()
    externalSubtitleDownloadTask = nil
    externalSubtitleDownloader = nil
    if notifyResolver {
      resolverChannel?.invokeMethod("nativeExternalSubtitleState", arguments: [
        "resolverSessionId": resolverSessionId, "state": "cancelled",
      ])
    }
  }

  private func cleanupExternalSubtitleFiles() {
    externalSubtitleTrack = nil
    externalSubtitleOverlay?.setTrack(nil)
  }

  private func updateExternalSubtitleOverlay() {
    externalSubtitleOverlay?.setTrack(externalSubtitleTrack)
  }

  private func notifyExternalSubtitleError(_ message: String) {
    resolverChannel?.invokeMethod("nativeExternalSubtitleState", arguments: [
      "resolverSessionId": resolverSessionId, "state": "error", "message": message,
    ])
    guard !playbackSessionClosed, viewIfLoaded?.window != nil, presentedViewController == nil else { return }
    let alert = UIAlertController(title: "字幕加载失败", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确定", style: .default))
    present(alert, animated: true)
  }

  func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
    stopCacheMetrics()
    externalSubtitleIsInPictureInPicture = true
    externalSubtitleOverlay?.setPictureInPictureHidden(true)
  }

  func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
    externalSubtitleIsInPictureInPicture = false
    startCacheMetrics()
    externalSubtitleOverlay?.setPictureInPictureHidden(false)
    externalSubtitleOverlay?.update(time: player?.currentTime().seconds ?? 0)
  }

  func playerViewController(_ playerViewController: AVPlayerViewController,
    failedToStartPictureInPictureWithError error: Error) {
    externalSubtitleIsInPictureInPicture = false
    startCacheMetrics()
    externalSubtitleOverlay?.setPictureInPictureHidden(false)
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
  private func advanceToAdjacentEpisode(forward: Bool, automatic: Bool = false) -> Bool {
    guard !playbackSessionClosed, !isBeingDismissed else { return false }
    if !automatic { cancelPendingPlaybackWork() }
    guard let generation = episodeIntent.begin(automatic: automatic) else { return false }
    episodeResolutionTimeout?.cancel()
    episodeResolutionTimeout = nil
    let nextQueue = forward ? episodeQueue?.moveToNext() : episodeQueue?.moveToPrevious()
    guard let nextQueue, let nextEntry = nextQueue.currentEntry else {
      _ = episodeIntent.finish(generation)
      return false
    }

    guard let resolverChannel, !resolverSessionId.isEmpty else {
      _ = episodeIntent.finish(generation)
      guard let nextRequest = nextEntry.request else { return false }
      switchEpisode(to: nextRequest, queue: nextQueue)
      return true
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.episodeIntent.finish(generation) else { return }
      self.episodeResolutionTimeout = nil
      self.showEpisodeResolutionFailure()
    }
    episodeResolutionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    let sessionId = resolverSessionId
    resolverChannel.invokeMethod("resolveNativePlaybackEpisode", arguments: [
      "resolverSessionId": resolverSessionId,
      "playbackTargetJson": nextEntry.playbackTargetJson,
    ]) { [weak self] result in
      let value = result as? [String: Any]
      let targetJson = value?["playbackTargetJson"] as? String ?? ""
      let transportUrl = value?["transportUrl"] as? String ?? ""
      func releaseTransport() {
        resolverChannel.invokeMethod("releaseNativePlaybackTransport", arguments: [
          "resolverSessionId": sessionId, "transportUrl": transportUrl,
        ])
      }
      guard let self else {
        releaseTransport()
        if !targetJson.isEmpty {
          resolverChannel.invokeMethod("releaseNativeFntvPlayback", arguments: [
            "resolverSessionId": sessionId, "playbackTargetJson": targetJson,
          ])
        }
        return
      }
      guard self.episodeIntent.finish(generation) else {
        releaseTransport()
        self.releaseResolvedPlayback(targetJson)
        return
      }
      self.episodeResolutionTimeout?.cancel()
      self.episodeResolutionTimeout = nil
      guard value?["ok"] as? Bool == true,
        let data = targetJson.data(using: .utf8),
        let target = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let entry = NativeEpisodeQueueEntry(json: [
          "target": target,
          "playbackItemKey": value?["playbackItemKey"] ?? nextEntry.playbackItemKey,
          "seriesKey": value?["seriesKey"] ?? nextEntry.seriesKey,
          "transportUrl": value?["transportUrl"] ?? target["streamUrl"] ?? "",
          "transportHeaders": value?["transportHeaders"] ?? target["headers"] ?? [:],
        ]), let nextRequest = entry.request
      else {
        releaseTransport()
        self.releaseResolvedPlayback(targetJson)
        self.showEpisodeResolutionFailure()
        return
      }
      self.switchEpisode(to: nextRequest, queue: nextQueue)
    }
    return true
  }

  private func switchEpisode(to nextRequest: NativePlaybackRequest, queue: NativeEpisodeQueue) {
    captureCurrentSubtitleSessionPreference()
    let previous = request.playbackTargetJson
    let previousTransport = request.url.absoluteString
    teardownPlayback()
    episodeQueue = queue
    request = nextRequest
    title = request.title
    configurePlayer()
    releaseResolvedPlayback(previous)
    resolverChannel?.invokeMethod("releaseNativePlaybackTransport", arguments: [
      "resolverSessionId": resolverSessionId, "transportUrl": previousTransport,
    ])
    updateNowPlayingInfo()
  }

  private func cancelPendingPlaybackWork() {
    episodeIntent.cancel()
    episodeResolutionTimeout?.cancel()
    episodeResolutionTimeout = nil
    startupGate?.cancel()
    startupGate = nil
    playbackStartupTimeoutWorkItem?.cancel()
    playbackStartupTimeoutWorkItem = nil
    interruptionWasPlaying = false
  }

  private func releaseResolvedPlayback(_ targetJson: String) {
    guard !targetJson.isEmpty else { return }
    resolverChannel?.invokeMethod("releaseNativeFntvPlayback", arguments: [
      "resolverSessionId": resolverSessionId, "playbackTargetJson": targetJson,
    ])
  }

  private func showEpisodeResolutionFailure() {
    guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
    let alert = UIAlertController(title: "切集失败", message: "未取得播放地址，请稍后重试。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确定", style: .default))
    present(alert, animated: true)
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
        guard let self, self.player === player else { return }
        if player.timeControlStatus != .playing { self.invalidateCacheMemoryReadiness() }
        self.syncAudioSessionForPlaybackState(player)
        self.updateNowPlayingInfo()
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
        self.stopCacheMetrics()
        self.episodeIntent.cancelAutomatic()
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
        self.startCacheMetrics()
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
      let wasPlaying = player?.timeControlStatus != .paused
      if wasPlaying {
        player?.pause()
        configureAudioSession(enabled: false)
        updateNowPlayingInfo()
      }
      interruptionWasPlaying = wasPlaying
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
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self, weak player] time in
      guard let self, let player, self.player === player else { return }
      self.sampleCacheMemoryReadiness(for: player)
      if time.seconds.isFinite && time.seconds > 0 {
        self.markPlaybackFirstFrameReady()
      }
      self.persistPlaybackProgress()
    }
    externalSubtitleTimeObserverToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
      queue: .main
    ) { [weak self, weak player] time in
      guard let self, let player, self.player === player else { return }
      if self.externalSubtitleTrack != nil, let item = player.currentItem,
        let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
        item.currentMediaSelection.selectedMediaOption(in: group) != nil {
        self.clearExternalSubtitle()
      }
      self.externalSubtitleOverlay?.update(time: time.seconds)
      self.externalSubtitleOverlay?.setPictureInPictureHidden(self.externalSubtitleIsInPictureInPicture)
    }
  }

  private func installPlaybackItemStatusObserver(for item: AVPlayerItem) {
    playbackBufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) {
      [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self, self.player?.currentItem === item, item.isPlaybackBufferEmpty else { return }
        self.invalidateCacheMemoryReadiness()
      }
    }
    playbackItemStatusObservation = item.observe(\.status, options: [.new]) {
      [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self, let player = self.player, player.currentItem === item else { return }
        if item.status != .readyToPlay { self.invalidateCacheMemoryReadiness() }
        if item.status == .failed {
          self.showPlaybackFailure(error: item.error)
        } else if item.status == .readyToPlay {
          NativePlaybackBufferingTuning.apply(playerItem: item, player: player,
            context: .init(url: self.request.url, headers: self.request.headers,
              isLiveStream: item.duration.isIndefinite))
        }
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
        self.closePlaybackSession()
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
    ) { [weak self, weak item] _ in
      guard let self, let item, self.player?.currentItem === item else { return }
      self.setCachePlaybackActive(false)
      if self.advanceToAdjacentEpisode(forward: true, automatic: true) {
        return
      }
      self.persistPlaybackProgress(force: true)
      self.updateNowPlayingInfo()
    }
  }

  private func teardownPlayback() {
    endCacheTransport()
    cancelExternalSubtitleOperation(notifyResolver: false)
    closeExternalSubtitleSearch()
    externalSubtitlePicker?.dismiss(animated: false)
    externalSubtitlePicker = nil
    cleanupExternalSubtitleFiles()
    playbackGeneration += 1
    episodeIntent.cancel()
    episodeResolutionTimeout?.cancel()
    episodeResolutionTimeout = nil
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
    playbackBufferEmptyObservation = nil

    if let token = timeObserverToken,
      let currentPlayer = player
    {
      currentPlayer.removeTimeObserver(token)
    }
    timeObserverToken = nil
    if let token = externalSubtitleTimeObserverToken,
      let currentPlayer = player
    {
      currentPlayer.removeTimeObserver(token)
    }
    externalSubtitleTimeObserverToken = nil

    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    endObserver = nil

    for observer in appObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    appObservers.removeAll()

    setBackgroundAudioOnly(false)
    (player as? NativePlaybackIntentPlayer)?.onUserCommand = nil
    (player as? NativePlaybackIntentPlayer)?.onPlaybackActive = nil
    (player as? NativePlaybackIntentPlayer)?.onSeek = nil
    player?.pause()
    player = nil
    lastSavedPositionMs = -1
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

    playbackStore.enqueuePlaybackEntry(
      targetJson: request.playbackTargetJson,
      itemKey: request.playbackItemKey,
      seriesKey: request.seriesKey,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: isoFormatter.string(from: Date()),
      final: force
    )
    let channel = resolverChannel
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    if force {
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Playback progress") {
        if backgroundTask != .invalid {
          UIApplication.shared.endBackgroundTask(backgroundTask)
          backgroundTask = .invalid
        }
      }
    }
    playbackStore.flush {
      if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
      }
      channel?.invokeMethod("nativePlaybackMemoryChanged", arguments: nil)
    }
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
