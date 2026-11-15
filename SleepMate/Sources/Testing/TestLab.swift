import Foundation
import Observation

// 테스트 모드: 시나리오별 더미 데이터로 기능을 확인한다.
// - 실제 수면 기록·캘린더·Context는 바꾸지 않는다 (저장 안 함, 캘린더 쓰기는 가짜로 처리)
// - 끄면 실제 데이터로 돌아간다

enum SleepPreset: String, CaseIterable, Identifiable {
    case good = "충분히 잔 일주일"
    case short = "지난밤 수면 부족 (5시간)"
    case fragmented = "자주 깬 밤"
    case irregular = "들쭉날쭉한 취침"
    case withNap = "밤잠 + 낮잠"
    case noStages = "단계 없음 (아이폰만 기록)"
    case duplicated = "워치·아이폰 중복 기록"
    case stale = "오래된 기록 (5일 전)"
    case empty = "기록 없음"
    var id: String { rawValue }
}

enum DayPreset: String, CaseIterable, Identifiable {
    case typical = "평범한 하루"
    case morningFocus = "오전 집중 작업 + 수업"
    case busy = "연속 일정이 많은 날"
    case early = "아침 7시 일정"
    case late = "오후 3시 첫 일정"
    case empty = "일정 없음"
    var id: String { rawValue }
}

/// 현재 시각 (테스트 모드에서는 '오늘 아침 7:30'으로 고정해 아침 시나리오를 언제든 확인)
enum AppClock {
    @MainActor static var now: Date {
        if TestLab.shared.isOn, let t = TestLab.shared.simulatedNow { return t }
        return Date()
    }
}

@MainActor
@Observable
final class TestLab {
    static let shared = TestLab()

    var isOn = false
    var sleep: SleepPreset = .short
    var today: DayPreset = .morningFocus
    var tomorrow: DayPreset = .typical
    var fatigue = 4
    var mood: Mood? = .tired
    var screenCount = 40
    enum ClockMode: String, CaseIterable, Identifiable {
        case morning = "아침 07:30"
        case evening = "밤 22:40"
        case real = "실제 시각"
        var id: String { rawValue }
    }
    var clock: ClockMode = .morning
    var simulatedNow: Date? {
        let base = Calendar.current.startOfDay(for: Date())
        switch clock {
        case .morning: return base.addingTimeInterval(7.5 * 3600)
        case .evening: return base.addingTimeInterval(22 * 3600 + 40 * 60)
        case .real: return nil
        }
    }

    // 캘린더 '적용'을 흉내 내기 위한 변경 내역
    private var moved: [String: Date] = [:]
    private var added: [PlanItem] = []

    func apply(store: SleepStore, ctx: ContextStore, calendar: CalendarService) {
        isOn = true
        moved = [:]
        added = []
        store.loadTest(segments: TestData.sleep(sleep), label: sleep.rawValue)
        ctx.beginTest(fatigue: fatigue, mood: mood, screenCount: screenCount)
        calendar.revision += 1
        AgentLog.shared.add(event: "테스트 모드", path: .rule,
                            action: "\(sleep.rawValue) · 오늘 \(today.rawValue) · 내일 \(tomorrow.rawValue)",
                            guardNote: "실제 기록은 변경 안 함")
    }

    func exit(store: SleepStore, ctx: ContextStore, calendar: CalendarService) {
        isOn = false
        moved = [:]
        added = []
        store.restoreReal()
        ctx.endTest()
        calendar.revision += 1
    }

    func items(on day: Date, fixedKeywords: [String]) -> [PlanItem] {
        let preset = Calendar.current.isDateInToday(day) ? today : tomorrow
        var list = TestData.day(preset, on: day, fixedKeywords: fixedKeywords)
        for i in list.indices {
            if let to = moved[list[i].id] {
                let dur = list[i].end.timeIntervalSince(list[i].start)
                list[i].start = to
                list[i].end = to.addingTimeInterval(dur)
            }
        }
        list += added.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
        return list.sorted { $0.start < $1.start }
    }

    func move(id: String, to: Date) { moved[id] = to }

    func add(title: String, start: Date, end: Date) {
        added.append(PlanItem(id: "test-add-\(added.count)", title: title, start: start, end: end,
                              isAllDay: false, isFixed: false, canModify: true, calendarName: "테스트"))
    }
}

/// 더미 데이터 생성기 (셀프 테스트에서도 사용)
enum TestData {
    static let watch = "Apple Watch (테스트)"
    static let phone = "iPhone (테스트)"

