import Foundation

@main
enum MemoryContractTest {
  static func main() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "test/fixtures/playback_memory_contract.json"))
    let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let cases = fixture["cases"] as! [[String: Any]]
    for c in cases {
      let position = (c["positionMs"] as! NSNumber).int64Value
      let duration = (c["durationMs"] as! NSNumber).int64Value
      let progress = (c["progress"] as! NSNumber).doubleValue
      precondition(PlaybackMemoryPolicy.resume(positionMs: position, durationMs: duration, progress: progress, completed: c["completed"] as! Bool) == (c["resumeMs"] as! NSNumber).int64Value)
      precondition(PlaybackMemoryPolicy.completed(positionMs: position, durationMs: duration, progress: progress) == c["isCompleted"] as! Bool)
    }
    let timestamps = fixture["timestamps"] as! [String]
    precondition(Set(timestamps.map(PlaybackMemoryPolicy.timestamp)).count == 1)
    precondition(PlaybackMemoryPolicy.nextTimestamp(now: timestamps[0], existing: timestamps) == fixture["nextTimestamp"] as! String)
    precondition(PlaybackPolicyValues.memoryRecentLimit == 20)
    print("Playback memory contract: \(cases.count) cases and timestamp rules passed")
  }
}
