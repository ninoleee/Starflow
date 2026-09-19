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
    precondition(previous.currentEntry?.request.headers["X-Test"] == "123")
    precondition(NativeEpisodeQueue.fromJsonString(queue.toJsonString())?.currentEntry?.request.playbackItemKey == "2")
    precondition(NativeSubtitleSessionPreference(json: ["mode": "dual"]) == nil)
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
    print("Native playback models/storage: queue, subtitle, resume, pruning, cache invalidation passed")
  }
}
