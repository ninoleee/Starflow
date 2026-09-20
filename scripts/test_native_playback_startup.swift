import AVFoundation
import Foundation

final class ReadyPlaybackItem: AVPlayerItem {
  var failure: Error?
  var waitingForBuffer = false
  var cancelledSeeks = 0
  override var error: Error? { failure }
  func notifyBufferChange() {
    willChangeValue(forKey: "playbackLikelyToKeepUp")
    didChangeValue(forKey: "playbackLikelyToKeepUp")
  }
  override var status: AVPlayerItem.Status { .readyToPlay }
  override var duration: CMTime { CMTime(seconds: 600, preferredTimescale: 1) }
  override var isPlaybackLikelyToKeepUp: Bool { !waitingForBuffer }
  override var isPlaybackBufferEmpty: Bool { waitingForBuffer }
  override var isPlaybackBufferFull: Bool { false }
  override func cancelPendingSeeks() { cancelledSeeks += 1 }
}

final class StartupCountingPlayer: AVPlayer {
  var prerollCalls = 0
  var playCalls = 0
  var pending: ((Bool) -> Void)?
  var pendingSeek: ((Bool) -> Void)?
  var seekCalls = 0
  var cancelledPrerolls = 0
  override func preroll(atRate rate: Float, completionHandler: ((Bool) -> Void)? = nil) {
    prerollCalls += 1
    pending = completionHandler
  }
  override func play() { playCalls += 1 }
  override func cancelPendingPrerolls() { cancelledPrerolls += 1 }
  override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
    completionHandler: @escaping (Bool) -> Void) {
    seekCalls += 1
    pendingSeek = completionHandler
  }
}

final class IntentPrerollPlayer: NativePlaybackIntentPlayer {
  var pending: ((Bool) -> Void)?
  override func preroll(atRate rate: Float, completionHandler: ((Bool) -> Void)? = nil) {
    pending = completionHandler
  }
}

@main
enum NativePlaybackStartupTests {
  static let commands = ["pause", "play", "immediatePlay", "rate", "seek", "seekCompletion",
    "seekTolerance", "seekToleranceCompletion", "seekDate", "seekDateCompletion"]

  static func send(_ command: String, to player: NativePlaybackIntentPlayer) {
    switch command {
    case "pause": player.pause()
    case "play": player.play()
    case "immediatePlay": player.playImmediately(atRate: 1)
    case "rate": player.rate = 0
    case "seek": player.seek(to: .zero)
    case "seekCompletion": player.seek(to: .zero) { _ in }
    case "seekTolerance": player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    case "seekToleranceCompletion":
      player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
    case "seekDate": player.seek(to: Date(timeIntervalSince1970: 0))
    case "seekDateCompletion": player.seek(to: Date(timeIntervalSince1970: 0)) { _ in }
    default: preconditionFailure("unknown command")
    }
  }

