import AVFoundation
import Foundation

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
    guard !hasStarted else {
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
      player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        guard let self else {
          return
        }
        self.seekCompleted = true
        self.evaluateStartupGate()
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
    finish(with: .cancelled)
  }

  private func installObservers() {
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      guard let self else {
        return
      }
      self.evaluateStartupGate()
    }
    keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) {
      [weak self] _, _ in
      guard let self else {
        return
      }
      self.evaluateStartupGate()
    }
    bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) {
      [weak self] _, _ in
      guard let self else {
        return
      }
      self.evaluateStartupGate()
    }
    bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) {
      [weak self] _, _ in
      guard let self else {
        return
      }
      self.evaluateStartupGate()
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

    guard item.status == .readyToPlay, seekCompleted else {
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
    guard !didComplete else {
      return
    }
    keepUpTimeoutWorkItem?.cancel()
    keepUpTimeoutWorkItem = nil

    if configuration.usePreroll {
      player.preroll(atRate: configuration.prerollRate) { [weak self] _ in
        Task { @MainActor in
          self?.playAndFinish(didUsePreroll: true)
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
    player.play()
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

  private func finish(with result: StartupResult) {
    guard !didComplete else {
      return
    }
    didComplete = true
    keepUpTimeoutWorkItem?.cancel()
    keepUpTimeoutWorkItem = nil
    invalidateObservers()
    let callback = completion
    completion = nil
    callback?(result)
  }
}
