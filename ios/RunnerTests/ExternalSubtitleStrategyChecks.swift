import Foundation

@main
enum ExternalSubtitleStrategyChecks {
  static func main() throws {
    func parse(_ text: String, _ name: String) throws -> NativeExternalSubtitleTrack {
      try NativeExternalSubtitleParser.parse(data: Data(text.utf8), fileName: name)
    }
    let srt = try parse("1\n00:00:01,000 --> 00:00:03,500\nHello <i>world</i>\n\n2\n00:00:02,000 --> 00:00:04,000\nSecond", "test.srt")
    precondition(srt.cue(at: 0) == nil)
    precondition(srt.cue(at: 1)?.text == "Hello world")
    precondition(srt.cue(at: 2)?.text == "Hello world\nSecond")
    precondition(srt.cue(at: 3.5)?.text == "Second")
    precondition(srt.cue(at: 4) == nil)
    precondition(srt.cue(at: .nan) == nil)
    let vtt = try parse("WEBVTT\n\n00:01.000 --> 00:02.000 align:start\n&lt;Hi&gt; &amp; bye\n\n00:03.000 --> 00:04.000\nNext", "test.vtt")
    precondition(vtt.cues.count == 2)
    precondition(vtt.cue(at: 1)?.text == "<Hi> & bye")
    let ass = try parse("[Script Info]\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}One\\NTwo, three", "test.ass")
    precondition(ass.cue(at: 1)?.text == "One\nTwo, three")
    let utf16 = "1\n00:00:01,000 --> 00:00:02,000\nHello".data(using: .utf16)!
    let decoded = try NativeExternalSubtitleParser.parse(data: utf16, fileName: "test.srt")
    precondition(decoded.cues.count == 1)
    for (data, name) in [(Data("<html>login</html>".utf8), "test.srt"),
      (Data(repeating: 0, count: NativeExternalSubtitleParser.maxBytes + 1), "test.srt"),
      (Data("1\n00:99:01,000 --> 00:99:02,000\nWrong".utf8), "test.srt")] {
      do { _ = try NativeExternalSubtitleParser.parse(data: data, fileName: name); fatalError("accepted invalid input") }
      catch is NativeExternalSubtitleError {}
    }
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let bucket = caches.appendingPathComponent("starflow/online_subtitles/download-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
    let cached = bucket.appendingPathComponent("subtitle.srt")
    try Data("test".utf8).write(to: cached)
    NativeExternalSubtitleParser.discardOnlineDownload(path: cached.path)
    precondition(!FileManager.default.fileExists(atPath: bucket.path))
    let local = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).srt")
    try Data("keep".utf8).write(to: local)
    defer { try? FileManager.default.removeItem(at: local) }
    NativeExternalSubtitleParser.discardOnlineDownload(path: local.path)
    precondition(FileManager.default.fileExists(atPath: local.path))
    print("External subtitle strategy checks: 15 passed")
  }
}
