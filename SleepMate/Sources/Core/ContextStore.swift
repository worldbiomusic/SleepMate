import Foundation
import Observation

// 계획서의 Context 3종
//  - 장기 Context: 목표 수면 시간, 평소 취침 목표, 준비 시간, 선호도 … (UserProfile)
//  - 일간 Context: 오늘의 피로도·기분·화면 사용량 … (DailyContext)
//  - 실시간 Context: 현재 시각, 다음 일정, 취침까지 남은 시간 … (계산값, RealtimeContext)

enum AlarmStyle: String, Codable, CaseIterable, Identifiable {
    case soundAndVibration = "소리 + 진동"
    case vibrationOnly = "진동만"
    case soundOnly = "소리만"
    var id: String { rawValue }
}

enum Mood: String, Codable, CaseIterable, Identifiable {
    case good = "좋음"
    case calm = "평온"
    case tired = "피곤"
    case stressed = "스트레스"
    case anxious = "불안"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .good: return "😊"
        case .calm: return "😌"
        case .tired: return "🥱"
        case .stressed: return "😣"
        case .anxious: return "😟"
        }
    }
}

/// 장기 Context (설정 탭에서 수정)
struct UserProfile: Codable, Equatable {
    var goalSleepMinutes = 450          // 목표 수면 7시간 30분
    var bedtimeMinutes = 23 * 60 + 30   // 취침 목표 23:30 (자정 기준 분)
    var prepMinutes = 60                // 기상 후 준비 시간
    var commuteMinutes = 30             // 이동 시간
    var earliestWakeMinutes = 6 * 60    // 이보다 일찍 깨우지 않음
    var defaultWakeMinutes = 7 * 60     // 일정 없을 때 기상
    var windDownLeadMinutes = 90        // 취침 준비 알림 시작 (취침 N분 전)
    var screenGoal = 50                 // 취침 전 화면 목표 (예: 쇼츠 개수)
    var screenUnit = "개"
    var notifyWindDown = true
    var maxEveningNotifications = 3     // GUARD: 저녁 알림 최대 횟수
    var alarmStyle: AlarmStyle = .soundAndVibration
    var alarmSoundName = "기본"
    var musicPreference = "잔잔한 피아노"
    var fixedKeywords = ["수업", "강의", "회의", "미팅", "약속", "이동", "시험", "출근", "면접", "class", "meeting"]
}

/// 일간 Context (매일 새로 시작)
struct DailyContext: Codable, Equatable {
    var date: Date
    var fatigue: Int?        // 1(개운함) ~ 5(매우 피곤)
    var mood: Mood?
    var screenCount = 0      // 취침 전 화면 사용 기록 (직접 입력/알림 버튼)
    var stoppedScreen = false
    var note = ""
}

enum FeedbackResponse: String, Codable {
    case helpful = "도움 됐어요"
    case later = "나중에"
    case skip = "건너뛰기"
    case accepted = "적용"
    case rejected = "거절"

    var isPositive: Bool { self == .helpful || self == .accepted }
}

struct FeedbackEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var scenario: String       // "01", "02", "04", "05"
    var itemKey: String        // 추천 종류 키 (같은 추천의 반응을 모아 다음 추천에 반영)
    var itemTitle: String
    var response: FeedbackResponse
}

/// 실시간 Context (저장하지 않고 매번 계산)
struct RealtimeContext {
    let now: Date
    let minutesToBedtime: Int
    let nextEvent: PlanItem?

    init(now: Date = Date(), profile: UserProfile, todayItems: [PlanItem], calendar: Calendar = .current) {
        self.now = now
        let mins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var diff = profile.bedtimeMinutes - mins
        if diff < -6 * 60 { diff += 1440 }      // 새벽이면 다음 취침까지
        minutesToBedtime = diff
        nextEvent = todayItems.filter { !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }
}

@MainActor
@Observable
final class ContextStore {
    private struct Saved: Codable {
        var profile: UserProfile
        var today: DailyContext
        var history: [DailyContext]
        var feedback: [FeedbackEntry]
    }

