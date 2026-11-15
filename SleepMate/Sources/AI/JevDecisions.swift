import Foundation

// Jev가 맡는 '작고 빠른 판단' 4곳 (계획서: 규칙 → 경량 AI → LLM 중 '경량 AI' 자리)
//  ① 02 취침 개입: 지금 말을 걸까? 어떤 말투로? 무엇을 권할까?
//  ② 01 노션 할 일 분류: 약속/집중 작업/가벼운 일/볼일/자기 관리 + 집중 필요도
//  ③ 02 수면 사운드: 오늘 상태에 맞는 소리 종류
//  ④ 05 Claude 게이트: 오늘 아침 요약을 LLM에 맡길 만큼 특별한 날인가? (비용 절감)
// 키가 없거나 실패하면 같은 판단을 규칙으로 대신한다 (AgentLog 경로: 경량 AI / 규칙)

/// 화면에 보여줄 판단 결과 (확률 막대 시각화용)
struct DecisionView: Equatable {
    struct Bar: Equatable, Identifiable {
        let label: String
        let value: Double
        var id: String { label }
    }
    var question: String
    var answer: String
    var confidence: Double?
    var bars: [Bar] = []
    var path: ReasonPath
    var note: String?
}

// MARK: - ① 취침 개입

struct WindDownInput {
    var minutesToBed: Int
    var screenCount: Int
    var screenGoal: Int
    var stopped: Bool
    var mood: Mood?
    var fatigue: Int?
}

struct WindDownDecision: Equatable {
    enum Tone: String { case gentle, cheerful, firm }
    enum Action: String { case remindGoal = "remind_goal", focusMode = "suggest_focus_mode"
        case sound = "suggest_sleep_sound", breathing = "suggest_breathing", none }

    var nudge: Bool
    var tone: Tone
    var action: Action
    var view: DecisionView

    var message: String {
        guard nudge else { return "지금은 그대로 두어도 괜찮아요. 편하게 쉬세요." }
        let body: String
        switch action {
        case .remindGoal: body = "오늘 화면 목표를 한 번 떠올려 볼까요?"
        case .focusMode: body = "취침 모드를 켜고 화면을 내려놓을 시간이에요."
        case .sound: body = "잔잔한 소리를 틀어 두고 눈을 감아 보세요."
        case .breathing: body = "1분만 천천히 호흡해 볼까요? 4초 들이쉬고, 7초 멈추고, 8초 내쉬어요."
        case .none: body = "조금씩 마무리해 봐요."
        }
        switch tone {
        case .gentle: return body
        case .cheerful: return "잘하고 있어요! " + body
        case .firm: return "목표를 넘었어요. 지금 멈추면 내일 아침이 가벼워져요. " + body
        }
    }
}

// MARK: - ② 할 일 분류

enum TaskKind: String, CaseIterable, Codable {
    case appointment, deepFocus = "deep_focus", light = "light_task", errand, selfCare = "self_care"

    var label: String {
        switch self {
        case .appointment: return "약속·일정"
        case .deepFocus: return "집중 작업"
        case .light: return "가벼운 일"
        case .errand: return "볼일·구매"
        case .selfCare: return "자기 관리"
        }
    }
    var symbol: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .deepFocus: return "brain.head.profile"
        case .light: return "checklist"
        case .errand: return "bag"
        case .selfCare: return "heart"
        }
    }
}

struct TaskClass: Equatable, Codable {
    var kind: TaskKind
    var focus: Int          // 0 낮음 · 1 보통 · 2 높음
    var path: ReasonPath
}

// MARK: - ③ 수면 사운드

enum SoundType: String, CaseIterable, Identifiable, Codable {
    case rain, whiteNoise = "white_noise", piano, lofi, nature, meditation
    var id: String { rawValue }
}

@MainActor
enum JevDecisions {
    static var config: JevConfig { .load() }
    static var available: Bool { JevClient.isConfigured }

    // MARK: ① 취침 개입

