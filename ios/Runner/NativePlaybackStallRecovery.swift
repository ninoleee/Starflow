import Foundation
import AVFoundation

/// Conservative stall recovery helper for AVPlayer native playback.
/// - Watches stalled notification + key buffer signals on AVPlayerItem.
/// - Tries to recover with bounded retries and minimum intervals.
/// - Owns observer lifecycle and can be torn down via `stop()`.
final class NativePlaybackStallRecovery {
  private enum RecoveryReason {
    case stalledNotification
    case bufferEmpty
    case likelyToKeepUp
    case bufferFull
  }

  private let minAttemptInterval: TimeInterval
  private let attemptWindow: TimeInterval
  private let maxAttemptsInWindow: Int
  private let baseBackoff: TimeInterval
  private let maxBackoff: TimeInterval

  private weak var player: AVPlayer?
  private weak var item: AVPlayerItem?

  private var stalledObserver: NSObjectProtocol?
  private var bufferEmptyObservation: NSKeyValueObservation?
  private var likelyToKeepUpObservation: NSKeyValueObservation?
  private var bufferFullObservation: NSKeyValueObservation?
  private var itemStatusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?

  private var pendingRecoveryWorkItem: DispatchWorkItem?
  private var attemptTimestamps: [Date] = []
  private var lastAttemptAt: Date?
  private var shouldResumeAfterBuffering = false
  private var isRecovering = false

  init(
    minAttemptInterval: TimeInterval = 1.5,
    attemptWindow: TimeInterval = 12.0,
    maxAttemptsInWindow: Int = 3,
    baseBackoff: TimeInterval = 0.6,
    maxBackoff: TimeInterval = 2.5
  ) {
    self.minAttemptInterval = minAttemptInterval
    self.attemptWindow = attemptWindow
    self.maxAttemptsInWindow = maxAttemptsInWindow
    self.baseBackoff = baseBackoff
    self.maxBackoff = maxBackoff
  }

  deinit {
    stop()
  }

  func start(player: AVPlayer, item: AVPlayerItem? = nil) {
    stop()

    let targetItem = item ?? player.currentItem
    guard let targetItem else {
      return
    }

    self.player = player
    self.item = targetItem
    self.shouldResumeAfterBuffering =
      player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate

    stalledObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemPlaybackStalled,
      object: targetItem,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleRecovery(reason: .stalledNotification, preferredDelay: 0.0)
    }

    bufferEmptyObservation = targetItem.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) {
      [weak self] item, change in
      guard let self, let isEmpty = change.newValue, isEmpty else {
        return
      }
      if self.shouldAttemptResume(for: self.player) {
        self.shouldResumeAfterBuffering = true
      }
      self.scheduleRecovery(reason: .bufferEmpty, preferredDelay: self.baseBackoff)
    }

    likelyToKeepUpObservation =
      targetItem.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) {
        [weak self] _, change in
        guard let self, let keepUp = change.newValue, keepUp else {
          return
        }
        self.scheduleRecovery(reason: .likelyToKeepUp, preferredDelay: 0.0)
      }

    bufferFullObservation = targetItem.observe(\.isPlaybackBufferFull, options: [.initial, .new]) {
      [weak self] _, change in
      guard let self, let full = change.newValue, full else {
        return
      }
      self.scheduleRecovery(reason: .bufferFull, preferredDelay: 0.0)
    }

    itemStatusObservation = targetItem.observe(\.status, options: [.new]) { [weak self] _, _ in
      self?.scheduleRecovery(reason: .likelyToKeepUp, preferredDelay: 0.0)
    }

    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      guard let self else {
        return
      }
      if player.timeControlStatus == .playing {
        self.attemptTimestamps.removeAll()
        self.pendingRecoveryWorkItem?.cancel()
        self.pendingRecoveryWorkItem = nil
        self.isRecovering = false
      } else if player.timeControlStatus == .paused && !self.isRecovering {
        // Respect explicit pauses and avoid forcing resume after user pause.
        self.shouldResumeAfterBuffering = false
      }
    }
  }

  func stop() {
    pendingRecoveryWorkItem?.cancel()
    pendingRecoveryWorkItem = nil

    if let observer = stalledObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    stalledObserver = nil

    bufferEmptyObservation = nil
    likelyToKeepUpObservation = nil
    bufferFullObservation = nil
    itemStatusObservation = nil
    timeControlObservation = nil

    attemptTimestamps.removeAll()
    lastAttemptAt = nil
    shouldResumeAfterBuffering = false
    isRecovering = false
    player = nil
    item = nil
  }

  private func scheduleRecovery(reason: RecoveryReason, preferredDelay: TimeInterval) {
    guard let player, let item else {
      return
    }
    guard item.status == .readyToPlay else {
      return
    }
    guard shouldResumeAfterBuffering || shouldAttemptResume(for: player) else {
      return
    }

    let now = Date()
    if let lastAttemptAt {
      let sinceLast = now.timeIntervalSince(lastAttemptAt)
      if sinceLast < minAttemptInterval {
        enqueueRecovery(after: minAttemptInterval - sinceLast)
        return
      }
    }

    attemptTimestamps = attemptTimestamps.filter { now.timeIntervalSince($0) <= attemptWindow }
    if attemptTimestamps.count >= maxAttemptsInWindow {
      enqueueRecovery(after: maxBackoff)
      return
    }

    switch reason {
    case .stalledNotification, .bufferEmpty:
      let backoffMultiplier = Double(attemptTimestamps.count + 1)
      let delay = min(max(preferredDelay, baseBackoff * backoffMultiplier), maxBackoff)
      enqueueRecovery(after: delay)
    case .likelyToKeepUp, .bufferFull:
      enqueueRecovery(after: preferredDelay)
    }
  }

  private func enqueueRecovery(after delay: TimeInterval) {
    pendingRecoveryWorkItem?.cancel()
    let task = DispatchWorkItem { [weak self] in
      self?.performRecoveryAttempt()
    }
    pendingRecoveryWorkItem = task
    DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0), execute: task)
  }

  private func performRecoveryAttempt() {
    guard let player, let item else {
      return
    }
    guard player.currentItem === item else {
      return
    }
    guard item.status == .readyToPlay else {
      return
    }
    guard shouldResumeAfterBuffering || shouldAttemptResume(for: player) else {
      return
    }

    if item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp && !item.isPlaybackBufferFull {
      // Buffer is still clearly insufficient; wait for next signal.
      return
    }

    let now = Date()
    if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < minAttemptInterval {
      enqueueRecovery(after: minAttemptInterval - now.timeIntervalSince(lastAttemptAt))
      return
    }

    isRecovering = true
    defer { isRecovering = false }

    lastAttemptAt = now
    attemptTimestamps.append(now)
    player.play()
  }

  private func shouldAttemptResume(for player: AVPlayer?) -> Bool {
    guard let player else {
      return false
    }
    return player.timeControlStatus == .playing
      || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
      || player.rate > 0.01
  }
}
