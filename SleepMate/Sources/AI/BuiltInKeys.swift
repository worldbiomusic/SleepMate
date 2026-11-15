import Foundation

// 빌드에 포함되는 기본 API 키 (MVP용)
// 이 파일은 저장소에는 빈 값으로 들어 있고, GitHub Actions 빌드 때
// repository secrets(JEV_API_KEY, CLAUDE_API_KEY)로 덮어써진다. (.github/scripts/embed_keys.py)
// 키는 XOR로 섞어 넣어 IPA 안에서 문자열 그대로 보이지 않게 한다 (완전한 보호는 아님).
enum BuiltInKeys {
    static let salt: [UInt8] = []
    static let jevBytes: [UInt8] = []
    static let claudeBytes: [UInt8] = []
    static let jevProviderHint = ""     // "openrouter" | "typesafe" | ""

    private static func reveal(_ b: [UInt8]) -> String? {
        guard !b.isEmpty, !salt.isEmpty else { return nil }
        let out = b.enumerated().map { $0.element ^ salt[$0.offset % salt.count] }
        let s = String(decoding: out, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    static var jev: String? { reveal(jevBytes) }
    static var claude: String? { reveal(claudeBytes) }
}
