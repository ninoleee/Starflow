import AVFoundation
import AVKit
import MediaPlayer
import UIKit
import Flutter

final class NativePlaybackViewController: AVPlayerViewController {
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
  private var appObservers: [NSObjectProtocol] = []
  private var lastSavedPositionMs: Int64 = -1
  private var remoteCommandsInstalled = false
  private var interruptionWasPlaying = false
  private var backgroundDisabledVideoTracks: [AVPlayerItemTrack] = []
  private var appIsInBackground = false
  private var subtitleSessionPreference: NativeSubtitleSessionPreference?
  private var automaticallyAppliedSubtitlePreference: NativeSubtitleSessionPreference?

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
    captureCurrentSubtitleSessionPreference()
    persistPlaybackProgress(force: true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || presentingViewController == nil {
      teardownPlayback()
      resolverChannel?.invokeMethod("closeNativeFntvSession", arguments: ["resolverSessionId": resolverSessionId])
    }
  }

  private func configurePlayer() {
    captureCurrentSubtitleSessionPreference()
    teardownPlayback()
    let generation = playbackGeneration
    playbackStore.preparePlayback(itemKey: request.playbackItemKey, seriesKey: request.seriesKey) {
      [weak self] position, subtitle in
      guard let self, self.playbackGeneration == generation else { return }
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
      self.cancelAutomaticPlaybackWork()
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
    if !automatic { cancelAutomaticPlaybackWork() }
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
      guard let self else {
        if !targetJson.isEmpty {
          resolverChannel.invokeMethod("releaseNativeFntvPlayback", arguments: [
            "resolverSessionId": sessionId, "playbackTargetJson": targetJson,
          ])
        }
        return
      }
      guard self.episodeIntent.finish(generation) else {
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
        ]), let nextRequest = entry.request
      else {
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
    teardownPlayback()
    episodeQueue = queue
    request = nextRequest
    title = request.title
    configurePlayer()
    releaseResolvedPlayback(previous)
    updateNowPlayingInfo()
  }

  private func cancelAutomaticPlaybackWork() {
    episodeIntent.cancelAutomatic()
    if !episodeIntent.pending {
      episodeResolutionTimeout?.cancel()
      episodeResolutionTimeout = nil
    }
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
      DispatchQueue.main.async {
        guard let self, let player = self.player, player.currentItem === item else { return }
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
      if self?.advanceToAdjacentEpisode(forward: true, automatic: true) == true {
        return
      }
      self?.persistPlaybackProgress(force: true)
      self?.updateNowPlayingInfo()
    }
  }

  private func teardownPlayback() {
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
    (player as? NativePlaybackIntentPlayer)?.onUserCommand = nil
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
