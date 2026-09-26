import Foundation
import CoreFoundation
#if canImport(UIKit)
import UIKit
#endif

struct NativeExternalSubtitleCue: Equatable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String
}

struct NativeExternalSubtitleTrack: Equatable {
  let format: String
  let displayName: String
  let cues: [NativeExternalSubtitleCue]
  private let maximumEnds: [TimeInterval]

  init(format: String, displayName: String, cues: [NativeExternalSubtitleCue]) {
    self.format = format
    self.displayName = displayName
    self.cues = cues.sorted { $0.start < $1.start }
    var maximum = -Double.infinity
    self.maximumEnds = self.cues.map { cue in
      maximum = max(maximum, cue.end)
      return maximum
    }
  }

  func cue(at time: TimeInterval) -> NativeExternalSubtitleCue? {
    guard time.isFinite else { return nil }
    var lower = 0
    var upper = cues.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if cues[middle].start <= time { lower = middle + 1 } else { upper = middle }
    }
    var index = lower - 1
    var active: [NativeExternalSubtitleCue] = []
    while index >= 0 && maximumEnds[index] > time {
      if cues[index].end > time { active.append(cues[index]) }
      index -= 1
    }
    guard let first = active.first else { return nil }
    return NativeExternalSubtitleCue(start: first.start, end: first.end,
      text: active.reversed().map(\.text).joined(separator: "\n"))
  }
}

enum NativeExternalSubtitleError: LocalizedError, Equatable {
  case tooLarge
  case unsupportedFormat
  case invalidEncoding
  case invalidContent

  var errorDescription: String? {
    switch self {
    case .tooLarge: return "字幕超过 16 MiB 限制"
    case .unsupportedFormat: return "仅支持 SRT、ASS、SSA 和 VTT 字幕"
    case .invalidEncoding: return "字幕编码无法识别"
    case .invalidContent: return "字幕没有可播放的文本内容"
    }
  }
}

enum NativeExternalSubtitleParser {
  static let maxBytes = 16 * 1024 * 1024
  static let supportedExtensions: Set<String> = ["srt", "ass", "ssa", "vtt"]

