import Foundation

enum PlaybackMemoryPolicy {
  static func resume(positionMs: Int64, durationMs: Int64, progress: Double, completed: Bool) -> Int64 {
    if completed || positionMs < Int64(PlaybackPolicyValues.memoryResumeMinimumMs)
      || (durationMs > 0 && durationMs - positionMs <= Int64(PlaybackPolicyValues.memoryResumeRemainingMs))
      || progress >= Double(PlaybackPolicyValues.memoryCompletedPermille) / 1000 { return 0 }
    return positionMs
  }

  static func completed(positionMs: Int64, durationMs: Int64, progress: Double) -> Bool {
    if durationMs <= 0 { return progress >= Double(PlaybackPolicyValues.memoryUnknownCompletedPermille) / 1000 }
    return progress >= Double(PlaybackPolicyValues.memoryCompletedPermille) / 1000
      || durationMs - positionMs <= Int64(PlaybackPolicyValues.memoryCompletedRemainingMs)
  }

  static func timestamp(_ raw: String) -> Int64 {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: raw)
    if date == nil {
      formatter.formatOptions = [.withInternetDateTime]
      date = formatter.date(from: raw)
    }
    if date == nil {
      let local = DateFormatter()
      local.locale = Locale(identifier: "en_US_POSIX")
      local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
      date = local.date(from: raw)
    }
    return Int64(((date?.timeIntervalSince1970 ?? 0) * 1000).rounded(.down))
  }

  static func nextTimestamp(now: String, existing: [String]) -> String {
    let next = existing.reduce(timestamp(now)) { max($0, timestamp($1) + 1) }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSince1970: Double(next) / 1000))
  }
}
