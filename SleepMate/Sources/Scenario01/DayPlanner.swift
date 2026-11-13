import Foundation

// 시나리오 01: 수면 상태에 맞춘 다음 날 행동 및 일정 추천
// 발생 조건: 수면 결과가 들어왔을 때
// Context: 수면 점수·추세, 오늘 일정, 피로도, 과거 피드백
// 판단: 규칙 (나중에 LLM으로 교체/보강 가능)
// 실행: 추천 카드 + 일정 조정안(사용자 승인 후 캘린더에 반영)

struct DayRecommendation: Identifiable, Equatable {
    let key: String           // 피드백 집계용 고정 키
    let icon: String          // SF Symbol
    let title: String
    let detail: String
    var id: String { key }
}

struct ScheduleChange: Identifiable, Equatable {
    enum Kind: Equatable { case move, addBreak }
    let id = UUID()
    let kind: Kind
    let itemID: String?       // move일 때 원래 일정
    let title: String
    let fromStart: Date?
    let toStart: Date
    let toEnd: Date
    let reason: String
}

@MainActor
enum DayPlanner {
    struct Input {
        var stats: SleepStats?
        var score: Int?
        var daily: DailyContext
        var profile: UserProfile
        var items: [PlanItem]           // 오늘 일정
        var now: Date = Date()
        var skipped: (String) -> Bool = { _ in false }   // 자주 건너뛴 추천인지
    }

    /// 수면이 부족했다는 신호 (점수·시간·피로도 중 하나라도)
    static func lowSleepSignal(_ i: Input) -> Bool {
        if let sc = i.score, sc < 70 { return true }
        if let s = i.stats, s.asleepMin < i.profile.goalSleepMinutes - 60 { return true }
        if let f = i.daily.fatigue, f >= 4 { return true }
        return false
    }

    // MARK: 행동 추천

    static func recommendations(_ i: Input) -> [DayRecommendation] {
        let cal = Calendar.current
        let timed = i.items.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let low = lowSleepSignal(i)
        var out: [DayRecommendation] = []

        guard let s = i.stats else {
            return [DayRecommendation(key: "nodata", icon: "questionmark.circle",
                                      title: "판단하기 어려워요",
                                      detail: "수면 기록이 없어서 추측하지 않을게요. 홈에서 ↻ 버튼으로 기록을 가져와 주세요.")]
        }
        if s.daysSinceLastNight >= 2 {
            out.append(DayRecommendation(key: "stale", icon: "clock.badge.exclamationmark",
                                         title: "최근 기록이 \(s.daysSinceLastNight)일 전이에요",
                                         detail: "오늘 추천은 오래된 기록을 바탕으로 해서 정확하지 않을 수 있어요."))
        }

        // 1) 자연광: 첫 일정 전 바깥 10분
        let morningFirst = timed.first { cal.component(.hour, from: $0.start) < 13 }
        if let first = morningFirst {
            let walk = first.start.addingTimeInterval(-40 * 60)
            out.append(DayRecommendation(key: "light-walk", icon: "sun.max",
                                         title: "자연광: \(Fmt.time.string(from: walk)) 전후 10분 산책",
                                         detail: "‘\(first.title)’ 전에 바깥에서 햇빛을 받으면 몸이 깨어나는 데 도움이 돼요."))
        } else {
            out.append(DayRecommendation(key: "light-walk", icon: "sun.max",
                                         title: "오전 중 바깥에서 10분 산책",
                                         detail: "아침 햇빛은 생체 리듬을 맞추는 데 도움이 돼요."))
        }

        // 2) 카페인 (부족할 때)
        if low {
            out.append(DayRecommendation(key: "caffeine", icon: "cup.and.saucer",
                                         title: "커피는 오후 2시 전까지만",
                                         detail: "늦은 카페인은 오늘 밤 잠들기를 어렵게 할 수 있어요."))
        }

        // 3) 규칙적 식사
        let dinnerBy = i.profile.bedtimeMinutes - 180
        out.append(DayRecommendation(key: "meal", icon: "fork.knife",
                                     title: "식사는 거르지 말고 규칙적으로",
                                     detail: "점심은 12~13시 사이, 저녁은 \(Clock.text(dinnerBy)) 전까지 마치고 늦은 과식은 피하세요."))

        // 4) 연속 일정 사이 휴식
        if let block = longestBackToBackBlock(timed), block.minutes >= 120 {
            out.append(DayRecommendation(key: "break", icon: "pause.circle",
                                         title: "‘\(block.last.title)’ 뒤 10~15분 휴식",
                                         detail: "\(Fmt.time.string(from: block.first.start))부터 \(Clock.durationText(block.minutes)) 동안 일정이 이어져요. 중간에 잠깐 쉬어 가세요."))
        } else if low {
            out.append(DayRecommendation(key: "break", icon: "pause.circle",
                                         title: "집중 일정 사이에 짧은 휴식 확보",
                                         detail: "50분 집중 후 5~10분 쉬는 리듬을 추천해요."))
        }

        // 5) 낮잠 (부족할 때, 13~15시 비어 있으면)
        if low, let nap = freeSlot(in: timed, from: 13 * 60, to: 15 * 60, minutes: 30, day: i.now) {
            out.append(DayRecommendation(key: "nap", icon: "bed.double",
                                         title: "\(Fmt.time.string(from: nap)) 20분 이내 낮잠",
                                         detail: "오후 3시 이후의 긴 낮잠은 밤잠을 방해할 수 있어요."))
        }

        // 6) 오늘 밤 취침
        let bedtime = low ? i.profile.bedtimeMinutes - 30 : i.profile.bedtimeMinutes
        out.append(DayRecommendation(key: "bedtime", icon: "moon.stars",
                                     title: "오늘 밤 \(Clock.text(bedtime)) 취침 목표",
                                     detail: low ? "어젯밤 부족했던 만큼 평소보다 30분 일찍 잠자리에 들어 보세요."
                                                 : "평소 리듬을 유지하면 내일 아침도 개운할 거예요."))

        // 개인화(첫 단계): 자주 건너뛴 추천은 뒤로
        let kept = out.filter { !i.skipped($0.key) }
        let moved = out.filter { i.skipped($0.key) }
        return kept + moved
    }

