import Foundation

// 근거 기반 수면 전략 라이브러리
// 모든 전략은 논문·가이드라인 출처(DOI)를 함께 갖고, 앱 안에서 바로 확인할 수 있다.
// 출처 확인: 2026-11-26, PubMed/학회 페이지 기준 (claude/strategy-evidence.md)

/// 근거 수준 (높을수록 믿을 만함)
enum EvidenceLevel: String, Codable {
    case guideline = "임상 가이드라인"
    case metaAnalysis = "메타분석"
    case consensus = "전문가 합의"
    case rct = "무작위 대조 시험"
    case labStudy = "실험 연구"
    case cohort = "대규모 관찰 연구"
    case review = "문헌 리뷰"

    /// A: 가이드라인·메타분석·합의 / B: 무작위 시험·대규모 코호트 / C: 소규모 실험·리뷰
    var grade: String {
        switch self {
        case .guideline, .metaAnalysis, .consensus: return "A"
        case .rct, .cohort: return "B"
        case .labStudy, .review: return "C"
        }
    }
}

struct Evidence: Equatable, Identifiable {
    let citation: String      // 저자 · 학술지 · 연도
    let title: String         // 논문 제목 (원문)
    let finding: String       // 핵심 결과 (우리말 요약)
    let doi: String
    let level: EvidenceLevel
    var id: String { doi }
    var url: URL { URL(string: "https://doi.org/\(doi)")! }
}

/// 사용자가 말한 고민
enum SleepProblem: String, Codable, CaseIterable, Identifiable {
    case fallAsleep = "fall_asleep"     // 잠들기 어려움
    case lateBed = "late_bed"           // 자꾸 늦게 자게 됨
    case wakeTired = "wake_tired"       // 아침이 피곤함
    case irregular = "irregular"        // 자는 시간이 들쭉날쭉
    case nightWake = "night_wake"       // 자다가 자주 깸
    case dayFocus = "day_sleepy"        // 낮에 졸림·집중 안 됨
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fallAsleep: return "잠들기 어려워요"
        case .lateBed: return "자꾸 늦게 자요"
        case .wakeTired: return "아침이 피곤해요"
        case .irregular: return "자는 시간이 들쭉날쭉해요"
        case .nightWake: return "자다가 자주 깨요"
        case .dayFocus: return "낮에 졸려요"
        }
    }
}

struct SleepStrategy: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String           // 한 줄 설명
    let icon: String
    let when: [NowMode]           // '지금' 화면에서 보여 줄 시간대
    let targets: [SleepProblem]
    let evidence: [Evidence]
    let appHelp: String           // 앱이 어떻게 도와주는지
    var caution: String? = nil

    var bestLevel: EvidenceLevel {
        evidence.map(\.level).min { $0.grade < $1.grade } ?? .review
    }
}

/// 인터뷰로 알게 된 개인 특성 (기기에만 저장)
struct PersonalProfile: Codable, Equatable {
    var workdayBed: Int?          // 자정 기준 분 (예: 01:00 → 60)
    var workdayWake: Int?
    var freeBed: Int?
    var freeWake: Int?
    var problems: [SleepProblem] = []
    var caffeineCups: Int?
    var lastCaffeine: Int?        // 마지막 카페인 시각 (분)
    var caffeineSensitive: Bool?
    var exercise: ExerciseTime?
    var naps: Bool?
    var alcoholPerWeek: Int?
    var lifestyle: String?        // 수업·연구 / 출근 / 교대 근무 / 자유
    var notes: [String] = []
    var redFlag = false           // 전문가 상담이 필요해 보이는 말이 있었음
    var chosen: [String] = []     // 사용자가 고른 전략 id
    var interviewDone = false

    enum ExerciseTime: String, Codable, CaseIterable {
        case rarely = "none", morning, afternoon, evening, lateNight = "late_night"
        var label: String {
            switch self {
            case .rarely: return "거의 안 함"
            case .morning: return "아침"
            case .afternoon: return "오후"
            case .evening: return "저녁"
            case .lateNight: return "자기 직전"
            }
        }
    }
}

enum Chronotype: String, Equatable {
    case early = "아침형", middle = "중간형", late = "저녁형"
}

enum StrategyLibrary {
    // MARK: 근거