    static func windDownRule(_ i: WindDownInput) -> WindDownDecision {
        let ratio = Double(i.screenCount) / Double(max(i.screenGoal, 1))
        let nearBed = (0...30).contains(i.minutesToBed)
        let nudge = !i.stopped && (ratio >= 0.8 || (nearBed && i.screenCount > 0) || i.minutesToBed < 0)
        let tone: WindDownDecision.Tone = ratio > 1.2 ? .firm : (ratio < 0.5 ? .cheerful : .gentle)
        let action: WindDownDecision.Action
        if !nudge { action = .none }
        else if ratio >= 1 { action = .focusMode }
        else if i.mood == .stressed || i.mood == .anxious { action = .sound }
        else if nearBed || i.minutesToBed < 0 { action = .breathing }
        else { action = .remindGoal }
        return WindDownDecision(nudge: nudge, tone: tone, action: action,
                                view: DecisionView(question: "지금 말을 걸까요?", answer: nudge ? "네" : "아니요",
                                                   confidence: nil, path: .rule, note: "규칙 판단"))
    }

    static func windDown(_ i: WindDownInput) async -> WindDownDecision {
        guard available, config.useWindDown else { return windDownRule(i) }
        let state: [String: Any] = [
            "minutes_until_target_bedtime": i.minutesToBed,
            "screen_items_watched_tonight": i.screenCount,
            "screen_goal_tonight": i.screenGoal,
            "user_said_stop_for_tonight": i.stopped,
            "mood": i.mood?.jevName ?? "unknown",
            "fatigue_1_to_5": i.fatigue ?? 0,
        ]
        let qs: [String: JevQuestion] = [
            "should_nudge": .noul(
                instructions: "A sleep app is helping the user wind down before bed. Should it gently interrupt the user right now?",
                yes: "Bedtime is near or passed, or the user is close to or over tonight's screen goal, and they have not stopped yet.",
                no: "Bedtime is still far away, the user is well under the goal, or the user already decided to stop."),
            "tone": .choice(instructions: "Which tone fits the message best?",
                            options: ["gentle": "Soft and calm reminder.",
                                      "cheerful": "Encouraging; the user is doing well.",
                                      "firm": "Clear and direct; the user is well over the goal or past bedtime."]),
            "action": .choice(instructions: "Which single action should the app suggest?",
                              options: ["remind_goal": "Remind the screen goal.",
                                        "suggest_focus_mode": "Turn on sleep focus mode and put the phone down.",
                                        "suggest_sleep_sound": "Play calming sleep sounds (good when stressed or anxious).",
                                        "suggest_breathing": "Do a one-minute breathing exercise (good right before bed).",
                                        "none": "Suggest nothing."]),
        ]
        do {
            let a = try await JevClient.decide(state: state, questions: qs)
            let p = a["should_nudge"]?.noul ?? 0
            let tone = WindDownDecision.Tone(rawValue: a["tone"]?.choice ?? "") ?? .gentle
            let action = WindDownDecision.Action(rawValue: a["action"]?.choice ?? "") ?? .remindGoal
            let view = DecisionView(question: "지금 말을 걸까요?", answer: p >= 0.5 ? "네" : "아니요",
                                    confidence: p >= 0.5 ? p : 1 - p,
                                    bars: [.init(label: "네", value: p), .init(label: "아니요", value: 1 - p)],
                                    path: .light)
            AgentLog.shared.add(.windDown, path: .light,
                                action: "개입 \(Int(p * 100))% · \(tone.rawValue) · \(action.rawValue)")
            return WindDownDecision(nudge: p >= 0.5, tone: tone, action: p >= 0.5 ? action : .none, view: view)
        } catch {
            var r = windDownRule(i)
            r.view.note = "Jev 실패 → 규칙: \(error.localizedDescription)"
            AgentLog.shared.add(.windDown, path: .rule, action: "Jev 실패, 규칙으로 대체", guardNote: error.localizedDescription)
            return r
        }
    }

    // MARK: ② 할 일 분류

    static func classifyRule(_ title: String) -> TaskClass { classifyRuleNonisolated(title) }

