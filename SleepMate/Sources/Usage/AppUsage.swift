import Foundation
import Observation

// 앱 사용시간 (예: 유튜브를 '쇼츠 개수'가 아니라 '사용한 분'으로 판단)
//
// iOS에서 앱 사용시간을 직접 읽는 Screen Time API(Family Controls)는 유료 개발자 계정이 필요하다.
// 그래서 단축어 개인 자동화 "앱 → 열릴 때 / 닫힐 때"가 SleepMate의 App Intent를 부르도록 하고
// (SleepMate 화면은 열리지 않음), 열림~닫힘 사이를 사용시간으로 계산한다.
//  - 열릴 때: 오늘 남은 허용 시간을 계산해 '초과 시점'에 알림을 예약
//  - 닫힐 때: 예약 알림 취소, 사용시간 누적, 알림 뒤 얼마나 빨리 닫았는지(개입 결과)를 기억에 남김

struct AppSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var app: String
    var start: Date
    var end: Date?
    var manual = false              // 직접 기록(+5분)
    var alertAt: Date?              // 이 세션 중 초과 알림 예정/발송 시각
    var alertTone: String?          // 알림 말투 (gentle / firm)
    var alertKind: String?          // daily / evening

    /// 닫힘 기록이 없으면 최대 3시간까지만 센다 (잠금 등으로 닫힘을 놓친 경우)
    static let maxOpenMinutes = 180

    func endOrNow(_ now: Date) -> Date {
        let cap = start.addingTimeInterval(TimeInterval(Self.maxOpenMinutes * 60))
        return min(end ?? now, cap)
    }
}

struct AppLimit: Codable, Identifiable, Equatable {
    var app: String
    var dailyMinutes: Int
    var enabled = true
    var id: String { app }
}

struct UsageSettings: Codable, Equatable {
    var limits: [AppLimit] = [AppLimit(app: "YouTube", dailyMinutes: 60),
                              AppLimit(app: "Instagram", dailyMinutes: 40),
                              AppLimit(app: "TikTok", dailyMinutes: 30)]
    /// 취침 준비 시간(취침 N분 전부터) 동안 감시 앱 합계 한도
    var eveningLimitMinutes = 20
    /// 초과 뒤 다시 알려 주는 간격 (분)
    var repeatMinutes = 10
    var enabled = true
}

/// 계산은 모두 순수 함수 (셀프 테스트 대상)
enum UsageMath {
    static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// 한국어 앱 이름도 같은 앱으로 본다
    static func canonical(_ s: String) -> String {
        let n = norm(s)
        let aliases: [String: String] = ["유튜브": "youtube", "인스타그램": "instagram", "인스타": "instagram",
                                         "틱톡": "tiktok", "넷플릭스": "netflix", "카카오톡": "kakaotalk"]
        return aliases[n] ?? n
    }

    static func same(_ a: String, _ b: String) -> Bool { canonical(a) == canonical(b) }

    /// [from, to) 구간과 겹치는 사용 분
    static func minutes(_ sessions: [AppSession], app: String? = nil, from: Date, to: Date, now: Date) -> Int {
        var total: TimeInterval = 0
        for s in sessions where app == nil || same(s.app, app!) {
            let a = max(s.start, from)
            let b = min(s.endOrNow(now), to)
            if b > a { total += b.timeIntervalSince(a) }
        }
        return Int((total / 60).rounded())
    }

    static func today(_ sessions: [AppSession], app: String?, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        return minutes(sessions, app: app, from: start, to: start.addingTimeInterval(86400), now: now)
    }

    /// 취침 준비 구간 시작 (취침 목표 - lead). 새벽이면 전날 저녁 기준.
    static func eveningStart(now: Date, profile: UserProfile, calendar: Calendar = .current) -> Date {
        let rt = RealtimeContext(now: now, profile: profile, todayItems: [], calendar: calendar)
        let bed = now.addingTimeInterval(TimeInterval(rt.minutesToBedtime * 60))
        return bed.addingTimeInterval(TimeInterval(-profile.windDownLeadMinutes * 60))
    }

    /// 오늘 밤(취침 준비 구간 이후) 감시 앱 합계 사용 분
    static func evening(_ sessions: [AppSession], watched: [String], now: Date, profile: UserProfile) -> Int {
        let from = eveningStart(now: now, profile: profile)
        guard now > from else { return 0 }
        return sessions.filter { s in s.manual || watched.contains { same($0, s.app) } }
            .reduce(0) { $0 + minutes([$1], from: from, to: now, now: now) }
    }

    struct Alert: Equatable {
        enum Kind: String { case daily, evening }
        var kind: Kind
        var at: Date
        var title: String
        var body: String
    }

