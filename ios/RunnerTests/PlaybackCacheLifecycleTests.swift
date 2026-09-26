import AVFoundation
#if !CACHE_STRATEGY_CHECKS
import Flutter
import UIKit
import XCTest
@testable import Runner
#endif

private enum MemoryReadinessStrategyChecks {
  static func run() {
    var policy = NativePlaybackMemoryReadiness()
    func sample(_ position: Double, ahead: Double? = 24, ready: Bool = true,
      playing: Bool = true, startup: Bool = false, empty: Bool = false,
      full: Bool = true, keepUp: Bool = true) -> Bool {
      policy.sample(position: position, bufferedAhead: ahead, itemReady: ready,
        playing: playing, startupPending: startup, bufferEmpty: empty,
        bufferFull: full, likelyToKeepUp: keepUp)
    }
    precondition(!sample(1))
    precondition(sample(2))
    precondition(!sample(3, full: false)) // A duration/keep-up hint is not fullness.
    precondition(!sample(4, keepUp: false))
    precondition(!sample(4)) // No playback progress.
    precondition(!sample(3)) // Backwards discontinuity.
    for invalid in [
      { sample(5, ahead: nil) }, { sample(5, ahead: .nan) },
      { sample(5, ahead: .infinity) }, { sample(5, ahead: 0) },
      { sample(5, ahead: -1) }, { sample(.nan) }, { sample(.infinity) },
      { sample(-1) }, { sample(5, ready: false) },
      { sample(5, playing: false) }, { sample(5, startup: true) },
      { sample(5, empty: true) },
    ] {
      precondition(!invalid())
      precondition(!sample(6))
      precondition(sample(7))
    }
    policy.invalidate() // Seek, rebuild, pause and end discard prior evidence.
    precondition(!sample(100))
    precondition(sample(101))
  }
}

#if CACHE_STRATEGY_CHECKS
@main
enum PlaybackCacheStrategyChecks {
  static func main() {
    MemoryReadinessStrategyChecks.run()
    print("Playback cache memory-readiness strategy checks passed")
  }
}
#else

final class PlaybackCacheLifecycleTests: XCTestCase {
  func testMemoryReadinessFailsClosedUntilFullBufferAndForwardPlayback() {
    MemoryReadinessStrategyChecks.run()
  }

  @MainActor
  func testTransportIntentIncludesAutomaticCommandsWithoutChangingUserIntent() {
    let player = NativePlaybackIntentPlayer()
    var active: [Bool] = []
    var seeks = 0
    var userCommands = 0
    player.onPlaybackActive = { active.append($0) }
    player.onSeek = { seeks += 1 }
    player.onUserCommand = { userCommands += 1 }
    player.automatically { player.play() }
    player.automatically { player.pause() }
    player.automatically { player.seek(to: .zero) }
    XCTAssertEqual(active, [true, false])
    XCTAssertEqual(seeks, 1)
    XCTAssertEqual(userCommands, 0)
    player.pause()
    XCTAssertEqual(active.last, false)
    XCTAssertEqual(userCommands, 1)
  }