    nonisolated static func classifyRuleNonisolated(_ title: String) -> TaskClass {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        // 순서 중요: "발표 준비"·"시험 범위 복습"은 집중 작업, "저녁 운동"은 자기 관리
        if has(["준비", "공부", "작성", "보고서", "ppt", "논문", "개발", "코딩", "정리", "읽기", "연습", "만들기",
                "풀기", "분석", "기획", "스크립트", "복습", "마무리", "과제"]) {
            return TaskClass(kind: .deepFocus, focus: 2, path: .rule)
        }
        if has(["운동", "산책", "명상", "물리치료", "스트레칭", "샤워", "빨래", "청소", "찜질"]) {
            return TaskClass(kind: .selfCare, focus: 0, path: .rule)
        }
        if has(["구매", "사기", "마트", "다이소", "쿠팡", "주문", "반납", "신청", "전화", "예약", "청구", "문의", "가입", "결제", "택배", "교환"]) {
            return TaskClass(kind: .errand, focus: 0, path: .rule)
        }
        if has(["시험", "결혼식", "약속", "발표", "수업", "회의", "미팅", "면접", "모임", "장례", "예식", "진료", "병원",
                "특강", "세미나", "식사", "상담", "면담"]) {
            return TaskClass(kind: .appointment, focus: 1, path: .rule)
        }
        return TaskClass(kind: .light, focus: 1, path: .rule)
    }

    /// 한 번의 요청으로 모든 할 일을 분류 (질문 2개 × 할 일 수)
    static func classify(_ titles: [String]) async -> [TaskClass] {
        let rules = titles.map(classifyRule)
        guard available, config.useTasks, !titles.isEmpty else { return rules }
        var qs: [String: JevQuestion] = [:]
        for (i, title) in titles.prefix(30).enumerated() {
            qs["kind_\(i)"] = .choice(
                instructions: "Classify this personal to-do item (may be Korean): \"\(title)\"",
                options: ["appointment": "A scheduled event with other people or at a fixed place/time (exam, meeting, class, wedding, hospital visit, dinner).",
                          "deep_focus": "Cognitively demanding work (studying, writing, coding, preparing slides, analysis).",
                          "light_task": "Short or easy task that needs little focus.",
                          "errand": "Shopping, ordering, phone calls, applications, returns, paperwork.",
                          "self_care": "Exercise, rest, chores, health care routines."])
            qs["focus_\(i)"] = .score(instructions: "How much mental focus does this to-do need? \"\(title)\"",
                                      levels: ["low", "medium", "high"])
        }
        do {
            let a = try await JevClient.decide(state: ["purpose": "Plan the day around energy after sleep"], questions: qs)
            let out = titles.enumerated().map { i, _ -> TaskClass in
                guard i < 30, let k = a["kind_\(i)"]?.choice, let kind = TaskKind(rawValue: k) else { return rules[i] }
                let f = Int((a["focus_\(i)"]?.score ?? Double(rules[i].focus)).rounded())
                return TaskClass(kind: kind, focus: min(2, max(0, f)), path: .light)
            }
            AgentLog.shared.add(.planToday, path: .light, action: "노션 할 일 \(titles.count)개 분류")
            return out
        } catch {
            AgentLog.shared.add(.planToday, path: .rule, action: "할 일 분류: Jev 실패, 키워드로 대체",
                                guardNote: error.localizedDescription)
            return rules
        }
    }

    // MARK: ③ 수면 사운드

    static func soundRule(mood: Mood?, fatigue: Int?, preference: String) -> SoundType {
        switch mood {
        case .stressed, .anxious: return .rain
        case .tired: return .whiteNoise
        default: break
        }
        if (fatigue ?? 0) >= 4 { return .whiteNoise }
        let p = preference.lowercased()
        if p.contains("피아노") || p.contains("piano") { return .piano }
        if p.contains("로파이") || p.contains("lofi") { return .lofi }
        if p.contains("자연") || p.contains("숲") || p.contains("파도") { return .nature }
        if p.contains("명상") { return .meditation }
        return .piano
    }