    /// 기상일(daysAgo일 전) 기준으로 전날 밤 bedMinutes(자정 기준, 음수면 전날 저녁)부터 패턴을 이어 붙인다
    static func night(daysAgo: Int, bedMinutes: Int, pattern: [(SleepStage, Int)],
                      source: String = watch, now: Date = Date()) -> [SleepSegment] {
        let wakeDay = Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(daysAgo) * 86400)
        var t = wakeDay.addingTimeInterval(TimeInterval(bedMinutes * 60))
        var out: [SleepSegment] = []
        for (stage, m) in pattern {
            let e = t.addingTimeInterval(TimeInterval(m * 60))
            out.append(SleepSegment(id: UUID(), stage: stage, start: t, end: e, sourceName: source, sourceID: source))
            t = e
        }
        return out
    }

    /// 약 7시간 40분, 단계 구성이 무난한 밤
    static let normalPattern: [(SleepStage, Int)] = [
        (.core, 25), (.deep, 40), (.core, 35), (.rem, 20), (.core, 40), (.deep, 30), (.core, 30),
        (.awake, 3), (.rem, 30), (.core, 45), (.deep, 15), (.rem, 35), (.core, 40), (.awake, 4), (.rem, 30), (.core, 20),
    ]

    /// 약 5시간, 깊은 수면 적음
    static let shortPattern: [(SleepStage, Int)] = [
        (.core, 35), (.deep, 15), (.core, 45), (.rem, 20), (.core, 50), (.awake, 5), (.rem, 25), (.core, 45), (.rem, 20),
        (.core, 20),
    ]

    /// 자주 깬 밤 (깸 합계 약 70분)
    static let fragmentedPattern: [(SleepStage, Int)] = [
        (.core, 30), (.awake, 15), (.core, 30), (.deep, 25), (.awake, 12), (.core, 40), (.rem, 20), (.awake, 18),
        (.core, 45), (.rem, 25), (.awake, 14), (.core, 40), (.rem, 25), (.awake, 11), (.core, 25),
    ]

    static func sleep(_ p: SleepPreset, now: Date = Date()) -> [SleepSegment] {
        let bed = -30          // 23:30
        func week(skipFirst: Bool = false, offset: Int = 0, bedFor: (Int) -> Int = { _ in -30 }) -> [SleepSegment] {
            var out: [SleepSegment] = []
            for d in (skipFirst ? 1 : 0)..<7 {
                out += night(daysAgo: d + offset, bedMinutes: bedFor(d), pattern: normalPattern, now: now)
            }
            return out
        }
        switch p {
        case .good:
            return week(bedFor: { [-35, -20, -40, -25, -30, -15, -30][$0] })
        case .short:
            return night(daysAgo: 0, bedMinutes: 90, pattern: shortPattern, now: now) + week(skipFirst: true)
        case .fragmented:
            return night(daysAgo: 0, bedMinutes: bed, pattern: fragmentedPattern, now: now) + week(skipFirst: true)
        case .irregular:
            return week(bedFor: { [150, -120, 60, -60, 120, -90, 30][$0] })
        case .withNap:
            let napStart = Calendar.current.startOfDay(for: now).addingTimeInterval(-86400 + 14 * 3600)
            let nap = SleepSegment(id: UUID(), stage: .asleepUnspecified, start: napStart,
                                   end: napStart.addingTimeInterval(40 * 60), sourceName: watch, sourceID: watch)
            return week() + [nap]
        case .noStages:
            return (0..<7).flatMap { d in
                night(daysAgo: d, bedMinutes: bed, pattern: [(.inBed, 15), (.asleepUnspecified, 420), (.inBed, 10)],
                      source: phone, now: now)
            }
        case .duplicated:
            let phoneCopy = (0..<7).flatMap { d in
                night(daysAgo: d, bedMinutes: bed - 10, pattern: [(.asleepUnspecified, 470)], source: phone, now: now)
            }
            return week() + phoneCopy
        case .stale:
            return week(offset: 5)
        case .empty:
            return []
        }
    }

    static func day(_ p: DayPreset, on day: Date, fixedKeywords: [String]) -> [PlanItem] {
        let base = Calendar.current.startOfDay(for: day)
        let tag = Calendar.current.isDateInToday(day) ? "t" : "n"
        let rows: [(String, Int, Int)]
        switch p {
        case .typical:
            rows = [("AI응용융합연구 수업", 9 * 60, 10 * 60 + 30), ("점심 약속", 12 * 60, 13 * 60),
                    ("개인 프로젝트 작업", 14 * 60, 16 * 60)]
        case .morningFocus:
            rows = [("논문 집중 작업", 8 * 60 + 30, 10 * 60 + 30), ("AI응용융합연구 수업", 10 * 60 + 30, 12 * 60),
                    ("점심", 12 * 60 + 30, 13 * 60), ("팀 회의", 16 * 60, 17 * 60)]
        case .busy:
            rows = [("오전 강의", 9 * 60, 10 * 60 + 30), ("연구실 미팅", 10 * 60 + 30, 12 * 60),
                    ("논문 정리", 12 * 60, 13 * 60), ("세미나", 13 * 60, 14 * 60 + 30),
                    ("코딩 작업", 14 * 60 + 30, 16 * 60)]
        case .early:
            rows = [("아침 운동", 7 * 60, 8 * 60), ("수업", 10 * 60, 12 * 60)]
        case .late:
            rows = [("오후 회의", 15 * 60, 16 * 60)]
        case .empty:
            rows = []
        }
        return rows.map { title, s, e in
            PlanItem(id: "test-\(tag)-\(s)", title: title,
                     start: base.addingTimeInterval(TimeInterval(s * 60)),
                     end: base.addingTimeInterval(TimeInterval(e * 60)),
                     isAllDay: false,
                     isFixed: CalendarService.isFixed(title: title, hasAttendees: false, keywords: fixedKeywords),
                     canModify: true, calendarName: "테스트")
        }
    }

    /// 테스트용 노션 할 일 (오늘·내일)
    static func notion(on day: Date) -> [NotionTask] {
        let base = Calendar.current.startOfDay(for: day)
        let isToday = Calendar.current.isDateInToday(day)
        let rows: [(String, Int?, Bool)] = isToday
            ? [("AI융합연구 발표 PPT 마무리", nil, false), ("마트: 대파, 두부, 계란", nil, false),
               ("치과 전화해서 예약", nil, true), ("저녁 운동 30분", nil, false),
               ("대학원동 1층 특강", 18 * 60, false)]
            : [("석사 종합시험", 13 * 60 + 20, false), ("시험 범위 복습", nil, false)]
        return rows.enumerated().map { i, r in
            NotionTask(id: "test-notion-\(isToday ? "t" : "n")-\(i)", title: r.0, day: base,
                       time: r.1.map { base.addingTimeInterval(TimeInterval($0 * 60)) }, done: r.2,
                       cls: JevDecisions.classifyRuleNonisolated(r.0))
        }
    }
}