    static let drake2013 = Evidence(
        citation: "Drake 외, J Clin Sleep Med 2013",
        title: "Caffeine Effects on Sleep Taken 0, 3, or 6 Hours before Going to Bed",
        finding: "카페인 400mg을 취침 6시간 전에 먹어도 객관적으로 측정한 총수면이 1시간 넘게 줄었고, 본인은 잘 알아차리지 못했어요.",
        doi: "10.5664/jcsm.3170", level: .labStudy)
    static let gardiner2023 = Evidence(
        citation: "Gardiner 외, Sleep Med Rev 2023",
        title: "The effect of caffeine on subsequent sleep: A systematic review and meta-analysis",
        finding: "연구 24편 종합: 카페인은 총수면을 평균 45분, 수면 효율을 7% 줄였어요. 커피 한 잔(107mg)은 취침 8.8시간 전까지 마시라고 제안해요.",
        doi: "10.1016/j.smrv.2023.101764", level: .metaAnalysis)
    static let scullin2018 = Evidence(
        citation: "Scullin 외, J Exp Psychol Gen 2018",
        title: "The effects of bedtime writing on difficulty falling asleep: A polysomnographic study comparing to-do lists and completed activity lists",
        finding: "자기 전 5분 동안 '내일 할 일'을 적은 사람이 '오늘 한 일'을 적은 사람보다 더 빨리 잠들었고, 구체적으로 적을수록 더 빨랐어요 (수면다원검사, 57명).",
        doi: "10.1037/xge0000374", level: .rct)
    static let he2020 = Evidence(
        citation: "He 외, PLOS ONE 2020",
        title: "Effect of restricting bedtime mobile phone use on sleep, arousal, mood, and working memory: A randomized pilot trial",
        finding: "취침 30분 전 휴대폰 사용을 4주 제한하자 잠들기까지 시간이 줄고 수면시간·작업기억이 좋아졌어요 (38명 예비 시험).",
        doi: "10.1371/journal.pone.0228756", level: .rct)
    static let chang2015 = Evidence(
        citation: "Chang 외, PNAS 2015",
        title: "Evening use of light-emitting eReaders negatively affects sleep, circadian timing, and next-morning alertness",
        finding: "자기 전 빛을 내는 화면으로 읽으면 종이책보다 잠드는 데 오래 걸리고, 멜라토닌이 줄고, 생체시계가 늦춰지고, 다음 날 아침이 덜 개운했어요.",
        doi: "10.1073/pnas.1418490112", level: .labStudy)
    static let wright2013 = Evidence(
        citation: "Wright 외, Current Biology 2013",
        title: "Entrainment of the human circadian clock to the natural light-dark cycle",
        finding: "낮엔 햇빛을 많이, 밤엔 인공조명을 적게 받는 1주 캠핑으로 생체시계가 앞당겨졌고, 저녁형일수록 더 많이 당겨졌어요.",
        doi: "10.1016/j.cub.2013.06.039", level: .labStudy)
    static let windred2023 = Evidence(
        citation: "Windred 외, SLEEP 2024 (UK Biobank 6만 명)",
        title: "Sleep regularity is a stronger predictor of mortality risk than sleep duration: A prospective cohort study",
        finding: "자고 일어나는 시각이 규칙적인 사람은 전체 사망 위험이 20~48% 낮았고, 규칙성이 수면시간보다 더 강한 예측 변수였어요.",
        doi: "10.1093/sleep/zsad253", level: .cohort)
    static let haghayegh2019 = Evidence(
        citation: "Haghayegh 외, Sleep Med Rev 2019",
        title: "Before-bedtime passive body heating by warm shower or bath to improve sleep: A systematic review and meta-analysis",
        finding: "연구 17편 종합: 취침 1~2시간 전 따뜻한 샤워·목욕이 잠드는 시간을 줄이고 수면의 질을 높였어요.",
        doi: "10.1016/j.smrv.2019.04.008", level: .metaAnalysis)
    static let brooks2006 = Evidence(
        citation: "Brooks & Lack, Sleep 2006",
        title: "A brief afternoon nap following nocturnal sleep restriction: which nap duration is most recuperative?",
        finding: "5시간만 잔 다음 날, 10분 낮잠이 바로 효과가 나고 오래 갔어요. 30분 낮잠은 깬 직후 오히려 멍해졌어요 (24명).",
        doi: "10.1093/sleep/29.6.831", level: .labStudy)
    static let stutz2019 = Evidence(
        citation: "Stutz 외, Sports Medicine 2019",
        title: "Effects of Evening Exercise on Sleep in Healthy Participants: A Systematic Review and Meta-Analysis",
        finding: "저녁 운동은 수면을 해치지 않았어요. 다만 취침 1시간 안에 끝나는 격한 운동은 잠들기·수면시간에 나쁠 수 있어요.",
        doi: "10.1007/s40279-018-1015-0", level: .metaAnalysis)
    static let ebrahim2013 = Evidence(
        citation: "Ebrahim 외, Alcohol Clin Exp Res 2013",
        title: "Alcohol and sleep I: effects on normal sleep",
        finding: "술은 빨리 잠들게 하지만, 밤 후반부 수면을 흐트러뜨려요.",
        doi: "10.1111/acer.12006", level: .review)
    static let edinger2021 = Evidence(
        citation: "Edinger 외, J Clin Sleep Med 2021 (미국수면의학회)",
        title: "Behavioral and psychological treatments for chronic insomnia disorder in adults: an AASM clinical practice guideline",
        finding: "만성 불면에는 인지행동치료(CBT-I)를 강하게 권고하고, 자극 조절(잠이 안 오면 침대를 벗어나기, 같은 시각 기상)도 단독 치료로 권해요. 수면위생만으로는 충분하지 않아요.",
        doi: "10.5664/jcsm.8986", level: .guideline)
    static let watson2015 = Evidence(
        citation: "Watson 외, J Clin Sleep Med 2015 (AASM·SRS 합의)",
        title: "Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the AASM and SRS",
        finding: "성인은 건강을 위해 꾸준히 하루 7시간 이상 자는 것이 좋아요.",
        doi: "10.5664/jcsm.4758", level: .consensus)
    static let roenneberg2003 = Evidence(
        citation: "Roenneberg 외, J Biol Rhythms 2003",
        title: "Life between Clocks: Daily Temporal Patterns of Human Chronotypes",
        finding: "쉬는 날 수면의 가운데 시각으로 아침형·저녁형(크로노타입)을 잴 수 있어요 (뮌헨 크로노타입 설문, MCTQ).",
        doi: "10.1177/0748730402239679", level: .cohort)

