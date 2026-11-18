import Foundation
import Observation

@MainActor
@Observable
final class MemoryStore {
    static let shared = MemoryStore()

    private struct Saved: Codable {
        var interventions: [InterventionRecord]
        var overrides: [String: FactOverride]
        var askedAt: [String: Date]
        var facts: [PatternFact]           // 마지막 통합 결과 (백그라운드 App Intent에서도 쓰도록)
        var lastConsolidated: Date?
    }

    var interventions: [InterventionRecord] = []
    var overrides: [String: FactOverride] = [:]
    var askedAt: [String: Date] = [:]
    private(set) var facts: [PatternFact] = []
    private(set) var episodes: [DayEpisode] = []
    private(set) var lastConsolidated: Date?
    private var isTest = false

    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memory.json")
    }

    init() { load() }

    private func load() {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        interventions = s.interventions
        overrides = s.overrides
        askedAt = s.askedAt
        facts = s.facts
        lastConsolidated = s.lastConsolidated
    }

    func save() {
        guard !isTest else { return }
        let cutoff = Date().addingTimeInterval(-60 * 86400)
        interventions.removeAll { $0.time < cutoff }
        let s = Saved(interventions: interventions, overrides: overrides, askedAt: askedAt,
                      facts: facts, lastConsolidated: lastConsolidated)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(s).write(to: url, options: .atomic)
        } catch {
            AppLog.shared.add("기억 저장 실패: \(error)")
        }
    }

    // MARK: 수집 · 배움

    func recordIntervention(_ r: InterventionRecord) {
        interventions.append(r)
        save()
    }

    /// 화면 안 개입(취침 권유)은 한 번 보여 줄 때 기록하고, 같은 저녁에는 다시 기록하지 않음
    func recordInAppNudge(tone: String, detail: String, now: Date) {
        let since = now.addingTimeInterval(-3 * 3600)
        guard !interventions.contains(where: { $0.kind == .windDown && $0.channel == .inApp && $0.time >= since }) else { return }
        recordIntervention(InterventionRecord(time: now, kind: .windDown, tone: tone, channel: .inApp, detail: detail))
    }

    /// 사용자가 행동했다 (오늘은 여기까지 · 취침 모드 · 알림의 '오늘은 여기까지')
    func markLatestAccepted(kinds: [InterventionRecord.Kind], now: Date, within hours: Double = 3) {
        guard let i = interventions.lastIndex(where: {
            kinds.contains($0.kind) && $0.outcome == .pending && now.timeIntervalSince($0.time) <= hours * 3600
        }) else { return }
        interventions[i].outcome = .accepted
        interventions[i].outcomeTime = now
        save()
    }

    /// 오래 응답이 없던 개입은 '무시'로 정리
    func expirePending(now: Date) {
        var changed = false
        for i in interventions.indices where interventions[i].outcome == .pending
            && now.timeIntervalSince(interventions[i].time) > 6 * 3600 {
            interventions[i].outcome = .ignored
            changed = true
        }
        if changed { save() }
    }

    // MARK: 통합 (아침 동기화 · 앱 열 때)

    func consolidate(nights: [SleepNight], ctx: ContextStore, now: Date = AppClock.now) {
        expirePending(now: now)
        let summaries = nights.compactMap { n -> NightSummary? in
            guard let b = n.bedtime, let w = n.wakeTime else { return nil }
            return NightSummary(day: n.day, bedtime: b, wake: w, asleepMin: Int(n.asleep / 60))
        }
        consolidate(nights: summaries, contexts: [ctx.today] + ctx.history, profile: ctx.profile,
                    sessions: UsageStore.shared.sessions, now: now)
    }

    func consolidate(nights: [NightSummary], contexts: [DailyContext], profile: UserProfile,
                     sessions: [AppSession], now: Date) {
        episodes = MemoryEngine.episodes(nights: nights, contexts: contexts, sessions: sessions,
                                         interventions: interventions, profile: profile, now: now)
        facts = MemoryEngine.patterns(episodes: episodes, interventions: interventions,
                                      overrides: overrides, profile: profile, now: now)
        lastConsolidated = now
        save()
    }

    // MARK: 꺼내기

    func snapshot(now: Date, profile: UserProfile) -> ContextSnapshot {
        MemoryEngine.snapshot(facts: facts, now: now)
    }

    var pendingQuestion: PatternFact? {
        MemoryEngine.question(facts: facts, askedAt: askedAt, now: AppClock.now)
    }

    var interruptionRate: Double? { MemoryEngine.interruptionRate(interventions) }

    // MARK: 사용자 확인 · 잊기

    func answer(_ fact: PatternFact, yes: Bool) {
        askedAt[fact.id] = Date()
        overrides[fact.id] = yes ? .confirmed : .rejected
        if let i = facts.firstIndex(where: { $0.id == fact.id }) {
            if yes { facts[i].source = .confirmed } else { facts.remove(at: i) }
        }
        AgentLog.shared.add(event: "기억 확인", path: .rule, action: "\(fact.title) → \(yes ? "맞아요" : "아니에요")",
                            guardNote: nil)
        save()
    }

    func skipQuestion(_ fact: PatternFact) {
        askedAt[fact.id] = Date()
        save()
    }

    func forget(_ fact: PatternFact) {
        overrides[fact.id] = .rejected
        facts.removeAll { $0.id == fact.id }
        save()
    }

    func resetAll() {
        interventions = []
        overrides = [:]
        askedAt = [:]
        facts = []
        episodes = []
        save()
    }

    // MARK: 테스트 모드

    func beginTest(interventions list: [InterventionRecord]) {
        isTest = true
        interventions = list
        overrides = [:]
        askedAt = [:]
    }

    func endTest() {
        isTest = false
        episodes = []
        load()
    }
}