    /// 앱이 열린 순간: 언제 '초과'가 되는지 계산해 알림 시점을 정한다 (가장 이른 것 + 반복 2번)
    static func alerts(app: String, now: Date, sessions: [AppSession], settings: UsageSettings,
                       profile: UserProfile, preferFirm: Bool) -> [Alert] {
        guard settings.enabled, let limit = settings.limits.first(where: { same($0.app, app) && $0.enabled })
        else { return [] }
        let usedToday = today(sessions, app: app, now: now)
        let watched = settings.limits.filter(\.enabled).map(\.app)
        let usedEvening = evening(sessions, watched: watched, now: now, profile: profile)
        let eveningStart = eveningStart(now: now, profile: profile)
        let rt = RealtimeContext(now: now, profile: profile, todayItems: [])

        var candidates: [(Alert.Kind, Date)] = []
        // 하루 한도
        let leftDaily = limit.dailyMinutes - usedToday
        candidates.append((.daily, now.addingTimeInterval(TimeInterval(max(0, leftDaily) * 60))))
        // 취침 전 한도 (구간이 이미 시작됐거나, 이 세션 중에 시작될 때)
        let eveningBase = max(now, eveningStart)
        let leftEvening = settings.eveningLimitMinutes - (now >= eveningStart ? usedEvening : 0)
        candidates.append((.evening, eveningBase.addingTimeInterval(TimeInterval(max(0, leftEvening) * 60))))

        guard let first = candidates.min(by: { $0.1 < $1.1 }) else { return [] }
        let fireAt = max(first.1, now.addingTimeInterval(5))
        let name = displayName(limit.app)
        let toBed = rt.minutesToBedtime
        let bedNote = toBed > 0 ? "취침까지 \(Clock.durationText(toBed)) 남았어요." : "취침 시간이 지났어요."
        func message(_ repeatIndex: Int) -> (String, String) {
            switch first.0 {
            case .daily:
                let title = repeatIndex == 0 ? "\(name) 오늘 \(limit.dailyMinutes)분을 다 썼어요"
                                             : "\(name) 한도를 \(settings.repeatMinutes * repeatIndex)분 넘었어요"
                let body = preferFirm ? "지금 닫는 게 좋아요. 내일 같은 시간이 다시 생겨요."
                                      : "잠깐 쉬어 갈까요? 오늘 한도는 여기까지예요."
                return (title, body)
            case .evening:
                let title = repeatIndex == 0 ? "잘 시간이 가까워요 · \(name)"
                                             : "취침 전 한도를 \(settings.repeatMinutes * repeatIndex)분 넘었어요"
                let body = (preferFirm ? "오늘 밤 한도 \(settings.eveningLimitMinutes)분을 넘었어요. 지금 내려놓아요. "
                                       : "오늘 밤 화면 시간을 다 썼어요. 슬슬 마무리해 볼까요? ") + bedNote
                return (title, body)
            }
        }
        return (0..<3).map { k in
            let m = message(k)
            return Alert(kind: first.0, at: fireAt.addingTimeInterval(TimeInterval(k * settings.repeatMinutes * 60)),
                         title: m.0, body: m.1)
        }
    }

    static func displayName(_ app: String) -> String {
        switch canonical(app) {
        case "youtube": return "유튜브"
        case "instagram": return "인스타그램"
        case "tiktok": return "틱톡"
        case "netflix": return "넷플릭스"
        default: return app
        }
    }
}

@MainActor
@Observable
final class UsageStore {
    static let shared = UsageStore()

    private struct Saved: Codable {
        var sessions: [AppSession]
        var settings: UsageSettings
        var lastEvent: Date?
    }

