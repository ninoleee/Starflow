import Foundation

@main
struct SubtitleLanguageContractTest {
  static func main() throws {
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "test/fixtures/subtitle_language_contract.json"
    let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [[String: Any]]
    for row in rows {
      let text = row["text"] as! String
      let preference = row["preference"] as! String
      let expected = row["match"] as! Bool
      precondition(NativeSubtitleLanguagePolicy.matches(language: "", label: text, preference: preference) == expected,
        "Subtitle contract failed: \(text) / \(preference)")
    }
    print("Swift subtitle language contract: \(rows.count) passed")
  }
}
