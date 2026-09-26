import Flutter
import AVFoundation
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor
  func testLateEpisodeResolverReleasesTargetAfterPauseSeekOrExit() async throws {
    for command in ["pause", "seek", "exit"] {
      let suite = "starflow.episode.tests.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let channel = PlaybackResolverTestChannel()
      let queue = NativeEpisodeQueue.fromJsonString(
        #"{"entries":[{"target":{"streamUrl":"file:///tmp/starflow-missing-first.mp4"},"playbackItemKey":"first"},{"target":{},"playbackItemKey":"second"}],"currentIndex":0}"#)!
      let controller = NativePlaybackViewController(request: queue.currentEntry!.request!,
        episodeQueue: queue, backgroundPlaybackEnabled: false, subtitlePreference: "off",
        defaultSubtitle: "", playbackStore: NativePlaybackMemoryStore(userDefaults: defaults),
        resolverSessionId: "test-session", resolverChannel: channel)
      controller.loadViewIfNeeded()
      for _ in 0..<100 where controller.player == nil {
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      let player = try XCTUnwrap(controller.player)
      let item = try XCTUnwrap(player.currentItem)
      NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
      let resolver = try XCTUnwrap(channel.pendingResolver)
      switch command {
      case "pause": player.pause()
      case "seek": player.seek(to: CMTime(seconds: 10, preferredTimescale: 1)) { _ in }
      default: controller.dismiss(animated: false)
      }
      let target = #"{"streamUrl":"file:///tmp/starflow-missing-second.mp4","sourceKind":"fntv","sessionId":"synthetic-late-session"}"#
      resolver(["ok": true, "playbackTargetJson": target, "playbackItemKey": "second"])
      XCTAssertEqual(channel.releasedTargets, [target], command)
      if command == "exit" {
        XCTAssertNil(controller.player)
        XCTAssertEqual(channel.closeCalls, 1)
      } else {
        XCTAssertTrue(controller.player === player, command)
        XCTAssertTrue(controller.player?.currentItem === item, command)
        XCTAssertEqual(channel.closeCalls, 0, "pause/seek must retain the active session")
      }
      controller.dismiss(animated: false)
      controller.viewDidDisappear(false)
      XCTAssertEqual(channel.closeCalls, 1, "exit cleanup must be idempotent")
    }
  }

  @MainActor
  func testExitInvalidatesPendingPlaybackPreparation() async throws {
    let suite = "starflow.exit.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let channel = PlaybackResolverTestChannel()
    let request = NativePlaybackRequest(url: URL(fileURLWithPath: "/tmp/starflow-missing.mp4"),
      title: "", headers: [:], playbackTargetJson: "{}", playbackItemKey: "first", seriesKey: "")
    var controller: NativePlaybackViewController? = NativePlaybackViewController(request: request,
      episodeQueue: nil, backgroundPlaybackEnabled: false, subtitlePreference: "off",
      defaultSubtitle: "", playbackStore: NativePlaybackMemoryStore(userDefaults: defaults),
      resolverSessionId: "test-session", resolverChannel: channel)
    controller?.loadViewIfNeeded()
    controller?.dismiss(animated: false)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertNil(controller?.player)
    controller = nil
    XCTAssertEqual(channel.closeCalls, 1)
  }

  @MainActor
  func testDeinitClosesResolverSessionWithoutViewDisappearance() {
    let suite = "starflow.deinit.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let channel = PlaybackResolverTestChannel()
    let request = NativePlaybackRequest(url: URL(fileURLWithPath: "/tmp/starflow-missing.mp4"),
      title: "", headers: [:], playbackTargetJson: "{}", playbackItemKey: "first", seriesKey: "")
    var controller: NativePlaybackViewController? = NativePlaybackViewController(request: request,
      episodeQueue: nil, backgroundPlaybackEnabled: false, subtitlePreference: "off",
      defaultSubtitle: "", playbackStore: NativePlaybackMemoryStore(userDefaults: defaults),
      resolverSessionId: "test-session", resolverChannel: channel)
    weak var releasedController = controller
    controller = nil
    XCTAssertNil(releasedController)
    XCTAssertEqual(channel.closeCalls, 1)
  }

  func testEpisodeQueueRoundTripAndBoundaries() {
    let raw = #"{"entries":[{"target":{"streamUrl":"https://example.test/1"},"playbackItemKey":"first"},{"target":{"streamUrl":"https://example.test/2"},"playbackItemKey":"second"}],"currentIndex":0}"#
    let queue = NativeEpisodeQueue.fromJsonString(raw)!
    XCTAssertFalse(queue.hasPrevious)
    XCTAssertNil(queue.moveToPrevious())
    let next = queue.moveToNext()!
    XCTAssertNil(next.moveToNext())
    XCTAssertEqual(NativeEpisodeQueue.fromJsonString(next.toJsonString())?.currentEntry?.request?.playbackItemKey, "second")
  }

  func testSubtitlePreferenceRoundTrip() {
    let preference = NativeSubtitleSessionPreference.single(
      NativeSubtitleTrackFingerprint(label: "English", language: "en", isForced: false))
    XCTAssertEqual(NativeSubtitleSessionPreference(json: preference.jsonObject), preference)
    XCTAssertEqual(NativeSubtitleSessionPreference(json: ["mode": "off"]), .off)
    XCTAssertNil(NativeSubtitleSessionPreference(json: ["mode": "dual"]))
  }

  func testExternalSubtitleParserSupportsSrtVttAndAss() throws {
    let srt = #"""
1
00:00:01,000 --> 00:00:03,500
Hello <i>world</i>
"""#.data(using: .utf8)!
    let srtTrack = try NativeExternalSubtitleParser.parse(data: srt, fileName: "sample.srt")
    XCTAssertEqual(srtTrack.format, "srt")
    XCTAssertEqual(srtTrack.cues, [NativeExternalSubtitleCue(start: 1, end: 3.5, text: "Hello world")])

    let vtt = #"""
WEBVTT

00:00:04.000 --> 00:00:06.000
VTT text
"""#.data(using: .utf8)!
    let vttTrack = try NativeExternalSubtitleParser.parse(data: vtt, fileName: "sample.vtt")
    XCTAssertEqual(vttTrack.cue(at: 4.5)?.text, "VTT text")

    let ass = #"""
[Script Info]
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:07.00,0:00:09.00,Default,,0,0,0,,Line 1\NLine 2
"""#.data(using: .utf8)!
    let assTrack = try NativeExternalSubtitleParser.parse(data: ass, fileName: "sample.ass")
    XCTAssertEqual(assTrack.cues.first?.text, "Line 1\nLine 2")
  }

  func testExternalSubtitleParserRejectsOversizedAndUnsupportedInput() {
    XCTAssertThrowsError(try NativeExternalSubtitleParser.parse(
      data: Data(repeating: 0, count: NativeExternalSubtitleParser.maxBytes + 1),
      fileName: "large.srt")) { error in
      XCTAssertEqual(error as? NativeExternalSubtitleError, .tooLarge)
    }
    XCTAssertThrowsError(try NativeExternalSubtitleParser.parse(
      data: Data("not a subtitle".utf8), fileName: "sample.txt")) { error in
      XCTAssertEqual(error as? NativeExternalSubtitleError, .unsupportedFormat)
    }
  }

  func testStoreReadsExternalChangesAndClear() {
    let suite = "starflow.runner.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = NativePlaybackMemoryStore(userDefaults: defaults)
    store.savePlaybackEntry(targetJson: "{}", itemKey: "item", seriesKey: "series",
      positionMs: 30_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z")
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 30_000)
    let key = "flutter.starflow.playback.memory.v2"
    defaults.set(#"{"items":{"item":{"positionMs":20000,"durationMs":100000,"progress":0.2,"completed":false}}}"#, forKey: key)
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 20_000)
    defaults.removeObject(forKey: key)
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 0)
  }

  @MainActor
  func testExternalSubtitleLateParseCannotMountAfterClearOrExit() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).srt")
    try "1\n00:00:01,000 --> 00:00:02,000\nTest".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    for close in [false, true] {
      let suite = "starflow.subtitle.tests.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let request = NativePlaybackRequest(url: URL(fileURLWithPath: "/tmp/video.mp4"),
        title: "", headers: [:], playbackTargetJson: "{}", playbackItemKey: "item", seriesKey: "")
      let controller = NativePlaybackViewController(request: request, episodeQueue: nil,
        backgroundPlaybackEnabled: false, subtitlePreference: "off", defaultSubtitle: "",
        playbackStore: NativePlaybackMemoryStore(userDefaults: defaults))
      let done = expectation(description: "stale subtitle rejected")
      controller.applyExternalSubtitlePath(file.path) { accepted in
        XCTAssertFalse(accepted)
        done.fulfill()
      }
      if close { controller.dismiss(animated: false) } else { controller.clearExternalSubtitle() }
      await fulfillment(of: [done], timeout: 3)
      XCTAssertNil(controller.externalSubtitleTrack)
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
  }

}

private final class PlaybackResolverTestChannel: FlutterMethodChannel {
  var pendingResolver: FlutterResult?
  var releasedTargets: [String] = []
  var closeCalls = 0

  override init() {
    super.init(name: "starflow.test.resolver", binaryMessenger: PlaybackTestMessenger(),
      codec: FlutterStandardMethodCodec.sharedInstance())
  }

  override func invokeMethod(_ method: String, arguments: Any?) {
    if method == "releaseNativeFntvPlayback",
      let arguments = arguments as? [String: Any],
      let target = arguments["playbackTargetJson"] as? String {
      releasedTargets.append(target)
    } else if method == "closeNativeFntvSession" {
      closeCalls += 1
    }
  }

  override func invokeMethod(_ method: String, arguments: Any?, result callback: FlutterResult?) {
    if method == "resolveNativePlaybackEpisode" {
      pendingResolver = callback
    } else {
      callback?(nil)
    }
  }
}

private final class PlaybackTestMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }
  func setMessageHandlerOnChannel(_ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 0 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
