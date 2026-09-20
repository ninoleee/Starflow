import Foundation

enum PlaybackMemoryPolicy {
  private static let formatterLock = NSLock()
  private static let fractionalFormatter: ISO8601DateFormatter = {
    let value = ISO8601DateFormatter()
    value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return value
  }()
  private static let secondsFormatter = ISO8601DateFormatter()
  private static let localFormatter: DateFormatter = {
    let value = DateFormatter()
    value.locale = Locale(identifier: "en_US_POSIX")
    value.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return value
  }()
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
    formatterLock.lock()
    defer { formatterLock.unlock() }
    let date = fractionalFormatter.date(from: raw)
      ?? secondsFormatter.date(from: raw) ?? localFormatter.date(from: raw)
    return Int64(((date?.timeIntervalSince1970 ?? 0) * 1000).rounded(.down))
  }

  static func nextTimestamp(now: String, existing: [String]) -> String {
    let next = existing.reduce(timestamp(now)) { max($0, timestamp($1) + 1) }
    return formatTimestamp(next)
  }

  static func formatTimestamp(_ milliseconds: Int64) -> String {
    formatterLock.lock()
    defer { formatterLock.unlock() }
    return fractionalFormatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
  }
}
