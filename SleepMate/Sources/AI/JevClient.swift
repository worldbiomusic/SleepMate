import Foundation
import Security

// Jev (TypeSafe AI) — 문장을 쓰지 않고 '판단'만 하는 빠른 모델 (System One API)
// POST {base}/v1/systemone   { model, state, questions } → { answers }
// 질문 3종: noul(예/아니오 확률) · choice(선택지 중 하나) · score(순서 있는 단계)
// 아이폰 12 Pro에서 못 쓰는 온디바이스 AI 대신 '작고 빠른 판단'을 맡는다.

/// 키체인 저장 (Claude 키와 같은 방식, 계정 이름만 다름)
enum SecretStore {
    static func load(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jeonghanlee.sleepmate.secrets",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let d = out as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty {
            return s
        }
        return UserDefaults.standard.string(forKey: "secret-fallback-" + account)
    }

    static func save(_ value: String, _ account: String) {
        delete(account)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jeonghanlee.sleepmate.secrets",
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(v.utf8),
        ]
        if SecItemAdd(attrs as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(v, forKey: "secret-fallback-" + account)
        }
    }

    static func delete(_ account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jeonghanlee.sleepmate.secrets",
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "secret-fallback-" + account)
    }
}

/// Jev 질문 (미리 세팅해 두는 '판단 문항')
enum JevQuestion {
    case noul(instructions: String, yes: String, no: String)
    case choice(instructions: String, options: [String: String])     // 값 → 설명
    case score(instructions: String, levels: [String])                 // 낮음 → 높음 순서

    var json: [String: Any] {
        switch self {
        case let .noul(ins, yes, no):
            return ["type": "noul", "instructions": ins, "criteria": ["true": yes, "false": no]]
        case let .choice(ins, options):
            return ["type": "choice", "instructions": ins, "criteria": options]
        case let .score(ins, levels):
            return ["type": "score", "instructions": ins, "criteria": levels]
        }
    }
}

/// Jev 답
struct JevAnswer: Equatable {
    var type: String
    var noul: Double?                 // '예'일 확률
    var choice: String?
    var confidence: Double?
    var score: Double?                // 0 ~ (단계 수-1) 사이 가중 위치
    var legend: [String: String] = [:]
    var probabilities: [String: Double] = [:]

    /// score 답을 가장 가까운 단계 이름으로
    var scoreLabel: String? {
        guard let s = score else { return nil }
        return legend[String(Int(s.rounded()))]
    }
}

struct JevConfig: Codable, Equatable {
    enum Provider: String, Codable, CaseIterable, Identifiable {
        case typesafe = "TypeSafe 직접"
        case openrouter = "OpenRouter"
        case custom = "직접 입력"
        var id: String { rawValue }

        var defaultURL: String {
            switch self {
            case .typesafe: return "https://api.typesafe.ai/v1/systemone"
            case .openrouter: return "https://openrouter.ai/api/v1/systemone"
            case .custom: return ""
            }
        }

        var defaultModel: String {
            switch self {
            case .typesafe: return "jev-latest"
            case .openrouter: return "typesafe/jev-1.13"
            case .custom: return "jev-latest"
            }
        }

        var keyHint: String {
            switch self {
            case .typesafe: return "console.typesafe.ai → Settings → Keys (대기자 명단 승인 필요)"
            case .openrouter: return "openrouter.ai → Keys (가입 후 바로 발급, 크레딧 충전)"
            case .custom: return "사용하는 게이트웨이의 키"
            }
        }
    }

    var provider: Provider = .openrouter
    var url: String = Provider.openrouter.defaultURL
    var model: String = Provider.openrouter.defaultModel
    // 판단 지점별 사용 여부
    var useWindDown = true      // 02 취침 개입 여부·말투
    var useTasks = true         // 01 노션 할 일 분류 (제목이 Jev로 전송됨)
    var useSound = true         // 02 수면 사운드 선택
    var useLLMGate = true       // 05 Claude 요약이 필요한 날인지

    private static let key = "jevConfig"
    static func load() -> JevConfig {
        guard let d = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(JevConfig.self, from: d) else { return JevConfig() }
        return c
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

enum JevError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Jev API 키가 없습니다."
        case .http(401, _): return "Jev 키가 올바르지 않습니다 (401)."
        case .http(402, _): return "크레딧이 부족합니다 (402)."
        case .http(429, _): return "요청이 너무 많습니다 (429)."
        case let .http(code, msg): return "Jev 오류 \(code): \(msg.prefix(120))"
        case .badResponse: return "Jev 응답을 해석하지 못했습니다."
        }
    }
}

enum JevClient {
    static let keyAccount = "jev-api-key"

    static var isConfigured: Bool { SecretStore.load(keyAccount) != nil }

    static func body(model: String, state: Any, questions: [String: JevQuestion]) -> [String: Any] {
        ["model": model, "state": state, "questions": questions.mapValues { $0.json }]
    }

    static func parse(_ data: Data) throws -> [String: JevAnswer] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let answers = obj["answers"] as? [String: Any] else { throw JevError.badResponse }
        var out: [String: JevAnswer] = [:]
        for (name, raw) in answers {
            guard let a = raw as? [String: Any] else { continue }
            func dbl(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
            var probs: [String: Double] = [:]
            for (k, v) in (a["probabilities"] as? [String: Any]) ?? [:] { probs[k] = dbl(v) ?? 0 }
            var legend: [String: String] = [:]
            for (k, v) in (a["legend"] as? [String: Any]) ?? [:] { legend[k] = "\(v)" }
            out[name] = JevAnswer(type: a["type"] as? String ?? "", noul: dbl(a["noul"]),
                                  choice: a["choice"] as? String, confidence: dbl(a["confidence"]),
                                  score: dbl(a["score"]), legend: legend, probabilities: probs)
        }
        return out
    }

    /// 한 번의 요청에 여러 질문을 함께 보낸다 (질문을 늘려도 응답 시간은 거의 같다)
    static func decide(state: Any, questions: [String: JevQuestion],
                       config: JevConfig = .load(), timeout: TimeInterval = 8) async throws -> [String: JevAnswer] {
        guard let key = SecretStore.load(keyAccount), let url = URL(string: config.url) else {
            throw JevError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(model: config.model, state: state,
                                                                       questions: questions))
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw JevError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return try parse(data)
    }
}