  @MainActor
  static func main() async {
    for finish in [true, false] {
      let item = ReadyPlaybackItem(asset: AVMutableComposition())
      let player = StartupCountingPlayer()
      let gate = NativePlaybackStartupGate(player: player, item: item)
      var completions = 0
      gate.start { result in
        completions += 1
        switch result {
        case .started: precondition(finish)
        case .failed: preconditionFailure("interruption is not a failure")
        case .cancelled: precondition(!finish)
        }
      }
      for _ in 0..<3 {
        item.notifyBufferChange()
        await Task.yield()
      }
      precondition(player.prerollCalls == 1)
      player.pending?(finish)
      try? await Task.sleep(nanoseconds: 10_000_000)
      precondition(completions == 1 && player.playCalls == (finish ? 1 : 0))
      player.pending?(true)
      await Task.yield()
      precondition(completions == 1)
    }
    let item = ReadyPlaybackItem(asset: AVMutableComposition())
    let player = StartupCountingPlayer()
    let gate = NativePlaybackStartupGate(player: player, item: item)
    var cancellations = 0
    gate.start { if case .cancelled = $0 { cancellations += 1 } }
    gate.cancel()
    player.pending?(true)
    try? await Task.sleep(nanoseconds: 10_000_000)
    precondition(cancellations == 1 && player.playCalls == 0)

    let unusedItem = ReadyPlaybackItem(asset: AVMutableComposition())
    let unusedPlayer = StartupCountingPlayer()
    let unusedGate = NativePlaybackStartupGate(player: unusedPlayer, item: unusedItem)
    unusedGate.cancel()
    unusedGate.start(resumeSeekTime: CMTime(seconds: 30, preferredTimescale: 1)) { _ in
      preconditionFailure("cancelled gate restarted")
    }
    precondition(unusedPlayer.seekCalls == 0 && unusedPlayer.prerollCalls == 0)

    for succeeded in [true, false] {
      let item = ReadyPlaybackItem(asset: AVMutableComposition())
      let player = StartupCountingPlayer()
      let gate = NativePlaybackStartupGate(player: player, item: item)
      var results = 0
      gate.start(resumeSeekTime: CMTime(seconds: 30, preferredTimescale: 1)) { result in
        guard case .cancelled = result else { preconditionFailure("stale resume seek committed") }
        precondition(player.cancelledPrerolls == 1 && item.cancelledSeeks == 1,
          "pending operations must drain before the completion can start new work")
        results += 1
      }
      precondition(player.seekCalls == 1 && player.prerollCalls == 0)
      gate.cancel()
      gate.cancel()
      player.pendingSeek?(succeeded)
      item.notifyBufferChange()
      try? await Task.sleep(nanoseconds: 10_000_000)
      precondition(results == 1 && player.prerollCalls == 0 && player.playCalls == 0)
    }

    let bufferingItem = ReadyPlaybackItem(asset: AVMutableComposition())
    bufferingItem.waitingForBuffer = true
    let bufferingPlayer = StartupCountingPlayer()
    let bufferingGate = NativePlaybackStartupGate(player: bufferingPlayer, item: bufferingItem,
      configuration: .init(waitForLikelyToKeepUp: true, usePreroll: true,
        prerollRate: 1, keepUpTimeout: 0.01))
    bufferingGate.start {
      guard case .cancelled = $0 else { preconditionFailure("cancelled buffer wait committed") }
    }
    bufferingGate.cancel()
    bufferingItem.waitingForBuffer = false
    bufferingItem.notifyBufferChange()
    try? await Task.sleep(nanoseconds: 30_000_000)
    precondition(bufferingPlayer.prerollCalls == 0 && bufferingPlayer.playCalls == 0)

    for command in commands {
      let item = ReadyPlaybackItem(asset: AVMutableComposition())
      let player = IntentPrerollPlayer()
      let gate = NativePlaybackStartupGate(player: player, item: item)
      var results = 0
      var commands = 0
      player.onUserCommand = { commands += 1; gate.cancel() }
      gate.start {
        guard case .cancelled = $0 else { preconditionFailure("stale startup committed") }
        results += 1
      }
      precondition(player.pending != nil)
      send(command, to: player)
      player.pending?(true)
      try? await Task.sleep(nanoseconds: 10_000_000)
      precondition(results == 1 && commands == 1)
    }

    let failedItem = ReadyPlaybackItem(asset: AVMutableComposition())
    let failedPlayer = StartupCountingPlayer()
    let failedGate = NativePlaybackStartupGate(player: failedPlayer, item: failedItem)
    var failures = 0
    failedGate.start { if case .failed = $0 { failures += 1 } }
    failedItem.failure = NSError(domain: "test", code: 1)
    failedPlayer.pending?(false)
    try? await Task.sleep(nanoseconds: 10_000_000)
    precondition(failures == 1 && failedPlayer.playCalls == 0)

    for command in commands + ["exit", "previous", "timeout"] {
      let intent = NativePlaybackEpisodeIntent()
      let automatic = intent.begin(automatic: true)!
      precondition(intent.begin(automatic: true) == nil)
      let intentPlayer = NativePlaybackIntentPlayer()
      var userCommands = 0
      intentPlayer.onUserCommand = {
        userCommands += 1
        intent.cancel()
      }
      intentPlayer.automatically { intentPlayer.pause() }
      precondition(userCommands == 0 && intent.pending)
      var manual: Int?
      switch command {
      case "exit": intent.cancel()
      case "timeout": precondition(intent.finish(automatic))
      case "previous": manual = intent.begin(automatic: false)
      default: send(command, to: intentPlayer)
      }
      // Model a resolver callback after cancellation: release, never switch.
      var released = 0
      var switched = 0
      if intent.finish(automatic) { switched += 1 } else { released += 1 }
      precondition(released == 1 && switched == 0)
      if let manual {
        precondition(intent.finish(manual))
        precondition(!intent.finish(automatic))
      } else {
        precondition(!intent.pending)
      }
      if commands.contains(command) {
        precondition(userCommands == 1)
      }
    }

    for command in commands {
      let intent = NativePlaybackEpisodeIntent()
      let manual = intent.begin(automatic: false)!
      let player = NativePlaybackIntentPlayer()
      player.onUserCommand = { intent.cancel() }
      player.automatically { send(command, to: player) }
      precondition(intent.pending)
      send(command, to: player)
      precondition(!intent.finish(manual), "a later user command must supersede a manual resolver too")
    }

    let controlledItem = ReadyPlaybackItem(asset: AVMutableComposition())
    let controlledPlayer = NativePlaybackIntentPlayer()
    let controlledGate = NativePlaybackStartupGate(player: controlledPlayer, item: controlledItem,
      configuration: .init(waitForLikelyToKeepUp: false, usePreroll: false,
        prerollRate: 1, keepUpTimeout: 0))
    var startupCommands = 0
    controlledPlayer.onUserCommand = { startupCommands += 1 }
    controlledGate.start { _ in }
    precondition(startupCommands == 0)

    let url = URL(string: "https://live.example.test/vod/movie.m3u8?live=1")!
    let vod = NativePlaybackBufferingTuning.Context(url: url)
    precondition(!vod.isLiveStream)
    precondition(NativePlaybackBufferingTuning.makeConfiguration(context: vod).preferredForwardBufferDuration == 24)
    let live = NativePlaybackBufferingTuning.Context(url: url, isLiveStream: true)
    precondition(NativePlaybackBufferingTuning.makeConfiguration(context: live).preferredForwardBufferDuration == 8)
    print("Native startup: preroll success/interruption/failure/cancel, cancel-before-start, resume-seek/keep-up cancellation, cleanup ordering, all 10 user command entry points, automatic/manual resolver supersession, timeout/exit and HLS policies passed (host strategy checks only)")
  }
}
