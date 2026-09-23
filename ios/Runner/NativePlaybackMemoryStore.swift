import Foundation

final class NativePlaybackMemoryStore {
  private static let storageKey = "flutter.starflow.playback.memory.v2"
  private static let recentEntryLimit = PlaybackPolicyValues.memoryRecentLimit

  private let userDefaults: UserDefaults
  private var cachedPlaybackRaw: String?
  private var cachedPlaybackSnapshot: [String: Any]?
  private var maximumTimestamp: Int64 = 0
  private static let sharedStorageQueue = DispatchQueue(label: "starflow.playback-memory", qos: .utility)
  private var storageQueue: DispatchQueue { Self.sharedStorageQueue }
  private let pendingLock = NSLock()
  private var pendingProgress: [String: () -> Void] = [:]
  private var pendingTokens: [String: UUID] = [:]

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  static func readShared(userDefaults: UserDefaults = .standard,
    completion: @escaping (String?) -> Void) {
    sharedStorageQueue.async {
      let raw = userDefaults.string(forKey: storageKey)
      DispatchQueue.main.async { completion(raw) }
    }
  }

  static func compareAndSetShared(expected: String?, value: String?,
    userDefaults: UserDefaults = .standard, completion: @escaping (Bool) -> Void) {
    sharedStorageQueue.async {
      let accepted = userDefaults.string(forKey: storageKey) == expected
      if accepted {
        if let value { userDefaults.set(value, forKey: storageKey) }
        else { userDefaults.removeObject(forKey: storageKey) }
      }
      DispatchQueue.main.async { completion(accepted) }
    }
  }

  func loadResumePositionMs(itemKey: String) -> Int64 {
    storageQueue.sync { loadResumePositionNow(itemKey: itemKey) }
  }

  private func loadResumePositionNow(itemKey: String) -> Int64 {
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
    storageQueue.sync {
      savePlaybackEntryNow(targetJson: targetJson, itemKey: itemKey, seriesKey: seriesKey,
        positionMs: positionMs, durationMs: durationMs, updatedAt: updatedAt)
    }
  }

  func enqueuePlaybackEntry(
    targetJson: String, itemKey: String, seriesKey: String,
    positionMs: Int64, durationMs: Int64, updatedAt: String, final: Bool = false
  ) {
    let operation = { [self] in
      savePlaybackEntryNow(targetJson: targetJson, itemKey: itemKey, seriesKey: seriesKey,
        positionMs: positionMs, durationMs: durationMs, updatedAt: updatedAt)
    }
    pendingLock.lock()
    if final {
      // A final save is an ordering barrier and is never replaced by a tick.
      pendingProgress.removeValue(forKey: itemKey)
      pendingTokens.removeValue(forKey: itemKey)
      storageQueue.async(execute: operation)
    } else {
      let alreadyQueued = pendingProgress[itemKey] != nil
      pendingProgress[itemKey] = operation
      if !alreadyQueued {
        let token = UUID()
        pendingTokens[itemKey] = token
        storageQueue.async { [self] in
          pendingLock.lock()
          guard pendingTokens[itemKey] == token else {
            pendingLock.unlock()
            return
          }
          pendingTokens.removeValue(forKey: itemKey)
          let next = pendingProgress.removeValue(forKey: itemKey)
          pendingLock.unlock()
          next?()
        }
      }
    }
    pendingLock.unlock()
  }

  func flush(completion: @escaping () -> Void) {
    storageQueue.async { DispatchQueue.main.async(execute: completion) }
  }

  func preparePlayback(itemKey: String, seriesKey: String,
    completion: @escaping (Int64, NativeSubtitleSessionPreference?) -> Void) {
    storageQueue.async { [self] in
      let position = loadResumePositionNow(itemKey: itemKey)
      let subtitle = loadSubtitlePreferenceNow(seriesKey: seriesKey)
      DispatchQueue.main.async { completion(position, subtitle) }
    }
  }

  private func savePlaybackEntryNow(
    targetJson: String, itemKey: String, seriesKey: String,
    positionMs: Int64, durationMs: Int64, updatedAt: String
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

    var targetObject = decodeTargetJson(targetJson)
    if targetObject["sourceKind"] as? String == "fntv" {
      if !(targetObject["fntvSessionLink"] as? String ?? "").isEmpty {
        targetObject["preferredPlaybackQualityIndex"] = 0
        targetObject["streamUrl"] = ""
        targetObject["headers"] = [String: String]()
      }
      targetObject["fntvSessionLink"] = ""
      targetObject["fntvStartPositionMs"] = 0
    }
    let itemType =
      (targetObject["itemType"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    let seriesTitle =
      (targetObject["seriesTitle"] as? String)?.nonEmptyTrimmed
      ?? (itemType == "series" ? ((targetObject["title"] as? String)?.nonEmptyTrimmed ?? "") : "")

    maximumTimestamp = max(PlaybackMemoryPolicy.timestamp(updatedAt), maximumTimestamp + 1)
    let entry: [String: Any] = [
      "key": itemKey,
      "target": targetObject,
      "updatedAt": PlaybackMemoryPolicy.formatTimestamp(maximumTimestamp),
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
    storageQueue.sync { loadSubtitlePreferenceNow(seriesKey: seriesKey) }
  }

  private func loadSubtitlePreferenceNow(seriesKey: String) -> NativeSubtitleSessionPreference? {
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
    storageQueue.async { [self] in saveSubtitlePreferenceNow(preference, seriesKey: seriesKey) }
  }

  private func saveSubtitlePreferenceNow(_ preference: NativeSubtitleSessionPreference, seriesKey: String) {
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
      maximumTimestamp = 0
      return [:]
    }
    if raw == cachedPlaybackRaw, let cached = cachedPlaybackSnapshot {
      return cached
    }
    guard let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      cachedPlaybackRaw = nil
      cachedPlaybackSnapshot = nil
      maximumTimestamp = 0
      return [:]
    }
    cachedPlaybackRaw = raw
    cachedPlaybackSnapshot = object
    maximumTimestamp = ["items", "series"].flatMap {
      (object[$0] as? [String: Any] ?? [:]).values
    }.compactMap { ($0 as? [String: Any])?["updatedAt"] as? String }
      .map(PlaybackMemoryPolicy.timestamp).max() ?? 0
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