    var profile = UserProfile()
    var today = DailyContext(date: Calendar.current.startOfDay(for: Date()))
    var history: [DailyContext] = []           // 지난 일간 Context (최근 30일)
    var feedback: [FeedbackEntry] = []

    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("context.json")
    }

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            profile = s.profile
            today = s.today
            history = s.history
            feedback = s.feedback
        }
        rollOverIfNeeded()
        syncScreenCountFromNotifications()
    }

    /// 날짜가 바뀌면 오늘 Context를 기록으로 넘기고 새로 시작
    func rollOverIfNeeded(now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        guard today.date != day else { return }
        history.insert(today, at: 0)
        history = Array(history.prefix(30))
        today = DailyContext(date: day)
        save()
    }

    func save() {
        let s = Saved(profile: profile, today: today, history: history, feedback: Array(feedback.suffix(500)))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(s).write(to: url, options: .atomic)
        } catch {
            AppLog.shared.add("Context 저장 실패: \(error)")
        }
    }

    // MARK: 피드백

    func record(scenario: String, key: String, title: String, response: FeedbackResponse) {
        feedback.append(FeedbackEntry(scenario: scenario, itemKey: key, itemTitle: title, response: response))
        AgentLog.shared.add(event: "피드백", path: .rule, action: "\(title) → \(response.rawValue)", guardNote: nil)
        save()
    }

    /// 오늘 이 추천에 대해 남긴 마지막 반응
    func todayResponse(for key: String) -> FeedbackResponse? {
        let day = Calendar.current.startOfDay(for: Date())
        return feedback.last { $0.itemKey == key && $0.date >= day }?.response
    }

    /// 최근 14일 동안 같은 추천을 2번 이상 건너뛰었으면 우선순위를 낮춘다 (개인화의 첫 단계)
    func isOftenSkipped(_ key: String) -> Bool {
        let since = Date().addingTimeInterval(-14 * 86400)
        return feedback.filter { $0.itemKey == key && $0.date >= since && $0.response == .skip }.count >= 2
    }

    // MARK: 화면 사용 (알림 버튼에서 앱이 꺼진 상태로도 기록되도록 UserDefaults 공유)

    nonisolated static func screenKey(for day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "screenCount-" + f.string(from: day)
    }

    func syncScreenCountFromNotifications() {
        let key = Self.screenKey(for: today.date)
        let v = UserDefaults.standard.integer(forKey: key)
        if v > today.screenCount { today.screenCount = v }
        if UserDefaults.standard.bool(forKey: key + "-stopped") { today.stoppedScreen = true }
    }

    func addScreen(_ n: Int) {
        rollOverIfNeeded()
        today.screenCount = max(0, today.screenCount + n)
        UserDefaults.standard.set(today.screenCount, forKey: Self.screenKey(for: today.date))
        save()
    }

    func stopScreen() {
        today.stoppedScreen = true
        UserDefaults.standard.set(true, forKey: Self.screenKey(for: today.date) + "-stopped")
        save()
    }

    func resetScreen() {
        today.screenCount = 0
        today.stoppedScreen = false
        UserDefaults.standard.set(0, forKey: Self.screenKey(for: today.date))
        UserDefaults.standard.set(false, forKey: Self.screenKey(for: today.date) + "-stopped")
        save()
    }

    // MARK: 데모 (CI 스크린샷용, 저장하지 않음)

    func seedDemo() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        today = DailyContext(date: todayStart, fatigue: 4, mood: .tired, screenCount: 38)
        history = [42, 65, 30, 55, 48, 71].enumerated().map { i, n in
            DailyContext(date: todayStart.addingTimeInterval(-Double(i + 1) * 86400), screenCount: n)
        }
        let samples: [(String, String, FeedbackResponse)] = [
            ("01", "light-walk", .helpful), ("01", "caffeine", .helpful), ("01", "meal", .later),
            ("01", "nap", .skip), ("01", "schedule-move", .accepted), ("02", "screen-stop", .accepted),
            ("02", "music", .accepted), ("02", "focus", .skip), ("04", "alarm", .accepted),
            ("05", "listen", .helpful), ("01", "break", .helpful), ("01", "bedtime", .later),
        ]
        feedback = samples.enumerated().map { i, t in
            FeedbackEntry(date: Date().addingTimeInterval(-Double(i) * 20000), scenario: t.0,
                          itemKey: t.1, itemTitle: t.1, response: t.2)
        }
        let log = AgentLog.shared
        log.add(.sleepImported, path: .rule, action: "새 기록 37개 병합")
        log.add(.morning, path: .llm, action: "Claude 요약 생성", guardNote: "수치만 전송")
        log.add(.planToday, path: .rule, action: "추천 6개 · 일정 조정안 2개")
        log.add(.windDown, path: .rule, action: "오후 10:00 ‘취침 준비 90분 전’", guardNote: "허용")
        log.add(.planAlarm, path: .rule, action: "시계 알람 07:30 요청", guardNote: "사용자 알람 우선")
    }

    // MARK: 평가 지표 (계획서: 추천 수락률 · 완료율 · 취침 규칙성 · 만족도)

    struct Metrics {
        let total: Int
        let positive: Int
        let skipped: Int
        let later: Int
        var acceptRate: Int { total == 0 ? 0 : positive * 100 / total }
    }

    func metrics(days: Int = 14) -> Metrics {
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        let list = feedback.filter { $0.date >= since }
        return Metrics(total: list.count,
                       positive: list.filter { $0.response.isPositive }.count,
                       skipped: list.filter { $0.response == .skip || $0.response == .rejected }.count,
                       later: list.filter { $0.response == .later }.count)
    }
}

// MARK: - 시각 유틸

enum Clock {
    /// 자정 기준 분 → "오후 11:30"
    static func text(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let h = m / 60, mm = m % 60
        let ampm = h < 12 ? "오전" : "오후"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%@ %d:%02d", ampm, h12, mm)
    }

    static func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// 분 값을 오늘 날짜의 Date로 (DatePicker 바인딩용)
    static func date(fromMinutes m: Int, on day: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(((m % 1440) + 1440) % 1440 * 60))
    }

    static func durationText(_ minutes: Int) -> String {
        Fmt.duration(TimeInterval(minutes * 60))
    }
}
