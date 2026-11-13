import Foundation
import Security

// MARK: - API 키 저장 (키체인)

enum KeyStore {
    private static let service = "com.jeonghanlee.sleepmate.claude"
    private static let account = "anthropic-api-key"
    private static let fallbackKey = "claudeAPIKeyFallback"

    static func load() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        // 서명 방식에 따라 키체인을 못 쓰는 경우 대비
        return UserDefaults.standard.string(forKey: fallbackKey)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(key, forKey: fallbackKey)
            return false
        }
        return true
    }

    static func delete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }
}

// MARK: - 설정

struct CoachSettings: Codable, Equatable {
    var model: String = "claude-haiku-5-5"
    var autoClaude: Bool = true        // 새 기록을 가져오면 Claude로 자동 요약 (키가 있을 때)
    var autoSpeak: Bool = false        // 새 기록을 가져오면 자동으로 읽어주기
    var speechRate: Double = 0.5       // AVSpeechUtterance rate (0.0 ~ 1.0)

    struct ModelPreset: Hashable {
        let id: String
        let label: String
    }

    static let presets: [ModelPreset] = [
        ModelPreset(id: "claude-haiku-5-5", label: "Haiku 5.5 (빠르고 저렴)"),
        ModelPreset(id: "claude-sonnet-5-5", label: "Sonnet 5.5 (더 자세함)"),
    ]

    private static let key = "coachSettings"

    static func load() -> CoachSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(CoachSettings.self, from: d) else { return CoachSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

// MARK: - Claude Messages API

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "Claude API 키가 없습니다. 설정에서 입력해 주세요."
        case .http(401, _): return "API 키가 올바르지 않습니다 (401)."
        case .http(429, _): return "요청이 너무 많거나 크레딧이 부족합니다 (429)."
        case .http(529, _): return "Claude 서버가 혼잡합니다. 잠시 후 다시 시도하세요 (529)."
        case .http(let code, let msg): return "Claude 오류 \(code): \(msg)"
        case .badResponse(let s): return "응답을 해석하지 못했습니다: \(s.prefix(120))"
        }
    }
}

enum ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let systemPrompt = """
    당신은 'SleepMate'라는 수면 코치입니다. 사용자의 Apple Watch 수면 통계를 보고 한국어로 짧고 따뜻하게 요약하고, 오늘 하루 실천할 행동을 추천합니다.
    규칙:
    - 의료 진단을 하거나 질병을 추정하지 마세요. 원인을 단정하지 말고 "~일 수 있어요"처럼 말하세요.
    - 수치는 주어진 값만 사용하고 지어내지 마세요. 데이터가 부족하면 그렇다고 말하세요.
    - daysSinceLastNight가 2 이상이면 최근 기록이 오래됐다고 먼저 알려주세요.
    - 추천은 3개, 각 한 문장, 가능하면 구체적인 시각이나 시간(예: "오후 2시 이후", "20분")을 넣으세요.
    - speech는 아침에 음성으로 읽어줄 30초 이내 분량의 자연스러운 구어체입니다. 숫자는 "6시간 20분"처럼 읽기 쉽게, 기호·이모지·괄호는 쓰지 마세요.
    반드시 아래 JSON 객체 하나만 출력하세요 (설명이나 코드블록 없이):
    {"summary": "2~3문장 요약", "recommendations": ["추천1", "추천2", "추천3"], "speech": "음성 원고"}
    """

    static func userMessage(_ s: SleepStats, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E) a h:mm"
        var dict: [String: Any] = [
            "now": f.string(from: now),
            "night_wakeDate": Fmt.day.string(from: s.day),
            "daysSinceLastNight": s.daysSinceLastNight,
            "asleepMinutes": s.asleepMin,
            "hasStageData": s.hasStages,
            "deepMinutes": s.deepMin,
            "coreMinutes": s.coreMin,
            "remMinutes": s.remMin,
            "unspecifiedSleepMinutes": s.unspecifiedMin,
            "awakeMinutes": s.awakeMin,
            "deepPercent": s.deepPct,
            "remPercent": s.remPct,
            "nightsInLast7Days": s.nightsIn7,
        ]
        if let b = s.bedtime { dict["bedtime"] = Fmt.time.string(from: b) }
        if let w = s.wakeTime { dict["wakeTime"] = Fmt.time.string(from: w) }
        if let a = s.avg7AsleepMin { dict["avgAsleepMinutesLast7"] = a }
        if let a = s.avgBedtimeMin { dict["avgBedtimeLast7"] = SleepStats.clock(fromMinutesAfter18: a) }
        if let sp = s.bedtimeSpreadMin { dict["bedtimeStdDevMinutes"] = sp }

        let json = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "지난밤 수면 통계입니다. 요약과 오늘의 추천을 JSON으로 주세요.\n\n\(json)"
    }

    private struct Payload: Decodable {
        let summary: String
        let recommendations: [String]
        let speech: String
    }

    static func report(for s: SleepStats, model: String) async throws -> SleepReport {
        guard let key = KeyStore.load(), !key.isEmpty else { throw ClaudeError.noKey }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage(s)]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard code == 200 else {
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(code, msg)
        }
        let text = ((obj?["content"] as? [[String: Any]]) ?? [])
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()

        // 모델이 앞뒤에 글을 붙여도 JSON 부분만 꺼낸다.
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let jsonData = String(text[start...end]).data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: jsonData)
        else { throw ClaudeError.badResponse(text) }

        return SleepReport(day: s.day, source: .claude, model: model,
                           summary: p.summary, recommendations: p.recommendations, speech: p.speech)
    }
}