  static func parse(data: Data, fileName: String) throws -> NativeExternalSubtitleTrack {
    guard data.count <= maxBytes else { throw NativeExternalSubtitleError.tooLarge }
    let text = try decode(data)
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    let format = supportedExtensions.contains(ext) ? ext : detectFormat(text)
    let cues: [NativeExternalSubtitleCue]
    switch format {
    case "srt": cues = parseSrt(text)
    case "vtt": cues = parseVtt(text)
    case "ass", "ssa": cues = parseAss(text)
    default: throw NativeExternalSubtitleError.unsupportedFormat
    }
    let normalized = cues
      .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && !$0.text.isEmpty }
      .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    guard !normalized.isEmpty else { throw NativeExternalSubtitleError.invalidContent }
    guard normalized.count <= 100_000 else { throw NativeExternalSubtitleError.tooLarge }
    return NativeExternalSubtitleTrack(
      format: format,
      displayName: URL(fileURLWithPath: fileName).lastPathComponent,
      cues: normalized
    )
  }

  private static func decode(_ data: Data) throws -> String {
    if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
      guard let text = String(data: data, encoding: .utf16) else {
        throw NativeExternalSubtitleError.invalidEncoding
      }
      return text
    }
    if let text = String(data: data, encoding: .utf8) {
      return text.replacingOccurrences(of: "\u{FEFF}", with: "")
    }
    let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    if let text = String(data: data, encoding: gb18030) {
      return text
    }
    throw NativeExternalSubtitleError.invalidEncoding
  }

  static func discardOnlineDownload(path: String) {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    let root = caches.appendingPathComponent("starflow/online_subtitles")
      .resolvingSymlinksInPath().standardizedFileURL
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    let bucket = file.deletingLastPathComponent()
    guard bucket.deletingLastPathComponent() == root,
      bucket.lastPathComponent.hasPrefix("download-") else { return }
    try? FileManager.default.removeItem(at: bucket)
  }

  private static func detectFormat(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.uppercased().hasPrefix("WEBVTT") { return "vtt" }
    if trimmed.range(of: "^\\[Script Info\\]", options: .regularExpression) != nil {
      return "ass"
    }
    if trimmed.range(of: "-->.*[,\\.]\\d{3}", options: .regularExpression) != nil {
      return "srt"
    }
    return ""
  }

  private static func parseSrt(_ text: String) -> [NativeExternalSubtitleCue] {
    parseTimestampBlocks(text, allowArrowWithoutCueNumber: true)
  }

  private static func parseVtt(_ text: String) -> [NativeExternalSubtitleCue] {
    var body = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    if let firstLineEnd = body.firstIndex(of: "\n"),
      body[..<firstLineEnd].trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("WEBVTT")
    {
      body = String(body[body.index(after: firstLineEnd)...])
    }
    return parseTimestampBlocks(body, allowArrowWithoutCueNumber: true)
  }

  private static func parseTimestampBlocks(
    _ text: String,
    allowArrowWithoutCueNumber: Bool
  ) -> [NativeExternalSubtitleCue] {
    let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n\n")
    var result: [NativeExternalSubtitleCue] = []
    for block in blocks {
      let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
      if !allowArrowWithoutCueNumber && timingIndex != 0 { continue }
      let timing = lines[timingIndex].components(separatedBy: "-->")
      guard timing.count == 2,
        let start = parseTimestamp(timing[0].trimmingCharacters(in: .whitespaces)),
        let end = parseTimestamp(timing[1].split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "")
      else { continue }
      let body = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
      let cleaned = cleanText(body, ass: false)
      if !cleaned.isEmpty {
        result.append(NativeExternalSubtitleCue(start: start, end: end, text: cleaned))
      }
    }
    return result
  }

  private static func parseAss(_ text: String) -> [NativeExternalSubtitleCue] {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
    var startIndex: Int?
    var endIndex: Int?
    var textIndex: Int?
    var result: [NativeExternalSubtitleCue] = []
    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.lowercased().hasPrefix("format:") {
        let fields = line.dropFirst("format:".count).split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        startIndex = fields.firstIndex(of: "start")
        endIndex = fields.firstIndex(of: "end")
        textIndex = fields.firstIndex(of: "text")
        continue
      }
      guard line.lowercased().hasPrefix("dialogue:") else { continue }
      let payload = String(line.dropFirst("dialogue:".count)).trimmingCharacters(in: .whitespaces)
      let fields = payload.split(separator: ",", maxSplits: max((textIndex ?? 9), 9), omittingEmptySubsequences: false).map(String.init)
      let startField = startIndex ?? 1
      let endField = endIndex ?? 2
      let subtitleField = textIndex ?? 9
      guard fields.indices.contains(startField), fields.indices.contains(endField),
        fields.count > subtitleField,
        let start = parseAssTimestamp(fields[startField]),
        let end = parseAssTimestamp(fields[endField])
      else { continue }
      let body = fields.dropFirst(subtitleField).joined(separator: ",")
      let cleaned = cleanText(body, ass: true)
      if !cleaned.isEmpty {
        result.append(NativeExternalSubtitleCue(start: start, end: end, text: cleaned))
      }
    }
    return result
  }

  private static func parseTimestamp(_ raw: String) -> TimeInterval? {
    let normalized = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    let parts = normalized.split(separator: ":").map(String.init)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    let seconds = Double(parts.last ?? "")
    let minutes = Double(parts[parts.count - 2])
    let hours = parts.count == 3 ? Double(parts[0]) : 0
    guard let seconds, let minutes, let hours, seconds >= 0, seconds < 60,
      minutes >= 0, minutes < 60, hours >= 0 else { return nil }
    return hours * 3600 + minutes * 60 + seconds
  }

  private static func parseAssTimestamp(_ raw: String) -> TimeInterval? {
    return parseTimestamp(raw)
  }

  private static func cleanText(_ raw: String, ass: Bool) -> String {
    var text = raw
    if ass {
      if raw.range(of: #"\\p[1-9]"#, options: .regularExpression) != nil { return "" }
      text = text.replacingOccurrences(of: "\\N", with: "\n")
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\h", with: " ")
        .replacingOccurrences(of: "\\{", with: "{")
        .replacingOccurrences(of: "\\}", with: "}")
      text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
    }
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

final class NativeExternalSubtitleDownloader: NSObject, URLSessionDataDelegate {
  private var data = Data()
  private var completed = false
  private let completion: (Result<Data, Error>) -> Void
  private var session: URLSession?

  init(completion: @escaping (Result<Data, Error>) -> Void) {
    self.completion = completion
    super.init()
  }

  func start(request: URLRequest) -> URLSessionDataTask {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    self.session = session
    let task = session.dataTask(with: request)
    task.resume()
    return task
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      finish(.failure(NSError(domain: "StarflowSubtitle", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "字幕下载失败（HTTP \(http.statusCode)）"])))
      completionHandler(.cancel)
      return
    }
    if response.expectedContentLength > Int64(NativeExternalSubtitleParser.maxBytes) {
      finish(.failure(NativeExternalSubtitleError.tooLarge))
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard !completed else { return }
    if self.data.count + data.count > NativeExternalSubtitleParser.maxBytes {
      dataTask.cancel()
      finish(.failure(NativeExternalSubtitleError.tooLarge))
      return
    }
    self.data.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error, !completed {
      finish(.failure(error))
    } else if !completed {
      finish(.success(data))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) {
    guard let destination = request.url,
      destination.scheme == "https" || destination.scheme == "http" else {
      completionHandler(nil)
      return
    }
    let previous = response.url
    if previous?.scheme == "https" && destination.scheme != "https" {
      completionHandler(nil)
      return
    }
    if previous?.host != destination.host || previous?.scheme != destination.scheme
      || previous?.port != destination.port {
      completionHandler(URLRequest(url: destination))
    } else {
      completionHandler(request)
    }
  }

  func cancel() {
    session?.invalidateAndCancel()
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<Data, Error>) {
    guard !completed else { return }
    completed = true
    session?.finishTasksAndInvalidate()
    completion(result)
  }
}

#if canImport(UIKit)
final class NativeExternalSubtitleOverlay: UIView {
  private let label = UILabel()
  private var track: NativeExternalSubtitleTrack?
  private var pictureInPictureHidden = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textColor = .white
    label.backgroundColor = UIColor.black.withAlphaComponent(0.62)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 20, weight: .medium)
    label.layer.cornerRadius = 4
    label.layer.masksToBounds = true
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -62),
      label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
    ])
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setTrack(_ track: NativeExternalSubtitleTrack?) {
    self.track = track
    update(time: 0)
  }

  func update(time: TimeInterval) {
    guard let cue = track?.cue(at: time) else {
      label.text = nil
      isHidden = true
      return
    }
    label.text = "  \(cue.text)  "
    isHidden = pictureInPictureHidden
  }

  func setPictureInPictureHidden(_ hidden: Bool) {
    pictureInPictureHidden = hidden
    isHidden = hidden || label.text == nil
  }
}
#endif
