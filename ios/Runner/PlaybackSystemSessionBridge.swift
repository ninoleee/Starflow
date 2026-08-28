import AVFoundation
import AVKit
import Flutter
import ImageIO
import MediaPlayer
import UIKit

final class PlaybackSystemSessionBridge {
  private weak var channel: FlutterMethodChannel?
  private let topViewControllerProvider: () -> UIViewController?
  private let artworkLoader = StarflowNowPlayingArtworkLoader()
  private var isActive = false
  private var latestIsPlaying = false
  private var interruptionWasPlaying = false
  private var latestNowPlayingArguments: [String: Any] = [:]
  private var observers: [NSObjectProtocol] = []

  init(topViewControllerProvider: @escaping () -> UIViewController?) {
    self.topViewControllerProvider = topViewControllerProvider
  }

  func bind(to channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func unbind() {
    channel?.setMethodCallHandler(nil)
    channel = nil
    setActive(false)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setActive":
      let arguments = call.arguments as? [String: Any]
      let active = arguments?["active"] as? Bool ?? false
      setActive(active)
      result(true)
    case "update":
      let arguments = call.arguments as? [String: Any] ?? [:]
      updateNowPlayingInfo(arguments)
      result(true)
    case "showAirPlayPicker":
      DispatchQueue.main.async {
        result(self.presentAirPlayPicker())
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setActive(_ active: Bool) {
    guard active != isActive else {
      return
    }

    isActive = active
    if active {
      configureAudioSession(enabled: latestIsPlaying)
      installRemoteCommands()
      registerSystemObservers()
      UIApplication.shared.beginReceivingRemoteControlEvents()
    } else {
      unregisterSystemObservers()
      uninstallRemoteCommands()
      artworkLoader.reset()
      latestIsPlaying = false
      interruptionWasPlaying = false
      latestNowPlayingArguments = [:]
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      UIApplication.shared.endReceivingRemoteControlEvents()
      configureAudioSession(enabled: false)
    }
  }

  private func configureAudioSession(enabled: Bool) {
    StarflowAudioSession.configurePlayback(
      enabled: enabled,
      owner: "playback-system-session"
    )
  }

  private func registerSystemObservers() {
    guard observers.isEmpty else {
      return
    }

    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioSessionInterruption(notification)
      }
    )
    observers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioRouteChange(notification)
      }
    )
  }

  private func unregisterSystemObservers() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func installRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    uninstallRemoteCommands()

    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.stopCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.skipForwardCommand.preferredIntervals = [10]
    commandCenter.skipBackwardCommand.preferredIntervals = [10]

    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("play")
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("pause")
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("toggle")
      return .success
    }
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("seekForward")
      return .success
    }
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("seekBackward")
      return .success
    }
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.dispatchRemoteCommand(
        "seekTo",
        positionMs: Int64((event.positionTime * 1000).rounded())
      )
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("previous")
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("next")
      return .success
    }
  }

  private func uninstallRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.stopCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
  }

  private func updateNowPlayingInfo(_ arguments: [String: Any]) {
    guard isActive else {
      return
    }
    latestNowPlayingArguments = arguments
    let title =
      (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let subtitle =
      (arguments["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let positionMs = (arguments["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let durationMs = (arguments["durationMs"] as? NSNumber)?.doubleValue ?? 0
    let playing = arguments["playing"] as? Bool ?? false
    let buffering = arguments["buffering"] as? Bool ?? false
    let speed = (arguments["speed"] as? NSNumber)?.doubleValue ?? 1
    let artworkCandidates = normalizedNowPlayingArtworkCandidates(
      arguments["artworkCandidates"] as? [[String: Any]]
    )
    let hasPrevious = arguments["hasPrevious"] as? Bool ?? false
    let hasNext = arguments["hasNext"] as? Bool ?? false
    let canSeek = arguments["canSeek"] as? Bool ?? true

    latestIsPlaying = playing
    if isActive {
      configureAudioSession(enabled: playing)
    }

    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = title.isEmpty ? "Starflow" : title
    if subtitle.isEmpty {
      info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
      info.removeValue(forKey: MPMediaItemPropertyArtist)
    } else {
      info[MPMediaItemPropertyAlbumTitle] = subtitle
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = durationMs / 1000.0
    } else {
      info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(positionMs, 0.0) / 1000.0
    info[MPNowPlayingInfoPropertyPlaybackRate] =
      playing && !buffering ? max(speed, 0.1) : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    artworkLoader.applyArtwork(
      to: &info,
      candidates: artworkCandidates
    ) { [weak self] in
      guard let self, !self.latestNowPlayingArguments.isEmpty else {
        return
      }
      self.updateNowPlayingInfo(self.latestNowPlayingArguments)
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.skipForwardCommand.isEnabled = canSeek
    commandCenter.skipBackwardCommand.isEnabled = canSeek
    commandCenter.changePlaybackPositionCommand.isEnabled = canSeek
    commandCenter.previousTrackCommand.isEnabled = hasPrevious
    commandCenter.nextTrackCommand.isEnabled = hasNext
  }

  private func dispatchRemoteCommand(_ command: String, positionMs: Int64? = nil) {
    switch command {
    case "play", "interruptionResume":
      latestIsPlaying = true
      configureAudioSession(enabled: true)
    case "pause", "stop", "becomingNoisy", "interruptionPause":
      latestIsPlaying = false
      configureAudioSession(enabled: false)
    case "toggle":
      latestIsPlaying.toggle()
      configureAudioSession(enabled: latestIsPlaying)
    default:
      break
    }
    var payload: [String: Any] = ["command": command]
    if let positionMs {
      payload["positionMs"] = NSNumber(value: positionMs)
    }
    channel?.invokeMethod("onPlaybackRemoteCommand", arguments: payload)
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
    guard let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType) else {
      return
    }

    switch interruptionType {
    case .began:
      interruptionWasPlaying = latestIsPlaying
      if interruptionWasPlaying {
        dispatchRemoteCommand("interruptionPause")
      }
    case .ended:
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      let shouldResume = interruptionWasPlaying && options.contains(.shouldResume)
      interruptionWasPlaying = false
      if shouldResume {
        dispatchRemoteCommand("interruptionResume")
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
      dispatchRemoteCommand("becomingNoisy")
    }
  }

  @discardableResult
  private func presentAirPlayPicker() -> Bool {
    guard let presenter = topViewControllerProvider() else {
      return false
    }

    let routePicker = AVRoutePickerView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    routePicker.prioritizesVideoDevices = true
    routePicker.tintColor = .clear
    routePicker.activeTintColor = .clear
    presenter.view.addSubview(routePicker)

    defer {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        routePicker.removeFromSuperview()
      }
    }

    guard let control = routePicker.subviews.compactMap({ $0 as? UIControl }).first else {
      return false
    }
    control.sendActions(for: .touchUpInside)
    return true
  }
}

struct StarflowNowPlayingArtworkCandidate: Equatable {
  let urlString: String
  let headers: [String: String]
}

final class StarflowNowPlayingArtworkLoader: NSObject, URLSessionDataDelegate {
  private static let maxDownloadBytes = 8 * 1024 * 1024
  private static let maxPixelSize = 1200
  private var candidates: [StarflowNowPlayingArtworkCandidate] = []
  private var artwork: MPMediaItemArtwork?
  private var dataTask: URLSessionDataTask?
  private var activeData = Data()
  private var activeTaskIdentifier: Int?
  private var activeCandidateIndex: Int?
  private var activeRefresh: (() -> Void)?
  private var generation = 0
  private lazy var session = URLSession(
    configuration: .default,
    delegate: self,
    delegateQueue: .main
  )

  func applyArtwork(
    to info: inout [String: Any],
    candidates rawCandidates: [StarflowNowPlayingArtworkCandidate],
    refresh: @escaping () -> Void
  ) {
    let normalizedCandidates = normalizedNowPlayingArtworkCandidates(rawCandidates)
    if normalizedCandidates != candidates {
      startLoading(candidates: normalizedCandidates, refresh: refresh)
    } else if dataTask != nil {
      activeRefresh = refresh
    }

    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    } else {
      info.removeValue(forKey: MPMediaItemPropertyArtwork)
    }
  }

  func reset() {
    dataTask?.cancel()
    dataTask = nil
    activeData.removeAll(keepingCapacity: false)
    activeTaskIdentifier = nil
    activeCandidateIndex = nil
    activeRefresh = nil
    candidates = []
    artwork = nil
    generation += 1
  }

  private func startLoading(
    candidates: [StarflowNowPlayingArtworkCandidate],
    refresh: @escaping () -> Void
  ) {
    dataTask?.cancel()
    dataTask = nil
    self.candidates = candidates
    artwork = nil
    generation += 1
    loadCandidate(at: 0, refresh: refresh, generation: generation)
  }

  private func loadCandidate(
    at index: Int,
    refresh: @escaping () -> Void,
    generation requestGeneration: Int
  ) {
    guard generation == requestGeneration, candidates.indices.contains(index) else {
      activeCandidateIndex = nil
      activeRefresh = nil
      return
    }
    let candidate = candidates[index]
    guard let url = URL(string: candidate.urlString),
      url.scheme != nil
    else {
      loadCandidate(at: index + 1, refresh: refresh, generation: requestGeneration)
      return
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .returnCacheDataElseLoad,
      timeoutInterval: 12
    )
    for (name, value) in candidate.headers where !name.isEmpty && !value.isEmpty {
      request.setValue(value, forHTTPHeaderField: name)
    }

    activeData.removeAll(keepingCapacity: false)
    activeCandidateIndex = index
    activeRefresh = refresh
    let task = session.dataTask(with: request)
    dataTask = task
    activeTaskIdentifier = task.taskIdentifier
    task.resume()
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard dataTask.taskIdentifier == activeTaskIdentifier else {
      completionHandler(.cancel)
      return
    }
    let expectedLength = response.expectedContentLength
    let responseIsTooLarge =
      expectedLength > 0 && expectedLength > Int64(Self.maxDownloadBytes)
    let statusIsValid =
      (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
    guard !responseIsTooLarge, statusIsValid else {
      completionHandler(.cancel)
      return
    }
    activeData.removeAll(keepingCapacity: true)
    completionHandler(.allow)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard dataTask.taskIdentifier == activeTaskIdentifier else {
      return
    }
    guard activeData.count + data.count <= Self.maxDownloadBytes else {
      activeData.removeAll(keepingCapacity: false)
      dataTask.cancel()
      return
    }
    activeData.append(data)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard task.taskIdentifier == activeTaskIdentifier else {
      return
    }
    let data = activeData
    let requestGeneration = generation
    let candidateIndex = activeCandidateIndex
    let refresh = activeRefresh
    dataTask = nil
    activeTaskIdentifier = nil
    activeCandidateIndex = nil
    activeRefresh = nil
    activeData.removeAll(keepingCapacity: false)
    guard let candidateIndex else {
      return
    }
    guard error == nil, !data.isEmpty else {
      if let refresh {
        loadCandidate(
          at: candidateIndex + 1,
          refresh: refresh,
          generation: requestGeneration
        )
      }
      return
    }

    DispatchQueue.global(qos: .utility).async { [weak self] in
      let image = Self.downsampledImage(from: data)
      DispatchQueue.main.async {
        guard let self,
          self.generation == requestGeneration
        else {
          return
        }
        guard let image else {
          if let refresh {
            self.loadCandidate(
              at: candidateIndex + 1,
              refresh: refresh,
              generation: requestGeneration
            )
          }
          return
        }
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        refresh?()
      }
    }
  }

  private static func downsampledImage(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}

func normalizedNowPlayingArtworkCandidates(
  _ raw: [[String: Any]]?
) -> [StarflowNowPlayingArtworkCandidate] {
  return normalizedNowPlayingArtworkCandidates(
    (raw ?? []).map { item in
      StarflowNowPlayingArtworkCandidate(
        urlString: (item["url"] as? String) ?? "",
        headers: normalizedStringMap(item["headers"] as? [String: Any])
      )
    }
  )
}

func normalizedNowPlayingArtworkCandidates(
  _ raw: [StarflowNowPlayingArtworkCandidate]
) -> [StarflowNowPlayingArtworkCandidate] {
  var seenUrls = Set<String>()
  return raw.compactMap { candidate in
    let urlString = candidate.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !urlString.isEmpty, seenUrls.insert(urlString).inserted else {
      return nil
    }
    return StarflowNowPlayingArtworkCandidate(
      urlString: urlString,
      headers: normalizedStringMap(candidate.headers)
    )
  }
}

func normalizedStringMap(_ raw: [String: Any]?) -> [String: String] {
  return (raw ?? [:]).reduce(into: [String: String]()) { result, item in
    let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = "\(item.value)".trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty && !value.isEmpty {
      result[key] = value
    }
  }
}

func normalizedStringMap(_ raw: [String: String]) -> [String: String] {
  return raw.reduce(into: [String: String]()) { result, item in
    let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty && !value.isEmpty {
      result[key] = value
    }
  }
}

enum StarflowAudioSession {
  private static var activeOwners = Set<String>()

  static func configurePlayback(
    enabled: Bool,
    owner: String,
    options: AVAudioSession.CategoryOptions = [
      .allowAirPlay,
      .allowBluetoothHFP,
      .allowBluetoothA2DP,
    ]
  ) {
    let session = AVAudioSession.sharedInstance()
    if enabled {
      activeOwners.insert(owner)
      do {
        try session.setCategory(.playback, mode: .moviePlayback, options: options)
      } catch {
        StarflowNativeLog.error(
          category: "ios.audio-session",
          message: "Failed to set playback audio session category",
          fields: [
            "owner": owner,
            "enabled": enabled,
            "operation": "setCategory",
          ],
          error: error
        )
        return
      }
      do {
        try session.setActive(true)
      } catch {
        StarflowNativeLog.error(
          category: "ios.audio-session",
          message: "Failed to activate playback audio session",
          fields: [
            "owner": owner,
            "enabled": enabled,
            "operation": "setActive",
          ],
          error: error
        )
      }
      return
    }

    guard activeOwners.remove(owner) != nil, activeOwners.isEmpty else {
      return
    }

    do {
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
    } catch {
      StarflowNativeLog.error(
        category: "ios.audio-session",
        message: "Failed to deactivate playback audio session",
        fields: [
          "owner": owner,
          "enabled": enabled,
          "operation": "setActive",
        ],
        error: error
      )
    }
  }
}

enum StarflowNativeLog {
  static func error(
    category: String,
    message: String,
    fields: [String: Any] = [:],
    error: Error? = nil
  ) {
    write(level: "error", category: category, message: message, fields: fields, error: error)
  }

  private static func write(
    level: String,
    category: String,
    message: String,
    fields: [String: Any],
    error: Error?
  ) {
    var payload = fields
    if let error {
      payload["error"] = String(describing: error)
    }
    payload["level"] = level
    payload["category"] = category
    payload["message"] = message

    let line: String
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    {
      line = json
    } else {
      line = "\(payload)"
    }
    NSLog("[Starflow] %@", line)
  }
}
