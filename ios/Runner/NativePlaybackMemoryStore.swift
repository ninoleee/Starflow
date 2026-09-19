import Foundation

final class NativePlaybackMemoryStore {
  private static let storageKey = "flutter.starflow.playback.memory.v1"
  private static let recentEntryLimit = PlaybackPolicyValues.memoryRecentLimit

  private let userDefaults: UserDefaults
  private var cachedPlaybackRaw: String?
  private var cachedPlaybackSnapshot: [String: Any]?

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func loadResumePositionMs(itemKey: String) -> Int64 {
    guard let entry = loadPlaybackEntry(itemKey: itemKey) else {
      return 0
    }

    let positionMs = entry.int64Value(for: "positionMs")
    let durationMs = entry.int64Value(for: "durationMs")
    let progress = entry.doubleValue(for: "progress")
    let completed = entry.boolValue(for: "completed")

    return PlaybackMemoryPolicy.resume(positionMs: positionMs, durationMs: durationMs, progress: progress, completed: completed)
  }

  func savePlaybackEntry(
    targetJson: String,
    itemKey: String,
    seriesKey: String,
    positionMs: Int64,
    durationMs: Int64,
    updatedAt: String
  ) {
    guard !itemKey.isEmpty else {
      return
    }

    let clampedDuration = max(durationMs, 0)
    let safePosition = clampedDuration > 0
      ? min(max(positionMs, 0), clampedDuration)
      : max(positionMs, 0)
    let progress = clampedDuration <= 0
      ? 0.0
      : min(max(Double(safePosition) / Double(clampedDuration), 0.0), 1.0)
    let completed = PlaybackMemoryPolicy.completed(positionMs: safePosition, durationMs: clampedDuration, progress: progress)

    var snapshot = loadPlaybackSnapshot()
    var items = snapshot["items"] as? [String: Any] ?? [:]
    var series = snapshot["series"] as? [String: Any] ?? [:]
    let skipPreferences = snapshot["skipPreferences"] as? [String: Any] ?? [:]

    let targetObject = decodeTargetJson(targetJson)
    let itemType =
      (targetObject["itemType"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    let seriesTitle =
      (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed
      ?? (itemType == "series" ? ((targetObject["title"] as? String)?.nonEmptyTrimmed ?? "") : "")

    let entry: [String: Any] = [
      "key": itemKey,
      "target": targetObject,
      "updatedAt": PlaybackMemoryPolicy.nextTimestamp(now: updatedAt, existing:
        [items, series].flatMap { $0.values }.compactMap { ($0 as? [String: Any])?["updatedAt"] as? String }),
      "seriesKey": seriesKey,
      "seriesTitle": seriesTitle,
      "positionMs": NSNumber(value: safePosition),
      "durationMs": NSNumber(value: clampedDuration),
      "progress": NSNumber(value: progress),
      "completed": completed,
    ]

    items[itemKey] = entry
    pruneRecentItems(items: &items)
    if !seriesKey.isEmpty {
      series[seriesKey] = entry
    }

    snapshot["items"] = items
    snapshot["series"] = series
    snapshot["skipPreferences"] = skipPreferences
    savePlaybackSnapshot(snapshot)
  }

  func loadSubtitlePreference(
    seriesKey: String
  ) -> NativeSubtitleSessionPreference? {
    guard !seriesKey.isEmpty else {
      return nil
    }
    let snapshot = loadPlaybackSnapshot()
    let preferences = snapshot["subtitlePreferences"] as? [String: Any] ?? [:]
    guard let raw = preferences[seriesKey] as? [String: Any] else {
      return nil
    }
    return NativeSubtitleSessionPreference(json: raw)
  }

  func saveSubtitlePreference(
    _ preference: NativeSubtitleSessionPreference,
    seriesKey: String
  ) {
    guard !seriesKey.isEmpty else {
      return
    }
    var snapshot = loadPlaybackSnapshot()
    var preferences = snapshot["subtitlePreferences"] as? [String: Any] ?? [:]
    var value = preference.jsonObject
    value["seriesKey"] = seriesKey
    value["updatedAt"] = ISO8601DateFormatter().string(from: Date())
    preferences[seriesKey] = value
    snapshot["subtitlePreferences"] = preferences
    savePlaybackSnapshot(snapshot)
  }

  private func loadPlaybackEntry(itemKey: String) -> [String: Any]? {
    guard !itemKey.isEmpty else {
      return nil
    }
    let snapshot = loadPlaybackSnapshot()
    let items = snapshot["items"] as? [String: Any] ?? [:]
    return items[itemKey] as? [String: Any]
  }

  private func loadPlaybackSnapshot() -> [String: Any] {
    guard let raw = userDefaults.string(forKey: Self.storageKey) else {
      cachedPlaybackRaw = nil
      cachedPlaybackSnapshot = nil
      return [:]
    }
    if raw == cachedPlaybackRaw, let cached = cachedPlaybackSnapshot {
      return cached
    }
    guard let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    cachedPlaybackRaw = raw
    cachedPlaybackSnapshot = object
    return object
  }

  private func savePlaybackSnapshot(_ snapshot: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(snapshot),
      let data = try? JSONSerialization.data(withJSONObject: snapshot),
      let raw = String(data: data, encoding: .utf8)
    else {
      return
    }
    userDefaults.set(raw, forKey: Self.storageKey)
    cachedPlaybackRaw = raw
    cachedPlaybackSnapshot = snapshot
  }

  func decodeTargetJson(_ raw: String) -> [String: Any] {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }

  private func pruneRecentItems(items: inout [String: Any]) {
    guard items.count > Self.recentEntryLimit else {
      return
    }

    let sortedKeys = items
      .compactMap { key, value -> (String, Int64)? in
        guard let entry = value as? [String: Any] else {
          return nil
        }
        return (key, PlaybackMemoryPolicy.timestamp(entry["updatedAt"] as? String ?? ""))
      }
      .sorted { left, right in
        left.1 == right.1 ? left.0 > right.0 : left.1 > right.1
      }

    for entry in sortedKeys.dropFirst(Self.recentEntryLimit) {
      items.removeValue(forKey: entry.0)
    }
  }

}

private extension Dictionary where Key == String, Value == Any {
  func intValue(for key: String) -> Int {
    if let value = self[key] as? NSNumber {
      return value.intValue
    }
    if let value = self[key] as? String {
      return Int(value) ?? 0
    }
    return 0
  }

  func int64Value(for key: String) -> Int64 {
    if let value = self[key] as? NSNumber {
      return value.int64Value
    }
    if let value = self[key] as? String {
      return Int64(value) ?? 0
    }
    return 0
  }

  func doubleValue(for key: String) -> Double {
    if let value = self[key] as? NSNumber {
      return value.doubleValue
    }
    if let value = self[key] as? String {
      return Double(value) ?? 0
    }
    return 0
  }

  func boolValue(for key: String) -> Bool {
    if let value = self[key] as? Bool {
      return value
    }
    if let value = self[key] as? NSNumber {
      return value.boolValue
    }
    if let value = self[key] as? String {
      return NSString(string: value).boolValue
    }
    return false
  }
}
