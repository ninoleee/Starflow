import Foundation

enum NativeSubtitleLanguagePolicy {
  static func canonical(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .replacingOccurrences(of: "_", with: "-")
    switch value {
    case "", "und", "zxx", "null", "unknown": return ""
    case "english", "eng": return "en"
    case "japanese", "jp", "jpn": return "ja"
    case "korean", "kr", "kor": return "ko"
    case "chinese", "ch", "chi", "zho": return "zh"
    case "zh-hans", "zh-sg", "chs", "chn", "cn", "sc", "gb": return "zh-cn"
    case "zh-hant", "zh-hk", "zh-mo", "cht", "tc", "big5": return "zh-tw"
    default: return value
    }
  }

  static func matches(language: String, label: String, preference: String) -> Bool {
    let actual = canonical(language)
    let preferred = canonical(preference)
    guard !preferred.isEmpty else { return false }
    if !actual.isEmpty {
      if actual == preferred { return true }
      let root = actual.split(separator: "-").first
      if root == preferred.split(separator: "-").first,
        root != "zh" || actual == "zh" || preferred == "zh" { return true }
    }
    return tokens(preferred).contains { contains(label, token: $0) }
  }

  static func contains(_ label: String, token: String) -> Bool {
    let text = label.lowercased()
    if token.unicodeScalars.allSatisfy({ $0.isASCII }) {
      let normalized = text.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
      return (" " + normalized + " ").contains(" " + token + " ")
    }
    return text.contains(token)
  }

  private static func tokens(_ language: String) -> [String] {
    switch language {
    case "zh-cn": return ["zh cn", "zh hans", "zhcn", "zhhans", "chs", "chn", "chi", "zho", "cn", "sc", "简体", "簡體", "简中"]
    case "zh-tw": return ["zh tw", "zh hant", "zhtw", "zhhant", "cht", "chi", "zho", "tc", "big5", "繁体", "繁體", "繁中"]
    case "zh": return ["zh", "chinese", "中文", "国语", "國語"]
    case "en": return ["en", "english", "eng", "英语", "英語", "英文", "英字", "中英"]
    case "ja": return ["ja", "japanese", "jp", "jpn", "日语", "日語", "日文", "日字", "日本語"]
    case "ko": return ["ko", "korean", "kr", "kor", "韩语", "韓語", "한국어"]
    default: return [language.replacingOccurrences(of: "-", with: " ")]
    }
  }
}