    // MARK: 일정 조정안 (자동 적용 X, 사용자 승인 필요)

    static func proposals(_ i: Input) -> [ScheduleChange] {
        guard lowSleepSignal(i) else { return [] }
        let timed = i.items.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let cal = Calendar.current
        var out: [ScheduleChange] = []
        var occupied = timed

        // 1) 오전의 '바꿀 수 있는' 긴 작업 → 오후 빈 시간으로
        for item in timed where !item.isFixed && item.canModify
            && cal.component(.hour, from: item.start) < 12 && item.durationMin >= 60
            && item.start > i.now {
            let others = occupied.filter { $0.id != item.id }
            if let slot = freeSlot(in: others, from: 13 * 60, to: 19 * 60, minutes: item.durationMin, day: item.start) {
                let action = AgentAction(kind: .calendarChange, title: item.title, requiresApproval: true,
                                         touchesFixedEvent: item.isFixed)
                let g = AgentGuard.check(action, profile: i.profile)
                AgentLog.shared.add(.planToday, path: .rule, action: "‘\(item.title)’ 오후로 이동 제안",
                                    guardNote: g.note)
                guard g.allowed else { continue }
                let end = slot.addingTimeInterval(TimeInterval(item.durationMin * 60))
                out.append(ScheduleChange(kind: .move, itemID: item.id, title: item.title,
                                          fromStart: item.start, toStart: slot, toEnd: end,
                                          reason: "오전에는 집중력이 낮을 수 있어요. 집중이 필요한 작업을 오후로 옮기고 오전엔 가벼운 일을 먼저 처리해 보세요."))
                if let idx = occupied.firstIndex(where: { $0.id == item.id }) {
                    occupied[idx].start = slot
                    occupied[idx].end = end
                }
            }
        }

        // 2) 2시간 이상 연속 일정 뒤 15분 휴식 추가
        if let block = longestBackToBackBlock(occupied.sorted { $0.start < $1.start }), block.minutes >= 120 {
            let bStart = block.last.end
            let bEnd = bStart.addingTimeInterval(15 * 60)
            let clash = occupied.contains { $0.start < bEnd && $0.end > bStart }
            if !clash {
                out.append(ScheduleChange(kind: .addBreak, itemID: nil, title: "휴식 (SleepMate)",
                                          fromStart: nil, toStart: bStart, toEnd: bEnd,
                                          reason: "연속 일정 뒤에 짧은 휴식을 넣어 두면 오후 피로가 덜해요."))
            }
        }
        return out
    }

    // MARK: 유틸

    /// 쉬는 시간 없이(10분 미만 간격) 이어지는 가장 긴 일정 묶음
    static func longestBackToBackBlock(_ items: [PlanItem]) -> (first: PlanItem, last: PlanItem, minutes: Int)? {
        guard var first = items.first else { return nil }
        var last = first
        var best: (PlanItem, PlanItem, Int)?
        func close() {
            let m = Int(last.end.timeIntervalSince(first.start) / 60)
            if best == nil || m > best!.2 { best = (first, last, m) }
        }
        for it in items.dropFirst() {
            if it.start.timeIntervalSince(last.end) < 10 * 60 {
                if it.end > last.end { last = it }
            } else {
                close()
                first = it
                last = it
            }
        }
        close()
        return best.map { (first: $0.0, last: $0.1, minutes: $0.2) }
    }

    /// day의 [from, to) 분 범위에서 minutes 길이로 비어 있는 첫 시작 시각 (15분 단위)
    static func freeSlot(in items: [PlanItem], from: Int, to: Int, minutes: Int, day: Date) -> Date? {
        let base = Calendar.current.startOfDay(for: day)
        var t = from
        while t + minutes <= to {
            let s = base.addingTimeInterval(TimeInterval(t * 60))
            let e = s.addingTimeInterval(TimeInterval(minutes * 60))
            if !items.contains(where: { !$0.isAllDay && $0.start < e && $0.end > s }) { return s }
            t += 15
        }
        return nil
    }
}