    // MARK: 전략

    static let all: [SleepStrategy] = [
        SleepStrategy(id: "regular-wake", title: "매일 같은 시각에 일어나기",
                      summary: "쉬는 날도 평일과 1시간 안쪽으로 맞춰요.", icon: "alarm",
                      when: [.morning], targets: [.irregular, .wakeTired, .lateBed],
                      evidence: [windred2023, edinger2021],
                      appHelp: "내일 기상 시각을 일정에서 거꾸로 계산하고, 들쭉날쭉한 정도를 기록 탭에서 보여 줘요."),
        SleepStrategy(id: "caffeine-cutoff", title: "커피는 취침 9시간 전까지",
                      summary: "취침 목표에서 거꾸로 '마지막 커피 시각'을 정해요.", icon: "cup.and.saucer",
                      when: [.morning, .day], targets: [.fallAsleep, .nightWake, .wakeTired],
                      evidence: [gardiner2023, drake2013],
                      appHelp: "아침 카드에 '오늘 커피는 몇 시까지'를 한 줄로 알려 줘요.",
                      caution: "카페인 분해 속도는 사람마다 2~10시간으로 달라요. 예민하다면 더 일찍 끊어요."),
        SleepStrategy(id: "screen-off", title: "취침 30분 전 휴대폰 내려놓기",
                      summary: "빛과 자극을 줄여 잠드는 시간을 당겨요.", icon: "iphone.slash",
                      when: [.night], targets: [.fallAsleep, .lateBed],
                      evidence: [he2020, chang2015],
                      appHelp: "밤 카드의 앱 사용 한도와 '오늘은 여기까지' 버튼, 한도 초과 알림으로 도와줘요."),
        SleepStrategy(id: "todo-offload", title: "자기 전 5분, 내일 할 일 적기",
                      summary: "머릿속 걱정을 종이(노션)로 옮겨요.", icon: "square.and.pencil",
                      when: [.night], targets: [.fallAsleep, .lateBed],
                      evidence: [scullin2018],
                      appHelp: "밤 카드에 '내일 할 일 적기' 버튼을 띄우고, 노션 할 일과 이어 줘요."),
        SleepStrategy(id: "morning-light", title: "일어나서 1시간 안에 밝은 빛 쬐기",
                      summary: "커튼을 열거나 10분 밖을 걸어요.", icon: "sun.max",
                      when: [.morning], targets: [.lateBed, .wakeTired, .irregular],
                      evidence: [wright2013],
                      appHelp: "아침 카드에 오늘 할 빛 쬐기를 한 줄로 알려 줘요. 저녁형일수록 먼저 추천해요."),
        SleepStrategy(id: "warm-shower", title: "취침 1~2시간 전 따뜻한 샤워",
                      summary: "몸이 식으며 졸음이 와요.", icon: "shower",
                      when: [.night], targets: [.fallAsleep],
                      evidence: [haghayegh2019],
                      appHelp: "취침 준비가 시작될 때(취침 90분 전) 밤 카드에 알려 줘요."),
        SleepStrategy(id: "short-nap", title: "낮잠은 10~20분, 늦은 오후 전",
                      summary: "길게 자면 깬 뒤 더 멍해요.", icon: "powersleep",
                      when: [.day], targets: [.dayFocus, .wakeTired],
                      evidence: [brooks2006],
                      appHelp: "잠이 부족한 날 낮 카드에 '15분 낮잠'과 알맞은 빈 시간을 제안해요.",
                      caution: "밤에 잠들기 어렵다면 낮잠은 줄이는 편이 좋아요."),
        SleepStrategy(id: "exercise-timing", title: "격한 운동은 취침 1시간 전까지",
                      summary: "저녁 운동은 괜찮아요. 아주 격한 운동만 일찍.", icon: "figure.run",
                      when: [.day, .night], targets: [.fallAsleep],
                      evidence: [stutz2019],
                      appHelp: "운동 일정이 취침 1시간 안에 있으면 낮 카드에서 알려 줘요."),
        SleepStrategy(id: "no-alcohol", title: "잠을 위해 술 마시지 않기",
                      summary: "빨리 잠들어도 새벽에 자주 깨요.", icon: "wineglass",
                      when: [.night], targets: [.nightWake, .wakeTired],
                      evidence: [ebrahim2013],
                      appHelp: "음주가 잦다고 답했다면 밤 카드에서 한 번 상기시켜요."),
        SleepStrategy(id: "stimulus-control", title: "20분 넘게 못 자면 잠시 침대 밖으로",
                      summary: "침대 = 잠이라는 연결을 되살려요.", icon: "bed.double",
                      when: [.night], targets: [.fallAsleep, .nightWake],
                      evidence: [edinger2021],
                      appHelp: "밤 카드의 호흡 화면에서 '잠이 안 오면' 안내로 보여 줘요.",
                      caution: "주 3번 이상, 3개월 넘게 잠들기 어렵다면 전문가(수면 클리닉)와 인지행동치료를 상의해 보세요."),
        SleepStrategy(id: "seven-hours", title: "7시간 이상 확보하기",
                      summary: "목표 수면에서 거꾸로 취침 시각을 정해요.", icon: "clock",
                      when: [.night, .morning], targets: [.wakeTired, .dayFocus],
                      evidence: [watson2015],
                      appHelp: "내일 기상 시각과 목표 수면으로 오늘 밤 취침 시각을 계산해요."),
    ]

