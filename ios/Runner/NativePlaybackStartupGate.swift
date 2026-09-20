import AVFoundation
import Foundation

/// AVKit controls and remote commands share this synchronous intent boundary.
/// Startup commands bypass it; state/KVO notifications are not user commands.
class NativePlaybackIntentPlayer: AVPlayer {
  var onUserCommand: (() -> Void)?
  private var automaticDepth = 0

  func automatically(_ action: () -> Void) {
    automaticDepth += 1
    defer { automaticDepth -= 1 }
    action()
  }

  private func command(_ action: () -> Void) {
    if automaticDepth == 0 { onUserCommand?() }
    automatically(action)
  }

  override var rate: Float {
    get { super.rate }
    set { command { super.rate = newValue } }
  }

  override func play() { command { super.play() } }
  override func pause() { command { super.pause() } }

  override func playImmediately(atRate rate: Float) {
    command { super.playImmediately(atRate: rate) }
  }

  override func seek(to date: Date) {
    command { super.seek(to: date) }
  }

  override func seek(to date: Date, completionHandler: @escaping (Bool) -> Void) {
    command { super.seek(to: date, completionHandler: completionHandler) }
  }

  override func seek(to time: CMTime) {
    command { super.seek(to: time) }
  }

  override func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
    command { super.seek(to: time, completionHandler: completionHandler) }
  }

  override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
    command { super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) }
  }

  override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
    completionHandler: @escaping (Bool) -> Void) {
    command {
      super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter,
        completionHandler: completionHandler)
    }
  }
}

/// Only a current resolver result can commit. Manual requests supersede pending
/// automatic requests; cancellation does not consume the next manual request.
final class NativePlaybackEpisodeIntent {
  private(set) var generation = 0
  private(set) var pending = false
  private var automatic = false

  func begin(automatic: Bool) -> Int? {
    if pending && automatic { return nil }
    cancel()
    pending = true
    self.automatic = automatic
    return generation
  }

  func cancelAutomatic() {
    if pending && automatic { cancel() }
  }

  func cancel() {
    generation += 1
    pending = false
  }

  func finish(_ token: Int) -> Bool {
    guard pending, generation == token else { return false }
    pending = false
    return true
  }
}

@MainActor
final class NativePlaybackStartupGate {
  struct Configuration {
    var waitForLikelyToKeepUp: Bool
    var usePreroll: Bool
    var prerollRate: Float
    var keepUpTimeout: TimeInterval

    static let balanced = Configuration(
      waitForLikelyToKeepUp: true,
      usePreroll: true,
      prerollRate: 1.0,
      keepUpTimeout: 2.0
    )
  }

  struct StartupDiagnostics {
    let didApplyResumeSeek: Bool
    let didWaitForKeepUp: Bool
    let didUsePreroll: Bool
  }

  enum StartupResult {
    case started(StartupDiagnostics)
    case failed(Error?)
    case cancelled
  }

  private let player: AVPlayer
  private let item: AVPlayerItem
  private let configuration: Configuration

  private var statusObservation: NSKeyValueObservation?
  private var keepUpObservation: NSKeyValueObservation?
  private var bufferEmptyObservation: NSKeyValueObservation?
  private var bufferFullObservation: NSKeyValueObservation?
  private var keepUpTimeoutWorkItem: DispatchWorkItem?

  private var completion: ((StartupResult) -> Void)?
  private var hasStarted = false
  private var didComplete = false
  private var prerollInFlight = false
  private var seekCompleted = false
  private var didApplyResumeSeek = false
  private var didWaitForKeepUp = false

  init(
    player: AVPlayer,
    item: AVPlayerItem,
    configuration: Configuration = .balanced
  ) {
    self.player = player
    self.item = item
    self.configuration = configuration
  }

  deinit {
    // `deinit` is nonisolated; cannot call `@MainActor` instance methods.
    statusObservation = nil
    keepUpObservation = nil
    bufferEmptyObservation = nil
    bufferFullObservation = nil
    keepUpTimeoutWorkItem?.cancel()
  }

