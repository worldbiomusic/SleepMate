import Foundation

// 개인 문맥 기억 (아이폰 안에만 저장)
//  1) 실시간  : 지금 시각·취침까지·열린 앱 (저장하지 않고 매번 계산)
//  2) 일일 에피소드 : 하루 한 장 기록 — 수면·기분·앱 사용·개입과 결과 (60일)
//  3) 장기 패턴 : 에피소드에서 뽑은 '나에 대한 사실' — 신뢰도·근거 수·감쇠
//  4) 사용자 선언 : 목표·한도·규칙 (UserProfile, UsageSettings) — 추론이 덮어쓰지 않음
// 순환: 수집 → 통합(패턴 계산) → 꺼내기(스냅샷) → 배움(개입 결과)

// MARK: - 개입 기록 (배움의 재료)

struct InterventionRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case windDown, appLimit, schedule, bedtimeNotice }
    enum Channel: String, Codable { case inApp, notification }
    enum Outcome: String, Codable { case pending, accepted, ignored }

    var id = UUID()
    var time: Date
    var kind: Kind
    var tone: String               // gentle / cheerful / firm
    var channel: Channel
    var detail: String
    var outcome: Outcome = .pending
    var outcomeTime: Date?

    var kindLabel: String {
        switch kind {
        case .windDown: return "취침 권유"
        case .appLimit: return "앱 한도 알림"
        case .schedule: return "일정 제안"
        case .bedtimeNotice: return "취침 알림"
        }
    }
}

// MARK: - 일일 에피소드

struct NightSummary: Equatable {
    var day: Date                   // 기상일(자정)
    var bedtime: Date
    var wake: Date
    var asleepMin: Int
}

struct DayEpisode: Identifiable, Equatable {
    var day: Date                   // 저녁 기준 날짜(이 날 밤에 잠)
    var bedtime: Date?              // 실제 잠든 시각
    var bedDelayMin: Int?           // 목표 대비 (+ 늦음)
    var asleepMin: Int?             // 그날 밤 수면
    var mood: Mood?
    var fatigue: Int?
    var appMinutes: [String: Int]   // 앱별 사용 분
    var eveningAppMin: Int          // 취침 준비 구간 사용 분
    var interventions: [InterventionRecord]
    var id: Date { day }

    var weekday: Int { Calendar.current.component(.weekday, from: day) }   // 1=일 … 7=토
}

// MARK: - 장기 패턴

struct PatternFact: Identifiable, Equatable, Codable {
    enum Category: String, CaseIterable, Codable { case sleep = "수면 습관", intervention = "통하는 개입", app = "앱 사용" }
    enum Source: String, Codable { case observed = "관찰", confirmed = "확인됨" }

    var id: String                  // 고유 키 (예: late-weekday-2)
    var category: Category
    var title: String               // "월요일 밤엔 평균 50분 늦게 자요"
    var question: String?           // 되묻기 문장
    var value: Double
    var evidence: Int               // 근거 수
    var baseConfidence: Double
    var lastEvidence: Date
    var source: Source = .observed
    var halfLifeDays: Double = 28

    /// 시간이 지나면 신뢰도가 줄어든다 (근거가 halfLife일 동안 없으면 절반)
    func confidence(now: Date) -> Double {
        if source == .confirmed { return 0.95 }
        let days = max(0, now.timeIntervalSince(lastEvidence) / 86400)
        return baseConfidence * pow(0.5, days / halfLifeDays)
    }
}

enum FactOverride: String, Codable { case confirmed, rejected }

// MARK: - 스냅샷 (판단할 때 필요한 것만)

struct ContextSnapshot: Equatable {
    var preferredTone: WindDownDecision.Tone?
    var lateTonight: PatternFact?            // 오늘 요일에 늦게 자는 패턴
    var eveningAppRisk: PatternFact?         // 밤 앱 사용 → 늦은 취침 패턴
    var lines: [String]                      // LLM에 넘길 짧은 사실 (신뢰도 높은 순, 최대 3)

    static let empty = ContextSnapshot(preferredTone: nil, lateTonight: nil, eveningAppRisk: nil, lines: [])
}

// MARK: - 엔진 (순수 함수)