    var sessions: [AppSession] = []
    var settings = UsageSettings()
    var lastEvent: Date?                    // 자동화가 동작하는지 확인용
    private var isTest = false

    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("usage.json")
    }

    init() { load() }

    private func load() {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        sessions = s.sessions
        settings = s.settings
        lastEvent = s.lastEvent
    }

    func save() {
        guard !isTest else { return }
        let cutoff = Date().addingTimeInterval(-60 * 86400)
        sessions.removeAll { $0.start < cutoff }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(sessions: sessions, settings: settings, lastEvent: lastEvent))
                .write(to: url, options: .atomic)
        } catch {
            AppLog.shared.add("사용시간 저장 실패: \(error)")
        }
    }

    // MARK: 테스트 모드

    func beginTest(_ s: [AppSession]) {
        isTest = true
        sessions = s
        lastEvent = Date()
    }

    func endTest() {
        isTest = false
        load()
    }

    // MARK: 조회

    var watchedApps: [String] { settings.limits.filter(\.enabled).map(\.app) }

    var openSession: AppSession? { sessions.last { $0.end == nil && !$0.manual } }

    func todayMinutes(_ app: String, now: Date = AppClock.now) -> Int {
        UsageMath.today(sessions, app: app, now: now)
    }

    func eveningMinutes(now: Date = AppClock.now, profile: UserProfile) -> Int {
        UsageMath.evening(sessions, watched: watchedApps, now: now, profile: profile)
    }

    // MARK: 이벤트 (App Intent · 알림 버튼 · 앱 활성화)

    /// 앱이 열림. 다른 앱 세션은 닫는다 (한 번에 하나만 앞에 있을 수 있음)
    @discardableResult
    func appOpened(_ app: String, at now: Date = Date(), profile: UserProfile) async -> String {
        lastEvent = now
        if let open = openSession, UsageMath.same(open.app, app) { return "이미 기록 중: \(app)" }
        await closeAll(at: now)
        var s = AppSession(app: app, start: now)
        let preferFirm = MemoryStore.shared.snapshot(now: now, profile: profile).preferredTone == .firm
        let alerts = UsageMath.alerts(app: app, now: now, sessions: sessions + [s], settings: settings,
                                      profile: profile, preferFirm: preferFirm)
        for (k, a) in alerts.enumerated() {
            NotificationService.shared.scheduleIn(id: "usage-\(UsageMath.canonical(app))-\(k)", at: a.at,
                                                  title: a.title, body: a.body)
        }
        if let first = alerts.first {
            s.alertAt = first.at
            s.alertTone = preferFirm ? "firm" : "gentle"
            s.alertKind = first.kind.rawValue
        }
        sessions.append(s)
        save()
        let used = todayMinutes(app, now: now)
        AgentLog.shared.add(.windDown, path: .rule,
                            action: "\(UsageMath.displayName(app)) 열림 · 오늘 \(used)분"
                                + (alerts.first.map { " · 알림 \(Fmt.time.string(from: $0.at))" } ?? ""))
        return "기록 시작: \(UsageMath.displayName(app)) (오늘 \(used)분)"
    }

    /// 앱이 닫힘
    @discardableResult
    func appClosed(_ app: String, at now: Date = Date()) async -> String {
        lastEvent = now
        await NotificationService.shared.cancel(prefix: "usage-\(UsageMath.canonical(app))-")
        guard let i = sessions.lastIndex(where: { $0.end == nil && !$0.manual && UsageMath.same($0.app, app) }) else {
            return "열린 기록 없음: \(app)"
        }
        sessions[i].end = now
        resolveAlert(sessions[i], closedAt: now)
        save()
        let mins = UsageMath.minutes([sessions[i]], from: .distantPast, to: .distantFuture, now: now)
        return "기록 종료: \(UsageMath.displayName(app)) \(mins)분 · 오늘 \(todayMinutes(app, now: now))분"
    }

    /// SleepMate가 앞으로 나왔다 = 다른 앱은 닫힌 것
    func closeAll(at now: Date = Date()) async {
        for i in sessions.indices where sessions[i].end == nil && !sessions[i].manual {
            sessions[i].end = now
            await NotificationService.shared.cancel(prefix: "usage-\(UsageMath.canonical(sessions[i].app))-")
            resolveAlert(sessions[i], closedAt: now)
        }
        save()
    }

    /// 알림 버튼 '+5분'처럼 직접 기록
    func addManual(minutes: Int, now: Date = Date()) {
        sessions.append(AppSession(app: "직접 기록", start: now.addingTimeInterval(TimeInterval(-minutes * 60)),
                                   end: now, manual: true))
        save()
    }

    func removeManualToday(now: Date = Date()) {
        let start = Calendar.current.startOfDay(for: now)
        sessions.removeAll { $0.manual && $0.start >= start }
        save()
    }

    /// 알림이 실제로 울렸는지(닫힌 시각 ≥ 알림 시각) 보고, 5분 안에 닫았으면 '수락'
    private func resolveAlert(_ s: AppSession, closedAt: Date) {
        guard let at = s.alertAt, closedAt >= at else { return }
        let accepted = closedAt.timeIntervalSince(at) <= 5 * 60
        MemoryStore.shared.recordIntervention(
            InterventionRecord(time: at, kind: .appLimit, tone: s.alertTone ?? "gentle", channel: .notification,
                               detail: "\(UsageMath.displayName(s.app)) \(s.alertKind == "evening" ? "취침 전" : "하루") 한도",
                               outcome: accepted ? .accepted : .ignored, outcomeTime: closedAt))
    }
}
