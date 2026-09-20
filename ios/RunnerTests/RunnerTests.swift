import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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

  func testStoreReadsExternalChangesAndClear() {
    let suite = "starflow.runner.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = NativePlaybackMemoryStore(userDefaults: defaults)
    store.savePlaybackEntry(targetJson: "{}", itemKey: "item", seriesKey: "series",
      positionMs: 30_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z")
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 30_000)
    let key = "flutter.starflow.playback.memory.v1"
    defaults.set(#"{"items":{"item":{"positionMs":20000,"durationMs":100000,"progress":0.2,"completed":false}}}"#, forKey: key)
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 20_000)
    defaults.removeObject(forKey: key)
    XCTAssertEqual(store.loadResumePositionMs(itemKey: "item"), 0)
  }

}
