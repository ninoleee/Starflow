import AVFoundation
import Foundation

struct NativePlaybackAccessLogSummary: CustomStringConvertible {
  let eventCount: Int
  let uri: String
  let serverAddress: String
  let playbackStartDateIso8601: String
  let observedBitrate: Double
  let indicatedBitrate: Double
  let switchBitrate: Double
  let transferDuration: Double
  let bytesTransferred: Int64
  let droppedVideoFrames: Int
  let stalls: Int
  let segmentsDownloadedDuration: Double

  var description: String {
    let uriValue = uri.isEmpty ? "-" : uri
    let hostValue = serverAddress.isEmpty ? "-" : serverAddress
    let startupValue = playbackStartDateIso8601.isEmpty ? "-" : playbackStartDateIso8601
    return
      "access(events=\(eventCount), host=\(hostValue), uri=\(uriValue), obsBitrate=\(observedBitrate), indBitrate=\(indicatedBitrate), switchBitrate=\(switchBitrate), bytes=\(bytesTransferred), transfer=\(transferDuration), dropped=\(droppedVideoFrames), stalls=\(stalls), segDur=\(segmentsDownloadedDuration), start=\(startupValue))"
  }

  var dictionary: [String: Any] {
    [
      "eventCount": eventCount,
      "uri": uri,
      "serverAddress": serverAddress,
      "playbackStartDateIso8601": playbackStartDateIso8601,
      "observedBitrate": observedBitrate,
      "indicatedBitrate": indicatedBitrate,
      "switchBitrate": switchBitrate,
      "transferDuration": transferDuration,
      "bytesTransferred": bytesTransferred,
      "droppedVideoFrames": droppedVideoFrames,
      "stalls": stalls,
      "segmentsDownloadedDuration": segmentsDownloadedDuration,
    ]
  }
}

struct NativePlaybackErrorLogSummary: CustomStringConvertible {
  let eventCount: Int
  let domain: String
  let statusCode: Int
  let comment: String
  let serverAddress: String
  let uri: String
  let dateIso8601: String

  var description: String {
    let domainValue = domain.isEmpty ? "-" : domain
    let commentValue = comment.isEmpty ? "-" : comment
    let uriValue = uri.isEmpty ? "-" : uri
    let hostValue = serverAddress.isEmpty ? "-" : serverAddress
    let dateValue = dateIso8601.isEmpty ? "-" : dateIso8601
    return
      "error(events=\(eventCount), domain=\(domainValue), code=\(statusCode), host=\(hostValue), uri=\(uriValue), date=\(dateValue), comment=\(commentValue))"
  }

  var dictionary: [String: Any] {
    [
      "eventCount": eventCount,
      "domain": domain,
      "statusCode": statusCode,
      "comment": comment,
      "serverAddress": serverAddress,
      "uri": uri,
      "dateIso8601": dateIso8601,
    ]
  }
}

struct NativePlaybackMetricsSnapshot: CustomStringConvertible {
  let startupStartedAtIso8601: String
  let firstFrameAtIso8601: String
  let startupLatencyMs: Int?
  let stallCount: Int
  let lastStallAtIso8601: String
  let timeControlStatus: String
  let waitingReason: String
  let isPlaybackLikelyToKeepUp: Bool
  let isPlaybackBufferEmpty: Bool
  let isPlaybackBufferFull: Bool
  let lastAccessLog: NativePlaybackAccessLogSummary?
  let lastErrorLog: NativePlaybackErrorLogSummary?

  var description: String {
    let startupValue = startupLatencyMs.map(String.init) ?? "-"
    let firstFrameValue = firstFrameAtIso8601.isEmpty ? "-" : firstFrameAtIso8601
    let stallTimeValue = lastStallAtIso8601.isEmpty ? "-" : lastStallAtIso8601
    let accessValue = lastAccessLog?.description ?? "access(-)"
    let errorValue = lastErrorLog?.description ?? "error(-)"
    return
      "metrics(startupMs=\(startupValue), firstFrameAt=\(firstFrameValue), stalls=\(stallCount), lastStallAt=\(stallTimeValue), timeControl=\(timeControlStatus), waitReason=\(waitingReason), likely=\(isPlaybackLikelyToKeepUp), empty=\(isPlaybackBufferEmpty), full=\(isPlaybackBufferFull), \(accessValue), \(errorValue))"
  }

