import AVFoundation
import AVKit
import Flutter
import MediaPlayer
import UIKit

final class PlaybackSystemSessionBridge {
  private weak var channel: FlutterMethodChannel?
  private let topViewControllerProvider: () -> UIViewController?
  private let artworkLoader = StarflowNowPlayingArtworkLoader()
  private var isActive = false
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
      configureAudioSession(enabled: true)
      installRemoteCommands()
      registerSystemObservers()
      UIApplication.shared.beginReceivingRemoteControlEvents()
    } else {
      unregisterSystemObservers()
      uninstallRemoteCommands()
      artworkLoader.reset()
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
    commandCenter.stopCommand.isEnabled = true
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
    commandCenter.stopCommand.addTarget { [weak self] _ in
      self?.dispatchRemoteCommand("stop")
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
    let title =
      (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let subtitle =
      (arguments["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let positionMs = (arguments["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let durationMs = (arguments["durationMs"] as? NSNumber)?.doubleValue ?? 0
    let playing = arguments["playing"] as? Bool ?? false
    let buffering = arguments["buffering"] as? Bool ?? false
    let speed = (arguments["speed"] as? NSNumber)?.doubleValue ?? 1
    let artworkUrl =
      (arguments["artworkUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let artworkHeaders = normalizedStringMap(arguments["artworkHeaders"] as? [String: Any])
    let hasPrevious = arguments["hasPrevious"] as? Bool ?? false
    let hasNext = arguments["hasNext"] as? Bool ?? false
    let canSeek = arguments["canSeek"] as? Bool ?? true

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
      urlString: artworkUrl,
      headers: artworkHeaders
    ) { [weak self] in
      self?.updateNowPlayingInfo(arguments)
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
      dispatchRemoteCommand("interruptionPause")
    case .ended:
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      if options.contains(.shouldResume) {
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

final class StarflowNowPlayingArtworkLoader {
  private var artworkUrl = ""
  private var artworkHeaders: [String: String] = [:]
  private var artwork: MPMediaItemArtwork?
  private var dataTask: URLSessionDataTask?
  private var generation = 0

  func applyArtwork(
    to info: inout [String: Any],
    urlString: String,
    headers: [String: String] = [:],
    refresh: @escaping () -> Void
  ) {
    let normalizedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedHeaders = normalizedStringMap(headers)
    if normalizedUrl != artworkUrl || normalizedHeaders != artworkHeaders {
      startLoading(urlString: normalizedUrl, headers: normalizedHeaders, refresh: refresh)
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
    artworkUrl = ""
    artworkHeaders = [:]
    artwork = nil
    generation += 1
  }

  private func startLoading(
    urlString: String,
    headers: [String: String],
    refresh: @escaping () -> Void
  ) {
    dataTask?.cancel()
    dataTask = nil
    artworkUrl = urlString
    artworkHeaders = headers
    artwork = nil
    generation += 1

    guard !urlString.isEmpty,
      let url = URL(string: urlString),
      url.scheme != nil
    else {
      return
    }

    let requestGeneration = generation
    var request = URLRequest(
      url: url,
      cachePolicy: .returnCacheDataElseLoad,
      timeoutInterval: 12
    )
    for (name, value) in headers where !name.isEmpty && !value.isEmpty {
      request.setValue(value, forHTTPHeaderField: name)
    }

    dataTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      DispatchQueue.main.async {
        guard let self,
          self.generation == requestGeneration,
          self.artworkUrl == urlString,
          self.artworkHeaders == headers
        else {
          return
        }
        self.dataTask = nil
        guard let data,
          let image = UIImage(data: data)
        else {
          return
        }
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        refresh()
      }
    }
    dataTask?.resume()
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
  static func configurePlayback(
    enabled: Bool,
    owner: String,
    options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
  ) {
    let session = AVAudioSession.sharedInstance()
    if enabled {
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
