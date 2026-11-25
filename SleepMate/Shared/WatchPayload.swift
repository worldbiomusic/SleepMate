import Foundation

/// 아이폰 → 워치로 보내는 요약 (WatchConnectivity applicationContext)
/// 아이폰 앱과 워치 앱이 같이 쓰는 파일
struct WatchPayload: Codable, Equatable {
    var updatedAt: Date
    // 어젯밤
    var score: Int?
    var scoreLabel: String?
    var asleepText: String?
    var sleepNote: String?               // "최근 평균보다 42분 짧아요"
    // 오늘 밤
    var bedtimeMinutes: Int              // 목표 취침 (자정 기준 분)
    var windDownLeadMinutes: Int
    var eveningAppMinutes: Int
    var eveningLimitMinutes: Int
    var openApp: String?
    var stopped: Bool
    var nudge: String?                   // 지금 한마디 (없으면 nil)
    var learnedNote: String?             // "기억: 수요일 밤엔 늦게 자요"
    // 오늘 · 내일
    var recommendation: String?
    var wakeText: String?                // "07:10"
    var wakeReason: String?
    var mood: String?                    // 현재 기분 (rawValue)

    static let key = "payload"

    func encoded() -> [String: Any] {
        guard let d = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: d]
    }

    static func decode(_ dict: [String: Any]) -> WatchPayload? {
        guard let d = dict[key] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: d)
    }

    /// 지금 기준 취침까지 남은 분 (지난 경우 음수, 새벽은 전날 목표 기준)
    func minutesToBed(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let m = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var diff = bedtimeMinutes - m
        if diff > 18 * 60 { diff -= 1440 }
        if diff < -12 * 60 { diff += 1440 }
        return diff
    }

    static let sample = WatchPayload(
        updatedAt: Date(), score: 72, scoreLabel: "보통", asleepText: "6시간 10분",
        sleepNote: "최근 평균보다 40분 짧아요", bedtimeMinutes: 23 * 60 + 30, windDownLeadMinutes: 90,
        eveningAppMinutes: 25, eveningLimitMinutes: 20, openApp: "유튜브", stopped: false,
        nudge: "오늘 밤 한도를 넘었어요. 지금 멈추면 내일 아침이 가벼워져요.",
        learnedNote: "기억: 수요일 밤엔 평균 75분 늦게 자요", recommendation: "오후 2시 전 카페인 마무리",
        wakeText: "07:10", wakeReason: "‘AI융합연구’ 09:00 − 준비 60분 − 이동 50분", mood: "피곤")
}

/// 워치 → 아이폰 메시지
enum WatchCommand: String {
    case stop          // 오늘은 여기까지
    case add5          // +5분 기록
    case mood          // 기분 (value: rawValue)
    case refresh       // 최신 요약 요청

    static let key = "cmd"
    static let valueKey = "value"
}