  var dictionary: [String: Any] {
    var value: [String: Any] = [
      "startupStartedAtIso8601": startupStartedAtIso8601,
      "firstFrameAtIso8601": firstFrameAtIso8601,
      "stallCount": stallCount,
      "lastStallAtIso8601": lastStallAtIso8601,
      "timeControlStatus": timeControlStatus,
      "waitingReason": waitingReason,
      "isPlaybackLikelyToKeepUp": isPlaybackLikelyToKeepUp,
      "isPlaybackBufferEmpty": isPlaybackBufferEmpty,
      "isPlaybackBufferFull": isPlaybackBufferFull,
    ]
    if let startupLatencyMs {
      value["startupLatencyMs"] = startupLatencyMs
    }
    if let lastAccessLog {
      value["lastAccessLog"] = lastAccessLog.dictionary
    }
    if let lastErrorLog {
      value["lastErrorLog"] = lastErrorLog.dictionary
    }
    return value
  }
}

final class NativePlaybackMetricsTracker {
  private let notificationCenter: NotificationCenter
  private let now: () -> Date
  private let isoFormatter: ISO8601DateFormatter

  private var player: AVPlayer?
  private var item: AVPlayerItem?
  private var timeControlObservation: NSKeyValueObservation?
  private var itemObservers: [NSObjectProtocol] = []

  private var startupBeganAt: Date?
  private var firstFrameAt: Date?
  private var stallCount: Int = 0
  private var lastStallAt: Date?
  private var lastAccessLogSummary: NativePlaybackAccessLogSummary?
  private var lastErrorLogSummary: NativePlaybackErrorLogSummary?
  private var timeControlStatusLabel: String = "unknown"
  private var waitingReasonLabel: String = "none"
  private var isPlaybackLikelyToKeepUp = false
  private var isPlaybackBufferEmpty = false
  private var isPlaybackBufferFull = false

  init(
    notificationCenter: NotificationCenter = .default,
    now: @escaping () -> Date = Date.init
  ) {
    self.notificationCenter = notificationCenter
    self.now = now
    self.isoFormatter = ISO8601DateFormatter()
  }

  deinit {
    detach()
  }

  func reset() {
    startupBeganAt = nil
    firstFrameAt = nil
    stallCount = 0
    lastStallAt = nil
    lastAccessLogSummary = nil
    lastErrorLogSummary = nil
    timeControlStatusLabel = "unknown"
    waitingReasonLabel = "none"
    isPlaybackLikelyToKeepUp = false
    isPlaybackBufferEmpty = false
    isPlaybackBufferFull = false
  }

  func beginStartup(at date: Date = Date()) {
    startupBeganAt = date
    firstFrameAt = nil
  }

  func attach(player: AVPlayer, item: AVPlayerItem) {
    detach()
    self.player = player
    self.item = item
    beginStartup(at: now())
    refreshItemFlags(item: item)
    refreshAccessErrorLog(item: item)

    timeControlObservation = player.observe(
      \.timeControlStatus,
      options: [.initial, .new]
    ) { [weak self] player, _ in
      self?.handleTimeControlChange(player: player)
    }

    itemObservers.append(
      notificationCenter.addObserver(
        forName: .AVPlayerItemPlaybackStalled,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.recordStall()
      }
    )

    itemObservers.append(
      notificationCenter.addObserver(
        forName: .AVPlayerItemNewAccessLogEntry,
        object: item,
        queue: .main
      ) { [weak self] _ in
        guard let self, let item = self.item else {
          return
        }
        self.refreshAccessErrorLog(item: item)
      }
    )

    itemObservers.append(
      notificationCenter.addObserver(
        forName: .AVPlayerItemNewErrorLogEntry,
        object: item,
        queue: .main
      ) { [weak self] _ in
        guard let self, let item = self.item else {
          return
        }
        self.refreshAccessErrorLog(item: item)
      }
    )
  }

  func detach() {
    timeControlObservation = nil

    for observer in itemObservers {
      notificationCenter.removeObserver(observer)
    }
    itemObservers.removeAll()
    player = nil
    item = nil
  }

  func recordStall(at date: Date = Date()) {
    stallCount += 1
    lastStallAt = date
    if let item {
      refreshItemFlags(item: item)
      refreshAccessErrorLog(item: item)
    }
  }

  func markFirstFrameIfNeeded(at date: Date = Date()) {
    guard firstFrameAt == nil else {
      return
    }
    firstFrameAt = date
  }

  func refreshAccessErrorLog(item: AVPlayerItem? = nil) {
    guard let currentItem = item ?? self.item else {
      return
    }
    lastAccessLogSummary = Self.makeAccessLogSummary(item: currentItem, formatter: isoFormatter)
    lastErrorLogSummary = Self.makeErrorLogSummary(item: currentItem, formatter: isoFormatter)
  }