enum MemoryEngine {
    static let weekdayNames = ["", "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    /// 목표 취침 대비 지연(분). 자정 넘김 처리.
    static func delay(bedtime: Date, target: Int) -> Int {
        var d = Clock.minutes(of: bedtime) - target
        if d < -12 * 60 { d += 1440 }
        if d > 12 * 60 { d -= 1440 }
        return d
    }

    /// 에피소드 만들기: 밤 기록은 '전날 저녁'의 에피소드가 된다
    static func episodes(nights: [NightSummary], contexts: [DailyContext], sessions: [AppSession],
                         interventions: [InterventionRecord], profile: UserProfile,
                         now: Date, days: Int = 60, calendar: Calendar = .current) -> [DayEpisode] {
        let today = calendar.startOfDay(for: now)
        var out: [DayEpisode] = []
        let watched = Set(sessions.map { UsageMath.canonical($0.app) })
        for k in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -k, to: today) else { continue }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let night = nights.first { calendar.isDate($0.day, inSameDayAs: next) }
            let ctx = contexts.first { calendar.isDate($0.date, inSameDayAs: day) }
            var apps: [String: Int] = [:]
            for a in watched {
                let m = UsageMath.minutes(sessions, app: a, from: day, to: next, now: now)
                if m > 0 { apps[UsageMath.displayName(a)] = m }
            }
            // 취침 준비 구간: 그날 목표 취침 - lead ~ 실제 잠든 시각(없으면 목표+2시간)
            let bedTarget = day.addingTimeInterval(TimeInterval(profile.bedtimeMinutes * 60))
            let evFrom = bedTarget.addingTimeInterval(TimeInterval(-profile.windDownLeadMinutes * 60))
            let evTo = night?.bedtime ?? bedTarget.addingTimeInterval(7200)
            let evening = evTo > evFrom ? UsageMath.minutes(sessions, from: evFrom, to: min(evTo, now), now: now) : 0
            let ivs = interventions.filter { $0.time >= day.addingTimeInterval(6 * 3600) && $0.time < next.addingTimeInterval(6 * 3600) }
            if night == nil && ctx == nil && apps.isEmpty && ivs.isEmpty { continue }
            out.append(DayEpisode(day: day, bedtime: night?.bedtime,
                                  bedDelayMin: night.map { delay(bedtime: $0.bedtime, target: profile.bedtimeMinutes) },
                                  asleepMin: night?.asleepMin, mood: ctx?.mood, fatigue: ctx?.fatigue,
                                  appMinutes: apps, eveningAppMin: evening, interventions: ivs))
        }
        return out
    }

    /// 장기 패턴 계산 (통합)
    static func patterns(episodes: [DayEpisode], interventions: [InterventionRecord],
                         overrides: [String: FactOverride], profile: UserProfile, now: Date) -> [PatternFact] {
        var facts: [PatternFact] = []
        let withBed = episodes.filter { $0.bedDelayMin != nil }

        // 1. 요일별 늦게 자는 패턴
        for wd in 1...7 {
            let list = withBed.filter { $0.weekday == wd }
            guard list.count >= 3 else { continue }
            let delays = list.map { $0.bedDelayMin! }
            let mean = Double(delays.reduce(0, +)) / Double(delays.count)
            let lateShare = Double(delays.filter { $0 >= 20 }.count) / Double(delays.count)
            guard mean >= 30, lateShare >= 0.6 else { continue }
            let conf = min(0.9, 0.25 + 0.12 * Double(list.count)) * lateShare
            facts.append(PatternFact(id: "late-weekday-\(wd)", category: .sleep,
                                     title: "\(weekdayNames[wd]) 밤엔 평균 \(Int(mean))분 늦게 자요",
                                     question: "\(weekdayNames[wd]) 밤엔 늦게 주무시는 편이세요?",
                                     value: mean, evidence: list.count, baseConfidence: conf,
                                     lastEvidence: list.map(\.day).max() ?? now))
        }

        // 2. 최근 2주 평균 수면
        let recent = episodes.filter { $0.asleepMin != nil && now.timeIntervalSince($0.day) <= 15 * 86400 }
        if recent.count >= 5 {
            let avg = recent.map { $0.asleepMin! }.reduce(0, +) / recent.count
            let gap = profile.goalSleepMinutes - avg
            let tail = gap > 15 ? " (목표보다 \(SleepStats.hm(gap)) 적음)" : (gap < -15 ? " (목표보다 충분)" : " (목표와 비슷)")
            facts.append(PatternFact(id: "sleep-avg", category: .sleep,
                                     title: "최근 2주 평균 수면 \(SleepStats.hm(avg))" + tail, question: nil,
                                     value: Double(avg), evidence: recent.count,
                                     baseConfidence: min(0.9, 0.3 + 0.05 * Double(recent.count)),
                                     lastEvidence: recent.map(\.day).max() ?? now, halfLifeDays: 14))
        }

        // 3. 통하는 개입: 말투별 수락률
        let resolved = interventions.filter { $0.outcome != .pending }
        for tone in ["gentle", "firm", "cheerful"] {
            let list = resolved.filter { $0.tone == tone }
            guard list.count >= 3 else { continue }
            let rate = Double(list.filter { $0.outcome == .accepted }.count) / Double(list.count)
            let label = tone == "firm" ? "단호한 말투" : (tone == "gentle" ? "부드러운 말투" : "응원하는 말투")
            facts.append(PatternFact(id: "tone-\(tone)", category: .intervention,
                                     title: "\(label) 알림은 \(Int(rate * 100))% 받아들였어요",
                                     question: rate >= 0.6 ? "\(label)로 말해 주는 게 더 효과 있나요?" : nil,
                                     value: rate, evidence: list.count,
                                     baseConfidence: min(0.9, 0.2 + 0.1 * Double(list.count)),
                                     lastEvidence: list.map(\.time).max() ?? now))
        }

        // 4. 밤 앱 사용 → 늦은 취침
        let heavy = withBed.filter { $0.eveningAppMin >= 30 }
        let light = withBed.filter { $0.eveningAppMin < 30 }
        if heavy.count >= 3, light.count >= 3 {
            let h = Double(heavy.map { $0.bedDelayMin! }.reduce(0, +)) / Double(heavy.count)
            let l = Double(light.map { $0.bedDelayMin! }.reduce(0, +)) / Double(light.count)
            if h - l >= 20 {
                facts.append(PatternFact(id: "evening-app-late", category: .app,
                                         title: "밤에 앱을 30분 넘게 쓴 날은 평균 \(Int(h - l))분 늦게 자요",
                                         question: "밤에 영상을 보면 잠드는 시간이 늦어지는 것 같으세요?",
                                         value: h - l, evidence: heavy.count + light.count,
                                         baseConfidence: min(0.9, 0.2 + 0.05 * Double(heavy.count + light.count)),
                                         lastEvidence: heavy.map(\.day).max() ?? now))
            }
        }

        // 5. 앱별 하루 평균
        var perApp: [String: [Int]] = [:]
        for e in episodes { for (a, m) in e.appMinutes { perApp[a, default: []].append(m) } }
        for (a, list) in perApp where list.count >= 3 {
            let avg = list.reduce(0, +) / list.count
            facts.append(PatternFact(id: "app-avg-\(a)", category: .app,
                                     title: "\(a) 하루 평균 \(avg)분 (\(list.count)일)", question: nil,
                                     value: Double(avg), evidence: list.count,
                                     baseConfidence: min(0.9, 0.3 + 0.08 * Double(list.count)),
                                     lastEvidence: now, halfLifeDays: 14))
        }

        // 사용자 확인/거절 반영 (거절·잊기 → 쓰지 않음)
        return facts.compactMap { f in
            switch overrides[f.id] {
            case .rejected: return nil
            case .confirmed: var c = f; c.source = .confirmed; return c
            case nil: return f
            }
        }
        .sorted { $0.confidence(now: now) > $1.confidence(now: now) }
    }

    /// 판단에 필요한 것만 꺼낸다 (신뢰도 0.5 이상)
    static func snapshot(facts: [PatternFact], now: Date) -> ContextSnapshot {
        let usable = facts.filter { $0.confidence(now: now) >= 0.5 }
        // 오늘 밤이 '늦게 자는 요일'인가 (새벽이면 전날 저녁 기준)
        let evening = Calendar.current.component(.hour, from: now) < 6 ? now.addingTimeInterval(-86400) : now
        let wd = Calendar.current.component(.weekday, from: evening)
        let late = usable.first { $0.id == "late-weekday-\(wd)" }
        let risk = usable.first { $0.id == "evening-app-late" }
        let tones = usable.filter { $0.id.hasPrefix("tone-") && $0.value >= 0.5 }.max { $0.value < $1.value }
        let tone = tones.flatMap { WindDownDecision.Tone(rawValue: String($0.id.dropFirst(5))) }
        return ContextSnapshot(preferredTone: tone, lateTonight: late, eveningAppRisk: risk,
                               lines: usable.filter { $0.category != .app || $0.id == "evening-app-late" }
                                   .prefix(3).map(\.title))
    }

    /// 되묻기: 애매한(0.4~0.65) 사실 하나
    static func question(facts: [PatternFact], askedAt: [String: Date], now: Date) -> PatternFact? {
        facts.first { f in
            guard f.source == .observed, f.question != nil else { return false }
            let c = f.confidence(now: now)
            let recentlyAsked = askedAt[f.id].map { now.timeIntervalSince($0) < 3 * 86400 } ?? false
            return c >= 0.4 && c < 0.65 && !recentlyAsked
        }
    }

    /// 방해율: 결과가 난 개입 중 무시된 비율
    static func interruptionRate(_ list: [InterventionRecord]) -> Double? {
        let r = list.filter { $0.outcome != .pending }
        guard !r.isEmpty else { return nil }
        return Double(r.filter { $0.outcome == .ignored }.count) / Double(r.count)
    }
}