    static func strategy(_ id: String) -> SleepStrategy? { all.first { $0.id == id } }

    // MARK: 개인화 (순수 함수)

    /// 쉬는 날 수면의 가운데 시각 (MSF, 자정 기준 분)
    static func midSleepFree(_ p: PersonalProfile) -> Int? {
        guard let b = p.freeBed, let w = p.freeWake else { return nil }
        let bed = b >= 12 * 60 ? b - 1440 : b       // 23:00 → -60
        let dur = w - bed
        guard dur > 0 else { return nil }
        return bed + dur / 2
    }

    /// 크로노타입 (MCTQ 방식 근사: 쉬는 날 수면 중간 시각)
    static func chronotype(_ p: PersonalProfile) -> Chronotype? {
        guard let msf = midSleepFree(p) else { return nil }
        if msf < 3 * 60 + 30 { return .early }
        if msf <= 5 * 60 { return .middle }
        return .late
    }

    /// 사회적 시차: 평일과 쉬는 날 수면 중간 시각 차이 (분)
    static func socialJetlag(_ p: PersonalProfile) -> Int? {
        guard let msf = midSleepFree(p), let b = p.workdayBed, let w = p.workdayWake else { return nil }
        let bed = b >= 12 * 60 ? b - 1440 : b
        guard w - bed > 0 else { return nil }
        return abs(msf - (bed + (w - bed) / 2))
    }

    /// 오늘의 마지막 커피 시각 (자정 기준 분, 30분 단위로 내림)
    static func caffeineCutoff(bedtime: Int, sensitive: Bool?) -> Int {
        let hours = sensitive == true ? 10 : 9
        var m = bedtime - hours * 60
        if m < 0 { m += 1440 }
        return m / 30 * 30
    }