  func snapshot() -> NativePlaybackMetricsSnapshot {
    if let item {
      refreshItemFlags(item: item)
    }
    return NativePlaybackMetricsSnapshot(
      startupStartedAtIso8601: Self.isoString(startupBeganAt, formatter: isoFormatter),
      firstFrameAtIso8601: Self.isoString(firstFrameAt, formatter: isoFormatter),
      startupLatencyMs: calculateStartupLatencyMs(),
      stallCount: stallCount,
      lastStallAtIso8601: Self.isoString(lastStallAt, formatter: isoFormatter),
      timeControlStatus: timeControlStatusLabel,
      waitingReason: waitingReasonLabel,
      isPlaybackLikelyToKeepUp: isPlaybackLikelyToKeepUp,
      isPlaybackBufferEmpty: isPlaybackBufferEmpty,
      isPlaybackBufferFull: isPlaybackBufferFull,
      lastAccessLog: lastAccessLogSummary,
      lastErrorLog: lastErrorLogSummary
    )
  }

  func summaryLine() -> String {
    snapshot().description
  }

  static func makeAccessLogSummary(item: AVPlayerItem?) -> NativePlaybackAccessLogSummary? {
    makeAccessLogSummary(item: item, formatter: ISO8601DateFormatter())
  }

  static func makeErrorLogSummary(item: AVPlayerItem?) -> NativePlaybackErrorLogSummary? {
    makeErrorLogSummary(item: item, formatter: ISO8601DateFormatter())
  }

  private func handleTimeControlChange(player: AVPlayer) {
    timeControlStatusLabel = Self.describeTimeControlStatus(player.timeControlStatus)
    waitingReasonLabel = Self.describeWaitingReason(player.reasonForWaitingToPlay)

    if player.timeControlStatus == .playing {
      markFirstFrameIfNeeded(at: now())
    }
  }

  private func refreshItemFlags(item: AVPlayerItem) {
    isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
    isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
    isPlaybackBufferFull = item.isPlaybackBufferFull
  }

  private func calculateStartupLatencyMs() -> Int? {
    guard let startupBeganAt, let firstFrameAt else {
      return nil
    }
    return max(Int(firstFrameAt.timeIntervalSince(startupBeganAt) * 1000.0), 0)
  }

  private static func makeAccessLogSummary(
    item: AVPlayerItem?,
    formatter: ISO8601DateFormatter
  ) -> NativePlaybackAccessLogSummary? {
    guard let log = item?.accessLog(),
      let last = log.events.last
    else {
      return nil
    }

    let startIso = isoString(last.playbackStartDate, formatter: formatter)
    return NativePlaybackAccessLogSummary(
      eventCount: log.events.count,
      uri: last.uri ?? "",
      serverAddress: last.serverAddress ?? "",
      playbackStartDateIso8601: startIso,
      observedBitrate: round2(last.observedBitrate),
      indicatedBitrate: round2(last.indicatedBitrate),
      switchBitrate: round2(last.switchBitrate),
      transferDuration: round2(last.transferDuration),
      bytesTransferred: Int64(last.numberOfBytesTransferred),
      droppedVideoFrames: Int(last.numberOfDroppedVideoFrames),
      stalls: Int(last.numberOfStalls),
      segmentsDownloadedDuration: round2(last.segmentsDownloadedDuration)
    )
  }

  private static func makeErrorLogSummary(
    item: AVPlayerItem?,
    formatter: ISO8601DateFormatter
  ) -> NativePlaybackErrorLogSummary? {
    guard let log = item?.errorLog(),
      let last = log.events.last
    else {
      return nil
    }

    let dateIso = isoString(last.date, formatter: formatter)
    return NativePlaybackErrorLogSummary(
      eventCount: log.events.count,
      domain: last.errorDomain,
      statusCode: Int(last.errorStatusCode),
      comment: last.errorComment ?? "",
      serverAddress: last.serverAddress ?? "",
      uri: last.uri ?? "",
      dateIso8601: dateIso
    )
  }

  private static func round2(_ value: Double) -> Double {
    (value * 100.0).rounded() / 100.0
  }

  private static func isoString(_ value: Date?, formatter: ISO8601DateFormatter) -> String {
    guard let value else {
      return ""
    }
    return formatter.string(from: value)
  }

  private static func describeTimeControlStatus(_ value: AVPlayer.TimeControlStatus) -> String {
    switch value {
    case .paused:
      return "paused"
    case .waitingToPlayAtSpecifiedRate:
      return "waiting"
    case .playing:
      return "playing"
    @unknown default:
      return "unknown"
    }
  }

  private static func describeWaitingReason(_ value: AVPlayer.WaitingReason?) -> String {
    guard let value else {
      return "none"
    }
    return value.rawValue
  }
}
