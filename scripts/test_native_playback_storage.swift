import Foundation

// Compile with NativePlaybackModels/MemoryStore and PlaybackMemoryPolicy/PolicyValues.
@main
enum NativePlaybackStorageTest {
  static func main() throws {
    let suite = "starflow.playback.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "flutter.starflow.playback.memory.v1"
    let store = NativePlaybackMemoryStore(userDefaults: defaults)
    let target = #"{"streamUrl":"https://example.test/movie","title":"Example","itemType":"episode","allowResume":false}"#
    let request = NativePlaybackRequest(url: URL(string: "https://example.test/movie")!,
      title: "Example", headers: [:], playbackTargetJson: target,
      playbackItemKey: "item", seriesKey: "series")
    precondition(!request.allowsResume)
    precondition(NativePlaybackRequest(url: request.url, title: "", headers: [:],
      playbackTargetJson: "invalid", playbackItemKey: "", seriesKey: "").allowsResume)
    precondition(NativeEpisodeQueue.fromJsonString("invalid") == nil)
    precondition(NativeEpisodeQueue.fromJsonString(#"{"entries":[]}"#) == nil)
    let queue = NativeEpisodeQueue.fromJsonString(#"{"entries":[{"target":{"streamUrl":"https://example.test/1","headers":{"X-Test":123}},"playbackItemKey":"1"},{"target":{"streamUrl":"https://example.test/2"},"playbackItemKey":"2"}],"currentIndex":100}"#)!
    precondition(queue.currentIndex == 1 && queue.hasPrevious && !queue.hasNext)
    precondition(queue.moveToNext() == nil)
    let previous = queue.moveToPrevious()!
    precondition(!previous.hasPrevious && previous.hasNext)
    precondition(previous.currentEntry?.request?.headers["X-Test"] == "123")
    precondition(NativeEpisodeQueue.fromJsonString(queue.toJsonString())?.currentEntry?.request?.playbackItemKey == "2")
    precondition(NativeSubtitleSessionPreference(json: ["mode": "dual"]) == nil)
    let deferred = NativeEpisodeQueue.fromJsonString(#"{"entries":[{"target":{"streamUrl":""},"playbackItemKey":"unresolved"},{"target":{"streamUrl":"https://example.test/2"},"playbackItemKey":"resolved"}],"currentIndex":1}"#)!
    precondition(deferred.entries.count == 2 && deferred.currentIndex == 1)
    precondition(deferred.moveToPrevious()?.currentEntry?.request == nil)
    precondition(NativeEpisodeQueue.fromJsonString(deferred.toJsonString())?.entries.count == 2)
    let transportEntry = NativeEpisodeQueueEntry(json: [
      "target": ["streamUrl": "https://nas.test/movie.mp4", "headers": ["Authorization": "Basic synthetic"]],
      "playbackItemKey": "original-item", "seriesKey": "original-series",
      "transportUrl": "http://127.0.0.1:1234/playback-relay/random/media",
      "transportHeaders": [String: String](),
    ])!
    precondition(transportEntry.request?.url.host == "127.0.0.1")
    precondition(transportEntry.request?.headers.isEmpty == true)
    precondition(transportEntry.request?.playbackItemKey == "original-item")
    precondition(!transportEntry.playbackTargetJson.contains("127.0.0.1"))
    let originalEntry = NativeEpisodeQueueEntry(json: transportEntry.toJsonObject())!
    precondition(originalEntry.request?.url.host == "nas.test")
    precondition(originalEntry.request?.headers["Authorization"] == "Basic synthetic")
    precondition(NativeSubtitleTrackFingerprint(json: [:]) == nil)
    let preference = NativeSubtitleSessionPreference.single(
      NativeSubtitleTrackFingerprint(label: "English", language: "en", isForced: true))
    precondition(NativeSubtitleSessionPreference(json: preference.jsonObject) == preference)

    defaults.set(#"{"skipPreferences":{"series":{"introSeconds":42}},"unknownField":true}"#, forKey: key)
    store.saveSubtitlePreference(preference, seriesKey: "series")
    precondition(store.loadSubtitlePreference(seriesKey: "series") == preference)
    for index in 0..<25 {
      store.savePlaybackEntry(targetJson: target, itemKey: "item-\(index)", seriesKey: "series",
        positionMs: 30_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00.000Z")
    }
    let snapshot = try JSONSerialization.jsonObject(with: Data(defaults.string(forKey: key)!.utf8)) as! [String: Any]
    let items = snapshot["items"] as! [String: [String: Any]]
    precondition(items.count == PlaybackPolicyValues.memoryRecentLimit)
    precondition(items["item-0"] == nil && items["item-24"] != nil)
    precondition(Set(items.values.map { $0["updatedAt"] as! String }).count == items.count)
    precondition(snapshot["unknownField"] as? Bool == true)
    precondition((snapshot["skipPreferences"] as? [String: Any])?["series"] != nil)
    precondition(store.loadSubtitlePreference(seriesKey: "series") == preference)
    precondition(store.loadResumePositionMs(itemKey: "item-24") == 30_000)
    precondition(NativePlaybackMemoryStore(userDefaults: defaults).loadResumePositionMs(itemKey: "item-24") == 30_000)

    // Flutter can replace or clear the shared preference while this store lives.
    defaults.set(#"{"items":{"external":{"positionMs":"15000","durationMs":"100000","progress":"0.15","completed":"false"}}}"#, forKey: key)
    precondition(store.loadResumePositionMs(itemKey: "external") == 15_000)
    precondition(store.loadResumePositionMs(itemKey: "item-24") == 0)
    defaults.set("invalid", forKey: key)
    precondition(store.loadResumePositionMs(itemKey: "external") == 0)
    defaults.removeObject(forKey: key)
    precondition(store.loadResumePositionMs(itemKey: "external") == 0)
    store.saveSubtitlePreference(.off, seriesKey: "series")
    precondition(store.loadSubtitlePreference(seriesKey: "series") == .off)
    store.savePlaybackEntry(targetJson: target, itemKey: "completed", seriesKey: "",
      positionMs: 200_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z")
    precondition(store.loadResumePositionMs(itemKey: "completed") == 0)
    for position in 10...30 {
      store.enqueuePlaybackEntry(targetJson: target, itemKey: "queued", seriesKey: "queued-series",
        positionMs: Int64(position * 1000), durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z")
    }
    store.enqueuePlaybackEntry(targetJson: target, itemKey: "queued", seriesKey: "queued-series",
      positionMs: 40_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z", final: true)
    store.enqueuePlaybackEntry(targetJson: target, itemKey: "queued", seriesKey: "queued-series",
      positionMs: 50_000, durationMs: 100_000, updatedAt: "2026-09-20T00:00:00Z")
    precondition(store.loadResumePositionMs(itemKey: "queued") == 50_000)
    let stale = defaults.string(forKey: key)
    store.saveSubtitlePreference(.off, seriesKey: "changed-after-read")
    precondition(store.loadSubtitlePreference(seriesKey: "changed-after-read") == .off)
    var conflictResult: Bool?
    NativePlaybackMemoryStore.compareAndSetShared(expected: stale, value: nil,
      userDefaults: defaults) { conflictResult = $0 }
    waitUntil { conflictResult != nil }
    precondition(conflictResult == false)
    var clearResult: Bool?
    NativePlaybackMemoryStore.compareAndSetShared(expected: defaults.string(forKey: key),
      value: nil, userDefaults: defaults) { clearResult = $0 }
    waitUntil { clearResult != nil }
    precondition(clearResult == true)
    precondition(store.loadResumePositionMs(itemKey: "queued") == 0)
    precondition(store.loadSubtitlePreference(seriesKey: "changed-after-read") == nil)
    print("Native playback models/storage: queue, subtitle, resume, pruning, cache invalidation passed")
  }

  private static func waitUntil(_ done: () -> Bool) {
    let deadline = Date().addingTimeInterval(10)
    while !done() && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(done(), "Shared storage callback timed out")
  }
}