    /// 전략 추천: (전략, 이유) — 점수 높은 순
    static func recommend(_ p: PersonalProfile, bedtime: Int, limit: Int = 4) -> [(SleepStrategy, String)] {
        var scored: [(SleepStrategy, Int, String, Int)] = []      // 전략, 점수, 이유, 원래 순서
        let chrono = chronotype(p)
        let jetlag = socialJetlag(p)
        for (index, s) in all.enumerated() {
            var score = 0
            var reason: String?
            let hit = s.targets.filter { p.problems.contains($0) }
            if !hit.isEmpty {
                score += 3 * hit.count
                reason = "‘\(hit[0].label)’라고 하셨어요"
            }
            switch s.id {
            case "caffeine-cutoff":
                let cut = caffeineCutoff(bedtime: bedtime, sensitive: p.caffeineSensitive)
                if let last = p.lastCaffeine, (p.caffeineCups ?? 1) > 0, last > cut, last < 20 * 60 {
                    score += 4
                    reason = "마지막 커피(\(Clock.hhmm(last)))가 권장 시각(\(Clock.hhmm(cut)))보다 늦어요"
                }
            case "regular-wake":
                if let j = jetlag, j >= 90 {
                    score += 3
                    reason = "평일과 쉬는 날 수면 시간대가 \(Clock.durationText(j)) 차이 나요"
                }
            case "morning-light":
                if chrono == .late {
                    score += 2
                    reason = reason ?? "저녁형이라 아침 빛이 생체시계를 앞당기는 데 도움이 돼요"
                }
            case "exercise-timing":
                if p.exercise == .lateNight {
                    score += 3
                    reason = "자기 직전에 운동한다고 하셨어요"
                }
            case "short-nap":
                if p.naps == true && p.problems.contains(.fallAsleep) { score -= 2 }   // 밤잠을 해칠 수 있음
            case "no-alcohol":
                if let a = p.alcoholPerWeek, a >= 3 {
                    score += 3
                    reason = "일주일에 \(a)번 정도 마신다고 하셨어요"
                }
            default: break
            }
            if score > 0 { scored.append((s, score, reason ?? s.summary, index)) }
        }
        // 아무 정보가 없으면 근거가 강한 기본 세트
        if scored.isEmpty {
            return ["regular-wake", "caffeine-cutoff", "screen-off"].compactMap { id in
                strategy(id).map { ($0, "근거가 가장 탄탄한 기본 전략이에요") }
            }
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.bestLevel.grade != b.0.bestLevel.grade { return a.0.bestLevel.grade < b.0.bestLevel.grade }
            return a.3 < b.3
        }
        .prefix(limit).map { ($0.0, $0.2) }
    }

    /// '지금' 화면에 띄울 오늘의 행동 한 줄
    static func todayAction(_ s: SleepStrategy, profile: UserProfile, personal: PersonalProfile) -> String {
        switch s.id {
        case "caffeine-cutoff":
            return "오늘 커피는 \(Clock.hhmm(caffeineCutoff(bedtime: profile.bedtimeMinutes, sensitive: personal.caffeineSensitive)))까지"
        case "regular-wake":
            return "내일도 \(Clock.hhmm(personal.workdayWake ?? profile.defaultWakeMinutes)) 전후로 일어나기"
        case "screen-off":
            return "\(Clock.hhmm((profile.bedtimeMinutes - 30 + 1440) % 1440))부터 휴대폰 내려놓기"
        case "todo-offload":
            return "자기 전 5분, 내일 할 일 적기"
        case "morning-light":
            return "1시간 안에 커튼 열고 10분 밝은 곳에 있기"
        case "warm-shower":
            return "\(Clock.hhmm((profile.bedtimeMinutes - 90 + 1440) % 1440)) 전후 따뜻한 샤워"
        case "short-nap":
            return "졸리면 오후 3시 전 15분만 낮잠"
        case "exercise-timing":
            return "격한 운동은 \(Clock.hhmm((profile.bedtimeMinutes - 60 + 1440) % 1440)) 전에 끝내기"
        case "no-alcohol":
            return "오늘 밤은 술 없이"
        case "stimulus-control":
            return "20분 넘게 잠이 안 오면 잠깐 일어나기"
        case "seven-hours":
            return "\(Clock.hhmm(profile.bedtimeMinutes)) 취침 = \(Clock.durationText(profile.goalSleepMinutes)) 확보"
        default:
            return s.title
        }
    }

    /// 지금 모드에 맞는, 사용자가 고른 전략 (최대 2개)
    static func forNow(_ mode: NowMode, personal: PersonalProfile) -> [SleepStrategy] {
        personal.chosen.compactMap(strategy).filter { $0.when.contains(mode) }.prefix(2).map { $0 }
    }
}