    static func sound(mood: Mood?, fatigue: Int?, minutesToBed: Int, preference: String) async -> (SoundType, DecisionView) {
        let rule = soundRule(mood: mood, fatigue: fatigue, preference: preference)
        guard available, config.useSound else {
            return (rule, DecisionView(question: "오늘 밤 소리", answer: rule.title, path: .rule, note: "규칙 판단"))
        }
        let options = Dictionary(uniqueKeysWithValues: SoundType.allCases.map { ($0.rawValue, $0.englishHint) })
        do {
            let a = try await JevClient.decide(
                state: ["mood": mood?.jevName ?? "unknown", "fatigue_1_to_5": fatigue ?? 0,
                        "minutes_until_bedtime": minutesToBed, "user_preference": preference],
                questions: ["sound": .choice(instructions: "Pick the background sound most likely to help this user fall asleep tonight.",
                                             options: options)])
            guard let ans = a["sound"], let c = ans.choice, let t = SoundType(rawValue: c) else { throw JevError.badResponse }
            let bars = ans.probabilities.compactMap { k, v in SoundType(rawValue: k).map { DecisionView.Bar(label: $0.title, value: v) } }
                .sorted { $0.value > $1.value }
            AgentLog.shared.add(.windDown, path: .light, action: "수면 사운드: \(t.title) \(Int((ans.confidence ?? 0) * 100))%")
            return (t, DecisionView(question: "오늘 밤 소리", answer: t.title, confidence: ans.confidence,
                                    bars: Array(bars.prefix(4)), path: .light))
        } catch {
            return (rule, DecisionView(question: "오늘 밤 소리", answer: rule.title, path: .rule,
                                       note: "Jev 실패 → 규칙"))
        }
    }

    // MARK: ④ Claude 게이트

    static func llmGateRule(_ s: SleepStats) -> Bool {
        if s.daysSinceLastNight >= 2 { return true }
        if s.asleepMin < 6 * 60 || s.awakeMin >= 40 { return true }
        if let avg = s.avg7AsleepMin, abs(s.asleepMin - avg) >= 45 { return true }
        if (s.bedtimeSpreadMin ?? 0) >= 60 { return true }
        return false
    }

    /// true면 Claude로 자세한 요약을 만들 가치가 있는 날
    static func shouldUseLLM(_ s: SleepStats) async -> Bool {
        guard available, config.useLLMGate else { return true }      // 게이트를 안 쓰면 항상 Claude
        do {
            let a = try await JevClient.decide(
                state: ["asleep_minutes": s.asleepMin, "avg_asleep_minutes_7d": s.avg7AsleepMin ?? -1,
                        "awake_minutes": s.awakeMin, "deep_percent": s.deepPct, "rem_percent": s.remPct,
                        "bedtime_std_minutes": s.bedtimeSpreadMin ?? -1, "days_since_last_record": s.daysSinceLastNight],
                questions: ["notable": .noul(
                    instructions: "Is last night's sleep notable enough to deserve a detailed, personalized AI summary this morning?",
                    yes: "Short sleep, big change from average, many awakenings, irregular timing, or stale data.",
                    no: "An ordinary night close to the user's usual pattern.")])
            let p = a["notable"]?.noul ?? 1
            AgentLog.shared.add(.morning, path: .light,
                                action: "Claude 요약 필요도 \(Int(p * 100))% → \(p >= 0.4 ? "Claude 호출" : "기본 분석 유지")",
                                guardNote: p >= 0.4 ? nil : "비용 절감")
            return p >= 0.4
        } catch {
            return llmGateRule(s)
        }
    }

    /// 연결 테스트 (설정 화면)
    static func ping() async -> String {
        do {
            let a = try await JevClient.decide(
                state: "The user slept 5 hours last night and feels tired.",
                questions: ["tired": .noul(instructions: "Is the user likely to feel sleepy this afternoon?",
                                           yes: "Likely sleepy.", no: "Likely fine.")], timeout: 12)
            if let p = a["tired"]?.noul { return "연결 성공 · 예시 판단 '오후에 졸릴까?' → \(Int(p * 100))%" }
            return "연결은 됐지만 응답 형식이 달라요."
        } catch {
            return "실패: \(error.localizedDescription)"
        }
    }
}

extension Mood {
    /// Jev는 영어 입력에서 가장 정확하므로 기분은 영어로 보낸다
    var jevName: String {
        switch self {
        case .good: return "good"
        case .calm: return "calm"
        case .tired: return "tired"
        case .stressed: return "stressed"
        case .anxious: return "anxious"
        }
    }
}