  @MainActor
  func testControllerCacheCommandsCarryOwnerAndLateHiddenSnapshotIsIgnored() async throws {
    let suite = "starflow.cache.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let channel = CacheResolverTestChannel()
    let url = URL(fileURLWithPath: "/tmp/starflow-cache-fixture.mp4")
    let request = NativePlaybackRequest(url: url, title: "", headers: [:],
      playbackTargetJson: "{}", playbackItemKey: "fixture", seriesKey: "")
    let controller = NativePlaybackViewController(request: request, episodeQueue: nil,
      backgroundPlaybackEnabled: false, subtitlePreference: "off", defaultSubtitle: "",
      playbackStore: NativePlaybackMemoryStore(userDefaults: defaults),
      resolverSessionId: "cache-session", resolverChannel: channel)
    controller.loadViewIfNeeded()
    for _ in 0..<100 where controller.player == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let player = try XCTUnwrap(controller.player)
    let startupReports = channel.calls.filter { $0.0 == "setNativePlaybackBufferState" }
    XCTAssertFalse(startupReports.isEmpty)
    XCTAssertTrue(startupReports.allSatisfy { $0.1["memoryReady"] as? Bool == false })
    let beforePause = channel.calls.count
    player.pause()
    XCTAssertTrue(channel.calls.dropFirst(beforePause).contains {
      $0.0 == "setNativePlaybackBufferState" && $0.1["memoryReady"] as? Bool == false
    })
    let beforeSeek = channel.calls.count
    player.seek(to: CMTime(seconds: 3, preferredTimescale: 1), completionHandler: { _ in })
    XCTAssertTrue(channel.calls.dropFirst(beforeSeek).contains {
      $0.0 == "setNativePlaybackBufferState" && $0.1["memoryReady"] as? Bool == false
    })
    player.play()
    let controls = channel.calls.filter { $0.0 == "setNativePlaybackActive" || $0.0 == "cancelNativePlaybackReadAhead" }
    XCTAssertTrue(controls.contains { $0.0 == "cancelNativePlaybackReadAhead" })
    XCTAssertTrue(controls.contains { $0.1["active"] as? Bool == false })
    XCTAssertEqual(controls.last?.1["active"] as? Bool, true)
    XCTAssertTrue(controls.allSatisfy { $0.1["resolverSessionId"] as? String == "cache-session" &&
      $0.1["currentURL"] as? String == url.absoluteString })
    let generations = controls.compactMap { $0.1["generation"] as? Int }
    XCTAssertTrue(zip(generations, generations.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
    controller.viewDidAppear(false)
    let sample = try XCTUnwrap(channel.pendingSample)
    controller.viewWillDisappear(false)
    var response = sample.0
    response["ok"] = true
    response["storedBytes"] = 999_999
    sample.1?(response)
    let label = controller.contentOverlayView?.subviews.compactMap { $0 as? UILabel }
      .first { $0.accessibilityIdentifier == "starflow-native-cache-metrics" }
    XCTAssertTrue(try XCTUnwrap(label).isHidden)
    XCTAssertEqual(label?.text, "不可用 | --")
    controller.viewDidAppear(false)
    let resumed = try XCTUnwrap(channel.pendingSample)
    XCTAssertEqual(resumed.0["currentURL"] as? String, sample.0["currentURL"] as? String)
    XCTAssertGreaterThan(try XCTUnwrap(resumed.0["generation"] as? Int),
      try XCTUnwrap(sample.0["generation"] as? Int))
    sample.1?(nil)
    var currentResponse = resumed.0
    currentResponse["ok"] = true
    currentResponse["storedBytes"] = 4096
    resumed.1?(currentResponse)
    let currentText = label?.text
    XCTAssertNotEqual(currentText, "不可用 | --")
    // The old timeout and duplicate response must not erase the resumed sample.
    try await Task.sleep(nanoseconds: 2_100_000_000)
    sample.1?(response)
    XCTAssertEqual(label?.text, currentText)
    let beforeClose = channel.calls.count
    controller.dismiss(animated: false)
    XCTAssertNil(controller.player)
    XCTAssertTrue(channel.calls.dropFirst(beforeClose).contains {
      $0.0 == "setNativePlaybackBufferState" && $0.1["memoryReady"] as? Bool == false
    })
    let reports = channel.calls.filter { $0.0 == "setNativePlaybackBufferState" }
    XCTAssertTrue(reports.allSatisfy {
      $0.1["resolverSessionId"] as? String == "cache-session" &&
        $0.1["currentURL"] as? String == url.absoluteString
    })
    let reportGenerations = reports.compactMap { $0.1["generation"] as? Int }
    XCTAssertEqual(reportGenerations.count, reports.count)
    XCTAssertTrue(zip(reportGenerations, reportGenerations.dropFirst()).allSatisfy { $0 < $1 })
  }
}

private final class CacheResolverTestChannel: FlutterMethodChannel {
  var calls: [(String, [String: Any])] = []
  var pendingSample: ([String: Any], FlutterResult?)?
  override init() {
    super.init(name: "starflow.test.cache", binaryMessenger: CacheTestMessenger(),
      codec: FlutterStandardMethodCodec.sharedInstance())
  }
  override func invokeMethod(_ method: String, arguments: Any?) {
    calls.append((method, arguments as? [String: Any] ?? [:]))
  }
  override func invokeMethod(_ method: String, arguments: Any?, result callback: FlutterResult?) {
    let args = arguments as? [String: Any] ?? [:]
    calls.append((method, args))
    if method == "nativePlaybackCacheSnapshot" { pendingSample = (args, callback) }
    else { callback?(nil) }
  }
}

private final class CacheTestMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 0 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
#endif