  func start(
    resumeSeekTime: CMTime? = nil,
    completion: @escaping (StartupResult) -> Void
  ) {
    guard !hasStarted, !didComplete else {
      return
    }
    hasStarted = true
    self.completion = completion
    installObservers()

    if let seekTime = resumeSeekTime,
      seekTime.isValid,
      !seekTime.isIndefinite,
      seekTime.seconds.isFinite,
      seekTime.seconds > 0
    {
      didApplyResumeSeek = true
      automatically {
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] succeeded in
          Task { @MainActor in
            guard let self, !self.didComplete else { return }
            guard succeeded else {
              self.finish(with: .cancelled)
              return
            }
            self.seekCompleted = true
            self.evaluateStartupGate()
          }
        }
      }
    } else {
      seekCompleted = true
      evaluateStartupGate()
    }
  }

  func cancel() {
    guard !didComplete else {
      return
    }
    finish(with: .cancelled, cancelPendingOperations: true)
  }

  private func installObservers() {
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor in self?.evaluateStartupGate() }
    }
    keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) {
      [weak self] _, _ in
      Task { @MainActor in self?.evaluateStartupGate() }
    }
    bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) {
      [weak self] _, _ in
      Task { @MainActor in self?.evaluateStartupGate() }
    }
    bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) {
      [weak self] _, _ in
      Task { @MainActor in self?.evaluateStartupGate() }
    }
  }

  private func invalidateObservers() {
    statusObservation = nil
    keepUpObservation = nil
    bufferEmptyObservation = nil
    bufferFullObservation = nil
  }

  private func evaluateStartupGate() {
    guard !didComplete else {
      return
    }

    if item.status == .failed {
      finish(with: .failed(item.error))
      return
    }

    guard item.status == .readyToPlay, seekCompleted, !prerollInFlight else {
      return
    }

    if shouldWaitForKeepUp() {
      didWaitForKeepUp = true
      scheduleKeepUpTimeoutIfNeeded()
      return
    }

    keepUpTimeoutWorkItem?.cancel()
    beginPlayback()
  }

  private func shouldWaitForKeepUp() -> Bool {
    guard configuration.waitForLikelyToKeepUp else {
      return false
    }
    if item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull {
      return false
    }
    return item.isPlaybackBufferEmpty
  }

  private func scheduleKeepUpTimeoutIfNeeded() {
    guard configuration.keepUpTimeout > 0 else {
      beginPlayback()
      return
    }
    guard keepUpTimeoutWorkItem == nil else {
      return
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.didComplete else {
        return
      }
      self.beginPlayback()
    }
    keepUpTimeoutWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + configuration.keepUpTimeout, execute: work)
  }

  private func beginPlayback() {
    guard !didComplete, !prerollInFlight else {
      return
    }
    keepUpTimeoutWorkItem?.cancel()
    keepUpTimeoutWorkItem = nil

    if configuration.usePreroll && !item.duration.isIndefinite {
      prerollInFlight = true
      player.preroll(atRate: configuration.prerollRate) { [weak self] succeeded in
        Task { @MainActor in
          guard let self, !self.didComplete else { return }
          self.prerollInFlight = false
          guard succeeded else {
            // AVFoundation also returns false for a time/rate interruption.
            // Do not restart here: that could undo the user's pause or seek.
            if self.item.status == .failed || self.item.error != nil {
              self.finish(with: .failed(self.item.error))
            } else {
              self.finish(with: .cancelled)
            }
            return
          }
          self.playAndFinish(didUsePreroll: true)
        }
      }
      return
    }

    playAndFinish(didUsePreroll: false)
  }

  private func playAndFinish(didUsePreroll: Bool) {
    guard !didComplete else {
      return
    }
    automatically { player.play() }
    finish(
      with: .started(
        StartupDiagnostics(
          didApplyResumeSeek: didApplyResumeSeek,
          didWaitForKeepUp: didWaitForKeepUp,
          didUsePreroll: didUsePreroll
        )
      )
    )
  }

  private func finish(with result: StartupResult, cancelPendingOperations: Bool = false) {
    guard !didComplete else {
      return
    }
    didComplete = true
    prerollInFlight = false
    keepUpTimeoutWorkItem?.cancel()
    keepUpTimeoutWorkItem = nil
    invalidateObservers()
    let callback = completion
    completion = nil
    // Invalidate first, then drain AVFoundation before a callback can start new work.
    if cancelPendingOperations {
      player.cancelPendingPrerolls()
      item.cancelPendingSeeks()
    }
    callback?(result)
  }

  private func automatically(_ action: () -> Void) {
    if let intentPlayer = player as? NativePlaybackIntentPlayer {
      intentPlayer.automatically(action)
    } else {
      action()
    }
  }
}
