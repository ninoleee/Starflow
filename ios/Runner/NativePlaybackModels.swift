import Foundation

struct NativePlaybackRequest {
  let url: URL
  let title: String
  let headers: [String: String]
  let playbackTargetJson: String
  let playbackItemKey: String
  let seriesKey: String

  var allowsResume: Bool {
    guard let data = playbackTargetJson.data(using: .utf8),
      let target = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return true
    }
    return target["allowResume"] as? Bool ?? true
  }
}

struct NativeEpisodeQueueEntry {
  let request: NativePlaybackRequest?
  let playbackTargetJson: String

  init?(json: [String: Any]) {
    let target = json["target"] as? [String: Any] ?? [:]
    let streamUrl = ((json["transportUrl"] ?? target["streamUrl"]) as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? ""
    let headers = ((json["transportHeaders"] ?? target["headers"]) as? [String: Any] ?? [:]).reduce(into: [String: String]()) {
      partialResult,
      item in
      partialResult[item.key] = "\(item.value)"
    }
    let targetData = (try? JSONSerialization.data(withJSONObject: target)) ?? Data("{}".utf8)
    playbackTargetJson = String(data: targetData, encoding: .utf8) ?? "{}"
    self.playbackItemKey = (json["playbackItemKey"] as? String)?.nonEmptyTrimmed ?? ""
    self.seriesKey = (json["seriesKey"] as? String)?.nonEmptyTrimmed ?? ""
    guard !playbackItemKey.isEmpty else { return nil }
    if let url = URL(string: streamUrl), url.scheme != nil {
      request = NativePlaybackRequest(
        url: url,
        title: (target["title"] as? String)?.nonEmptyTrimmed ?? "",
        headers: headers,
        playbackTargetJson: playbackTargetJson,
        playbackItemKey: playbackItemKey,
        seriesKey: seriesKey
      )
    } else {
      request = nil
    }
  }

  let playbackItemKey: String
  let seriesKey: String

  func toJsonObject() -> [String: Any] {
    return [
      "target": targetObject(),
      "playbackItemKey": playbackItemKey,
      "seriesKey": seriesKey,
    ]
  }

  private func targetObject() -> [String: Any] {
    guard let data = playbackTargetJson.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }
}

struct NativeEpisodeQueue {
  let entries: [NativeEpisodeQueueEntry]
  let currentIndex: Int

  var hasPrevious: Bool {
    currentIndex > 0 && currentIndex < entries.count
  }

  var hasNext: Bool {
    currentIndex >= 0 && currentIndex + 1 < entries.count
  }

  var currentEntry: NativeEpisodeQueueEntry? {
    guard currentIndex >= 0 && currentIndex < entries.count else {
      return nil
    }
    return entries[currentIndex]
  }

  func moveToNext() -> NativeEpisodeQueue? {
    guard hasNext else {
      return nil
    }
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex + 1)
  }

  func moveToPrevious() -> NativeEpisodeQueue? {
    guard hasPrevious else {
      return nil
    }
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex - 1)
  }

  func toJsonString() -> String {
    let object: [String: Any] = [
      "currentIndex": currentIndex,
      "entries": entries.map { $0.toJsonObject() },
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else {
      return ""
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func fromJsonString(_ raw: String) -> NativeEpisodeQueue? {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    let entryObjects = object["entries"] as? [[String: Any]] ?? []
    let entries = entryObjects.compactMap(NativeEpisodeQueueEntry.init)
    guard !entries.isEmpty else {
      return nil
    }
    let currentIndex = min(
      max((object["currentIndex"] as? NSNumber)?.intValue ?? 0, 0),
      entries.count - 1
    )
    return NativeEpisodeQueue(entries: entries, currentIndex: currentIndex)
  }
}

struct NativeSubtitleTrackFingerprint: Equatable {
  let label: String
  let language: String
  let isForced: Bool

  var jsonObject: [String: Any] {
    return [
      "label": label,
      "language": language,
      "isForced": isForced,
    ]
  }

  init(label: String, language: String, isForced: Bool) {
    self.label = label
    self.language = language
    self.isForced = isForced
  }

  init?(json: [String: Any]) {
    self.label = json["label"] as? String ?? ""
    self.language = json["language"] as? String ?? ""
    self.isForced = json["isForced"] as? Bool ?? false
    if label.isEmpty, language.isEmpty {
      return nil
    }
  }
}

enum NativeSubtitleSessionPreference: Equatable {
  case off
  case single(NativeSubtitleTrackFingerprint)

  var jsonObject: [String: Any] {
    switch self {
    case .off:
      return ["mode": "off"]
    case .single(let fingerprint):
      return ["mode": "single", "primary": fingerprint.jsonObject]
    }
  }

  init?(json: [String: Any]) {
    if json["mode"] as? String == "off" {
      self = .off
      return
    }
    if json["mode"] as? String == "dual" {
      return nil
    }
    guard let primary = json["primary"] as? [String: Any],
      let fingerprint = NativeSubtitleTrackFingerprint(json: primary)
    else {
      return nil
    }
    self = .single(fingerprint)
  }
}

extension String {
  var nonEmptyTrimmed: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
