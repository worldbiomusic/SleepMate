import SwiftUI

// '지금' 탭의 판단 (순수 함수 — 셀프 테스트로 검증)
// 시간대에 따라 카드 하나만 보여 준다: 시작 · 아침 · 낮 · 밤

enum NowMode: String, Equatable {
    case start      // 수면 기록이 아직 없음 → 시작 3단계
    case morning    // 04:00 ~ 기상 + 3.5시간
    case day        // 그 사이
    case night      // 취침 준비 시작 ~ 취침 4시간 뒤(새벽)
}

/// 점수 숫자 대신 보여 줄 상태 단어 + 색
enum SleepStatus: Equatable {
    case great, okay, short, veryShort

    static func from(score: Int) -> SleepStatus {
        switch score {
        case 85...: return .great
        case 70..<85: return .okay
        case 55..<70: return .short
        default: return .veryShort
        }
    }

    var word: String {
        switch self {
        case .great: return "충분히 잤어요"
        case .okay: return "괜찮아요"
        case .short: return "조금 부족해요"
        case .veryShort: return "많이 부족해요"
        }
    }

    /// 짧은 꼬리표 (기록 탭·워치)
    var tag: String {
        switch self {
        case .great: return "좋음"
        case .okay: return "보통"
        case .short, .veryShort: return "부족"
        }
    }

    var color: Color {
        switch self {
        case .great: return .green
        case .okay: return .teal
        case .short: return .orange
        case .veryShort: return .red
        }
    }

    var icon: String {
        switch self {
        case .great: return "sun.max.fill"
        case .okay: return "cloud.sun.fill"
        case .short: return "cloud.fill"
        case .veryShort: return "cloud.rain.fill"
        }
    }
}

/// '다음 3가지' 한 줄
struct NextItem: Identifiable, Equatable {
    enum Kind: Equatable { case event, task, tip }
    let id: String
    let kind: Kind
    let time: Date?
    let title: String
    let icon: String
}

/// 아침 한 번 탭 체크인 (입력 안 하면 수면으로 추정)
enum CheckIn: String, CaseIterable, Identifiable {
    case fresh = "개운해요", normal = "보통", tired = "피곤해요"
    var id: String { rawValue }
    var fatigue: Int {
        switch self { case .fresh: return 1; case .normal: return 3; case .tired: return 4 }
    }
    var mood: Mood? {
        switch self { case .fresh: return .good; case .normal: return nil; case .tired: return .tired }
    }
    var emoji: String {
        switch self { case .fresh: return "😊"; case .normal: return "🙂"; case .tired: return "🥱" }
    }
    static func from(fatigue: Int?) -> CheckIn? {
        guard let f = fatigue else { return nil }
        return f <= 2 ? .fresh : (f >= 4 ? .tired : .normal)
    }
}

enum NowPlanner {
    /// 지금 보여 줄 모드
    /// - wakeMinutes: 오늘 실제 기상 시각(없으면 평소 기상)
    static func mode(now: Date, profile: UserProfile, hasData: Bool, wakeMinutes: Int?,
                     calendar: Calendar = .current) -> NowMode {
        guard hasData else { return .start }
        let rt = RealtimeContext(now: now, profile: profile, todayItems: [], calendar: calendar)
        let mins = Clock.minutes(of: now, calendar: calendar)
        // 취침 준비 시작부터 취침 4시간 뒤까지, 그리고 새벽 4시 전은 모두 '밤'
        if mins < 4 * 60 || (rt.minutesToBedtime <= profile.windDownLeadMinutes && rt.minutesToBedtime >= -240) {
            return .night
        }
        let wake = wakeMinutes ?? profile.defaultWakeMinutes
        if mins >= 4 * 60 && mins < wake + 210 { return .morning }
        return .day
    }

    /// 다음 3가지: 지금 이후 일정 · 오늘 할 일 · (모자라면) 추천 한 가지
    static func nextThree(now: Date, events: [PlanItem], tasks: [NotionTask],
                          tips: [DayRecommendation], limit: Int = 3,
                          calendar: Calendar = .current) -> [NextItem] {
        var timed: [NextItem] = []
        for e in events where !e.isAllDay && e.end > now && calendar.isDate(e.start, inSameDayAs: now) {
            timed.append(NextItem(id: "e-\(e.id)", kind: .event, time: e.start, title: e.title,
                                  icon: e.isFixed ? "calendar.badge.clock" : "calendar"))
        }
        var untimed: [NextItem] = []
        for t in tasks where !t.done && calendar.isDate(t.day, inSameDayAs: now) {
            if let tm = t.time {
                if tm > now.addingTimeInterval(-30 * 60) {
                    timed.append(NextItem(id: "t-\(t.id)", kind: .task, time: tm, title: t.title, icon: "checklist"))
                }
            } else {
                untimed.append(NextItem(id: "t-\(t.id)", kind: .task, time: nil, title: t.title, icon: "checklist"))
            }
        }
        var out = timed.sorted { ($0.time ?? now) < ($1.time ?? now) } + untimed
        if out.count < limit {
            for r in tips where r.key != "nodata" && r.key != "stale" {
                if out.count >= limit { break }
                out.append(NextItem(id: "r-\(r.key)", kind: .tip, time: nil, title: r.title, icon: r.icon))
            }
        }
        return Array(out.prefix(limit))
    }

    /// "6시간 10분 잤어요" + 평소와 비교 한 줄
    static func sleepLine(_ s: SleepStats) -> (main: String, compare: String?) {
        let main = "\(Clock.durationText(s.asleepMin)) 잤어요"
        guard let avg = s.avg7AsleepMin, s.nightsIn7 >= 3 else { return (main, nil) }
        let diff = s.asleepMin - avg
        if abs(diff) < 10 { return (main, "평소와 비슷해요") }
        return (main, diff > 0 ? "평소보다 \(Clock.durationText(diff)) 더 잤어요"
                               : "평소보다 \(Clock.durationText(-diff)) 짧아요")
    }

    /// 밤 카운트다운 문장
    static func countdown(minutesToBed m: Int) -> String {
        if m > 0 { return "취침까지 \(Clock.durationText(m))" }
        if m == 0 { return "지금이 취침 시간이에요" }
        return "취침 시간이 \(Clock.durationText(-m)) 지났어요"
    }
}
