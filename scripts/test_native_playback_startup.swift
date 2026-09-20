import AVFoundation
import Foundation

final class ReadyPlaybackItem: AVPlayerItem {
  var failure: Error?
  override var error: Error? { failure }
  func notifyBufferChange() {
    willChangeValue(forKey: "playbackLikelyToKeepUp")
    didChangeValue(forKey: "playbackLikelyToKeepUp")
  }
  override var status: AVPlayerItem.Status { .readyToPlay }
  override var duration: CMTime { CMTime(seconds: 600, preferredTimescale: 1) }
  override var isPlaybackLikelyToKeepUp: Bool { true }
  override var isPlaybackBufferEmpty: Bool { false }
  override var isPlaybackBufferFull: Bool { false }
}

final class StartupCountingPlayer: AVPlayer {
  var prerollCalls = 0
  var playCalls = 0
  var pending: ((Bool) -> Void)?
  override func preroll(atRate rate: Float, completionHandler: ((Bool) -> Void)? = nil) {
    prerollCalls += 1
    pending = completionHandler
  }
  override func play() { playCalls += 1 }
}

final class IntentPrerollPlayer: NativePlaybackIntentPlayer {
  var pending: ((Bool) -> Void)?
  override func preroll(atRate rate: Float, completionHandler: ((Bool) -> Void)? = nil) {
    pending = completionHandler
  }
}

@main
enum NativePlaybackStartupTests {
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

    for seek in [false, true] {
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
      if seek {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
      } else {
        player.pause()
      }
      player.pending?(true)
      try? await Task.sleep(nanoseconds: 10_000_000)
      precondition(results == 1 && commands == 1 && player.rate == 0)
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

    for command in ["pause", "play", "seek", "rate", "exit", "previous"] {
      let intent = NativePlaybackEpisodeIntent()
      let automatic = intent.begin(automatic: true)!
      precondition(intent.begin(automatic: true) == nil)
      let intentPlayer = NativePlaybackIntentPlayer()
      var userCommands = 0
      intentPlayer.onUserCommand = {
        userCommands += 1
        intent.cancelAutomatic()
      }
      intentPlayer.automatically { intentPlayer.pause() }
      precondition(userCommands == 0 && intent.pending)
      var manual: Int?
      switch command {
      case "pause": intentPlayer.pause()
      case "play": intentPlayer.play()
      case "seek": intentPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
      case "rate": intentPlayer.rate = 0
      case "exit": intent.cancel()
      default: manual = intent.begin(automatic: false)
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
      if ["pause", "play", "seek", "rate"].contains(command) {
        precondition(userCommands == 1)
      }
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
    print("Native startup: preroll success/interruption/failure/cancel, late callbacks, user commands, episode supersession and HLS policies passed")
  }
}
