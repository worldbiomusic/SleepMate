import Foundation
import WatchConnectivity

/// 아이폰 ↔ 애플워치 연결 (수업 4.1의 Companion Relay: 워치는 보여 주고 입력받고, 판단은 아이폰)
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private weak var store: SleepStore?
    private weak var ctx: ContextStore?
    private weak var calendar: CalendarService?
    private var last: WatchPayload?

    func start(store: SleepStore, ctx: ContextStore, calendar: CalendarService) {
        self.store = store
        self.ctx = ctx
        self.calendar = calendar
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 지금 상태로 요약을 만든다 (워치 화면 = 이 값)
    func makePayload(now at: Date? = nil) -> WatchPayload? {
        guard let store, let ctx else { return nil }
        let now = at ?? AppClock.now
        let p = ctx.profile
        var payload = WatchPayload(updatedAt: Date(), bedtimeMinutes: p.bedtimeMinutes,
                                   windDownLeadMinutes: p.windDownLeadMinutes,
                                   eveningAppMinutes: UsageStore.shared.eveningMinutes(now: now, profile: p),
                                   eveningLimitMinutes: UsageStore.shared.settings.eveningLimitMinutes,
                                   openApp: UsageStore.shared.openSession.map { UsageMath.displayName($0.app) },
                                   stopped: ctx.today.stoppedScreen, mood: ctx.today.mood?.rawValue)
        if let s = SleepStats(nights: store.nights, now: now) {
            let sc = SleepScore.compute(s, goalMinutes: p.goalSleepMinutes)
            payload.score = sc.total
            payload.scoreLabel = sc.label
            payload.asleepText = Clock.durationText(s.asleepMin)
            if let avg = s.avg7AsleepMin, s.nightsIn7 >= 3 {
                let d = s.asleepMin - avg
                payload.sleepNote = abs(d) < 10 ? "최근 평균과 비슷해요"
                    : (d > 0 ? "최근 평균보다 \(Clock.durationText(d)) 더 잤어요" : "최근 평균보다 \(Clock.durationText(-d)) 짧아요")
            }
            payload.recommendation = RuleReporter.make(s).recommendations.first
        }
        let rt = RealtimeContext(now: now, profile: p, todayItems: [])
        let input = WindDownInput(minutesToBed: rt.minutesToBedtime, screenCount: payload.eveningAppMinutes,
                                  screenGoal: payload.eveningLimitMinutes, stopped: payload.stopped,
                                  mood: ctx.today.mood, fatigue: ctx.today.fatigue,
                                  snapshot: MemoryStore.shared.snapshot(now: now, profile: p))
        let d = JevDecisions.windDownRule(input)
        if d.nudge { payload.nudge = d.message }
        payload.learnedNote = d.learnedNote
        if let calendar {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            let plan = AlarmPlanner.plan(profile: p, tomorrowItems: calendar.items(on: tomorrow, fixedKeywords: p.fixedKeywords))
            payload.wakeText = Clock.text(plan.wakeMinutes)
            payload.wakeReason = plan.reason
        }
        return payload
    }

    /// 상태가 바뀌면 워치로 보낸다 (applicationContext는 최신 1개만 유지 → 워치가 켜질 때 받음)
    func push() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              var p = makePayload() else { return }
        p.updatedAt = last?.updatedAt ?? p.updatedAt
        if p == last { return }
        p.updatedAt = Date()
        last = p
        try? WCSession.default.updateApplicationContext(p.encoded())
    }

    private func handle(_ message: [String: Any]) {
        guard let raw = message[WatchCommand.key] as? String, let cmd = WatchCommand(rawValue: raw), let ctx else { return }
        switch cmd {
        case .stop:
            ctx.stopScreen()
            ctx.record(scenario: "02", key: "screen-stop", title: "화면 그만 보기 (워치)", response: .accepted)
            MemoryStore.shared.markLatestAccepted(kinds: [.windDown, .appLimit, .bedtimeNotice], now: Date())
            AgentLog.shared.add(event: "워치", path: .rule, action: "오늘은 여기까지", guardNote: nil)
        case .add5:
            UsageStore.shared.addManual(minutes: 5)
        case .mood:
            if let v = message[WatchCommand.valueKey] as? String, let m = Mood(rawValue: v) {
                ctx.today.mood = m
                ctx.save()
            }
        case .refresh:
            break
        }
        last = nil
        push()
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let box = MessageBox(message)
        Task { @MainActor in self.handle(box.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let box = MessageBox(message)
        Task { @MainActor in
            self.handle(box.value)
            replyHandler(self.last?.encoded() ?? [:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let box = MessageBox(userInfo)
        Task { @MainActor in self.handle(box.value) }
    }
}

/// [String: Any]를 액터 경계 너머로 넘기기 위한 상자
private struct MessageBox: @unchecked Sendable {
    let value: [String: Any]
    init(_ v: [String: Any]) { value = v }
}
