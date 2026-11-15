import Foundation
import SwiftUI

// 셀프 테스트: 더미 데이터로 핵심 기능을 자동 검사한다.
// 앱 안(설정 → 테스트 → 셀프 테스트 실행)과 CI(실행 인자 -runSelfTests YES)에서 같은 코드가 돈다.
// 실제 기록·캐시·캘린더에는 쓰지 않는다.

struct TestResult: Identifiable {
    let id = UUID()
    let group: String
    let name: String
    let passed: Bool
    let detail: String
}

@MainActor
final class TestRecorder {
    private(set) var results: [TestResult] = []
    var group = ""

    func check(_ name: String, _ cond: Bool, _ detail: @autoclosure () -> String = "") {
        results.append(TestResult(group: group, name: name, passed: cond, detail: cond ? "" : detail()))
    }

    func equal<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
        check(name, actual == expected, "기대 \(expected), 실제 \(actual)")
    }
}

@MainActor
enum SelfTestSuite {
    static func run() -> [TestResult] {
        let t = TestRecorder()
        importTests(t)
        nightTests(t)
        scoreTests(t)
        reportTests(t)
        claudeTests(t)
        dayPlannerTests(t)
        alarmTests(t)
        windDownTests(t)
        clockTests(t)
        coachTests(t)
        presetTests(t)
        jevTests(t)
        notionTests(t)
        return t.results
    }

    // MARK: 도우미

    private static let cal = Calendar.current
    private static var today: Date { cal.startOfDay(for: Date()) }

    /// 오늘 기준 dayOffset일, h:m
    private static func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
        today.addingTimeInterval(Double(dayOffset) * 86400 + Double(h * 3600 + m * 60))
    }

    private static func seg(_ st: SleepStage, _ s: Date, _ e: Date, _ src: String = "watch") -> SleepSegment {
        SleepSegment(id: UUID(), stage: st, start: s, end: e, sourceName: src, sourceID: src)
    }

    private static func item(_ title: String, _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int,
                             day: Int = 0, fixed: Bool? = nil) -> PlanItem {
        let kw = UserProfile().fixedKeywords
        return PlanItem(id: "\(title)-\(sh)\(sm)", title: title, start: at(day, sh, sm), end: at(day, eh, em),
                        isAllDay: false,
                        isFixed: fixed ?? CalendarService.isFixed(title: title, hasAttendees: false, keywords: kw),
                        canModify: true, calendarName: "test")
    }

    private static func nights(_ p: SleepPreset) -> [SleepNight] {
        SleepStore.groupIntoNights(TestData.sleep(p))
    }

    private static func mins(_ t: TimeInterval) -> Int { Int((t / 60).rounded()) }

    // MARK: 1. 단축어 가져오기 해석

    static func importTests(_ t: TestRecorder) {
        t.group = "가져오기 (단축어 텍스트)"
        let r = SleepImport.parseShortcutText(
            "2026-11-13T00:12:00+09:00|2026-11-13T00:47:00+09:00|Core|Apple Watch")
        t.equal("ISO 형식 한 줄", r.segments.count, 1)
        t.equal("단계 Core → 코어", r.segments.first?.stage, .core)
        t.equal("길이 35분", r.segments.first.map { mins($0.duration) }, 35)
        t.equal("소스 이름", r.segments.first?.sourceName, "Apple Watch")

        let stages: [(String, SleepStage)] = [
            ("깊은 수면", .deep), ("REM 수면", .rem), ("코어", .core), ("깨어 있음", .awake),
            ("침대에 있음", .inBed), ("Asleep", .asleepUnspecified), ("In Bed", .inBed), ("Deep", .deep),
            ("Awake", .awake), ("REM", .rem), ("HKCategoryValueSleepAnalysisAsleepCore", .core),
            ("HKCategoryValueSleepAnalysisAsleepREM", .rem), ("HKCategoryValueSleepAnalysisAwake", .awake),
            ("HKCategoryValueSleepAnalysisInBed", .inBed), ("수면", .asleepUnspecified), ("3", .core),
        ]
        for (text, expected) in stages {
            t.equal("값 ‘\(text)’", SleepImport.parseStage(text), expected)
        }
        t.check("알 수 없는 값은 nil", SleepImport.parseStage("abc") == nil)

        let ko = SleepImport.parseDate("2026. 11. 13. 오전 1:05")
        t.equal("한국어 날짜(오전)", ko.map { Clock.minutes(of: $0) }, 65)
        let ko2 = SleepImport.parseDate("2026. 11. 13. 오후 11:05")
        t.equal("한국어 날짜(오후)", ko2.map { Clock.minutes(of: $0) }, 23 * 60 + 5)
        let ko3 = SleepImport.parseDate("2026년 11월 13일 오전 7:30")
        t.equal("한국어 날짜(년월일)", ko3.map { Clock.minutes(of: $0) }, 7 * 60 + 30)
        t.check("좁은 공백 포함 날짜", SleepImport.parseDate("2026. 11. 13.\u{202F}오전 1:05") != nil)
        t.check("소수점 초 ISO", SleepImport.parseDate("2026-11-13T00:12:00.123+09:00") != nil)

        let multi = SleepImport.parseShortcutText("""
        2026-11-13T00:00:00+09:00|2026-11-13T00:30:00+09:00|코어\r
        \r
        2026-11-13T00:30:00+09:00|2026-11-13T01:00:00+09:00|깊은 수면|Apple Watch\r
        잘못된 줄
        2026-11-13T02:00:00+09:00|2026-11-13T01:00:00+09:00|REM
        """)
        t.equal("CRLF·빈 줄 처리, 정상 2줄", multi.segments.count, 2)
        t.equal("잘못된 줄·끝<시작 건너뜀", multi.skipped.count, 2)
        t.equal("소스 생략 시 ‘단축어’", multi.segments.first?.sourceName, "단축어")
    }

    // MARK: 2. 밤 단위 묶기 · 중복 제거 · 낮잠 분리

    static func nightTests(_ t: TestRecorder) {
        t.group = "밤 묶기 · 중복 · 낮잠"
        // 겹치는 같은 단계는 한 번만
        let a = SleepStore.groupIntoNights([seg(.core, at(-1, 23), at(0, 1)), seg(.core, at(0, 0), at(0, 2))])
        t.equal("겹치는 구간 병합 (3시간)", a.first.map { mins($0.asleep) }, 180)

        // 워치 + 아이폰 중복
        let b = SleepStore.groupIntoNights([
            seg(.core, at(-1, 23), at(0, 3)), seg(.rem, at(0, 3), at(0, 6)),
            seg(.asleepUnspecified, at(-1, 22, 50), at(0, 6, 10), "phone"),
        ])
        t.equal("워치 기록만 사용 (7시간)", b.first.map { mins($0.asleep) }, 420)
        t.check("단계 데이터 있음", b.first?.hasDetailedStages == true)
        t.check("아이폰 ‘단계 미상’ 제외", b.first?.stageTotals[.asleepUnspecified] == nil)

        // 자정을 넘는 밤은 하나로
        let c = SleepStore.groupIntoNights([seg(.core, at(-1, 23, 30), at(0, 0, 30)), seg(.deep, at(0, 0, 30), at(0, 6, 30))])
        t.equal("자정 넘는 밤 = 1개", c.count, 1)
        t.equal("기상일 = 오늘", c.first?.day, today)

        // 밤잠 + 낮잠 (사용자 실제 데이터에서 발견: 03:06 → 18:28로 표시되던 문제)
        let d = SleepStore.groupIntoNights([
            seg(.core, at(-1, 23), at(0, 3)), seg(.deep, at(0, 3), at(0, 7)),
            seg(.asleepUnspecified, at(0, 14), at(0, 14, 40)),
        ])
        t.equal("낮잠은 같은 날로 묶이되", d.count, 1)
        t.equal("기상 시각은 밤잠 기준 07:00", d.first?.wakeTime.map { Clock.minutes(of: $0) }, 7 * 60)
        t.equal("밤잠 8시간", d.first.map { mins($0.asleep) }, 480)
        t.equal("낮잠 40분 따로", d.first.map { mins($0.napSleep) }, 40)

        // 같은 워치에서 단계 + 단계 미상이 겹칠 때
        let e = SleepStore.groupIntoNights([
            seg(.core, at(-1, 23), at(0, 3)), seg(.asleepUnspecified, at(-1, 23), at(0, 7)),
        ])
        t.equal("겹친 단계 미상은 남는 부분만 (4시간)", e.first?.stageTotals[.asleepUnspecified].map { mins($0) }, 240)
        t.equal("총 수면 8시간", e.first.map { mins($0.asleep) }, 480)

        // 18시 이후 잠든 수면은 다음 날로
        let f = SleepStore.groupIntoNights([seg(.core, at(-1, 19), at(-1, 20))])
        t.equal("18시 이후 수면 → 다음 날", f.first?.day, today)

        t.equal("기록 없음 → 0일", SleepStore.groupIntoNights([]).count, 0)
    }

    // MARK: 3. 통계 · 수면 점수

    static func scoreTests(_ t: TestRecorder) {
        t.group = "통계 · 수면 점수"
        let goal = UserProfile().goalSleepMinutes

        let good = SleepStats(nights: nights(.good))
        let goodScore = good.map { SleepScore.compute($0, goalMinutes: goal) }
        t.check("충분한 밤 점수 ≥ 80", (goodScore?.total ?? 0) >= 80, "점수 \(goodScore?.total ?? -1)")
        t.equal("7일 기록 7밤", good?.nightsIn7, 7)

        let short = SleepStats(nights: nights(.short))
        let shortScore = short.map { SleepScore.compute($0, goalMinutes: goal) }
        t.check("부족한 밤 점수 < 70", (shortScore?.total ?? 100) < 70, "점수 \(shortScore?.total ?? -1)")
        t.equal("부족한 밤 라벨", shortScore?.label, "부족")
        t.check("부족한 밤 < 평균", (short?.asleepMin ?? 0) < (short?.avg7AsleepMin ?? 0))

        let irr = SleepStats(nights: nights(.irregular))
        let irrScore = irr.map { SleepScore.compute($0, goalMinutes: goal) }
        t.check("불규칙 취침 편차 ≥ 60분", (irr?.bedtimeSpreadMin ?? 0) >= 60, "편차 \(irr?.bedtimeSpreadMin ?? -1)")
        t.check("불규칙 → 규칙성 점수 낮음", (irrScore?.regularity ?? 15) <= 5, "규칙성 \(irrScore?.regularity ?? -1)")
        t.check("규칙적 → 규칙성 점수 높음", (goodScore?.regularity ?? 0) >= 12, "규칙성 \(goodScore?.regularity ?? -1)")

        // 자정 앞뒤 취침은 편차가 작아야 함 (23:40, 00:20, 23:50)
        let mid = SleepStore.groupIntoNights([
            seg(.core, at(-1, 23, 40), at(0, 7)), seg(.core, at(-1, 0, 20), at(-1, 7)),
            seg(.core, at(-3, 23, 50), at(-2, 6, 50)),
        ])
        let midStats = SleepStats(nights: mid)
        t.check("자정 앞뒤 취침 편차 < 30분", (midStats?.bedtimeSpreadMin ?? 999) < 30,
                "편차 \(midStats?.bedtimeSpreadMin ?? -1)")

        let stale = SleepStats(nights: nights(.stale))
        t.equal("오래된 기록 → 5일 전", stale?.daysSinceLastNight, 5)

        let noSt = SleepStats(nights: nights(.noStages))
        t.check("단계 없음 표시", noSt?.hasStages == false)
        t.equal("단계 없음 → 단계 점수 중간값 9", noSt.map { SleepScore.compute($0, goalMinutes: goal).stages }, 9)

        let frag = SleepStats(nights: nights(.fragmented))
        t.check("자주 깬 밤 깸 ≥ 60분", (frag?.awakeMin ?? 0) >= 60, "깸 \(frag?.awakeMin ?? -1)분")

        let dup = SleepStats(nights: nights(.duplicated))
        t.check("중복 기록이어도 8시간 이하", (dup?.asleepMin ?? 999) <= 480, "\(dup?.asleepMin ?? -1)분")

        t.check("기록 없음 → 통계 없음", SleepStats(nights: nights(.empty)) == nil)
        t.check("점수 0~100 범위", (goodScore?.total ?? -1) <= 100 && (shortScore?.total ?? -1) >= 0)
    }

    // MARK: 4. 기본 요약 (시나리오 05)

    static func reportTests(_ t: TestRecorder) {
        t.group = "05 기본 요약"
        if let s = SleepStats(nights: nights(.short)) {
            let r = RuleReporter.make(s)
            t.check("부족 → 카페인 추천", r.recommendations.contains { $0.contains("커피") })
            t.check("부족 → 일찍 자기 추천", r.recommendations.contains { $0.contains("일찍") })
            t.check("추천 2~4개", (2...4).contains(r.recommendations.count), "\(r.recommendations.count)개")
            t.check("음성 원고에 추천 포함", r.speech.contains("1번"))
        } else { t.check("부족 데이터 통계", false, "nil") }

        if let s = SleepStats(nights: nights(.good)) {
            let r = RuleReporter.make(s)
            t.check("충분 → 리듬 유지", r.recommendations.contains { $0.contains("유지") })
        }
        if let s = SleepStats(nights: nights(.stale)) {
            let r = RuleReporter.make(s)
            t.check("오래된 기록 안내 (요약)", r.summary.contains("5일 전"))
            t.check("오래된 기록 안내 (음성)", r.speech.contains("5일 전"))
        }
        if let s = SleepStats(nights: nights(.fragmented)) {
            let r = RuleReporter.make(s)
            t.check("자주 깸 → 깬 시간 언급", r.summary.contains("깨어 있던"))
            t.check("자주 깸 → 화면 멀리하기", r.recommendations.contains { $0.contains("휴대폰") })
        }
        if let s = SleepStats(nights: nights(.irregular)) {
            let r = RuleReporter.make(s)
            t.check("불규칙 → 일정한 취침 추천", r.recommendations.contains { $0.contains("잠드는") })
        }
        if let s = SleepStats(nights: nights(.noStages)) {
            let r = RuleReporter.make(s)
            t.check("단계 없음 → 단계 문장 생략", !r.summary.contains("깊은 수면 0분"))
        }
    }

    // MARK: 5. Claude 응답 해석 · 전송 내용

    static func claudeTests(_ t: TestRecorder) {
        t.group = "05 Claude 연동 (오프라인 검사)"
        let text = """
        네, 요약입니다.
        ```json
        {"summary": "지난밤 6시간 잤어요.", "recommendations": ["오후 2시 이후 커피 피하기", "", "20분 낮잠"], "speech": "좋은 아침이에요."}
        ```
        """
        let r = try? ClaudeClient.parse(text: text, day: today, model: "m")
        t.check("앞뒤 글·코드블록이 있어도 해석", r != nil)
        t.equal("빈 추천 제거", r?.recommendations.count, 2)
        t.equal("출처 = Claude", r?.source, .claude)
        t.check("JSON 없으면 오류", (try? ClaudeClient.parse(text: "죄송합니다", day: today, model: "m")) == nil)
        t.check("필드 누락이면 오류",
                (try? ClaudeClient.parse(text: "{\"summary\": \"a\"}", day: today, model: "m")) == nil)

        if let s = SleepStats(nights: nights(.short)) {
            let msg = ClaudeClient.userMessage(s)
            t.check("수치 포함", msg.contains("asleepMinutes"))
            t.check("원시 구간·기기 이름 미포함", !msg.contains("Apple Watch") && !msg.contains("sourceName"))
            if let a = msg.firstIndex(of: "{"), let b = msg.lastIndex(of: "}") {
                let ok = (try? JSONSerialization.jsonObject(with: Data(msg[a...b].utf8))) != nil
                t.check("전송 JSON 형식 유효", ok)
            } else {
                t.check("전송 JSON 형식 유효", false, "JSON 없음")
            }
        }
    }

    // MARK: 6. 시나리오 01 행동·일정 추천

    static func dayPlannerTests(_ t: TestRecorder) {
        t.group = "01 행동·일정 추천"
        let profile = UserProfile()
        let morning = at(0, 7, 30)
        let focusDay = TestData.day(.morningFocus, on: today, fixedKeywords: profile.fixedKeywords)
        let busyDay = TestData.day(.busy, on: today, fixedKeywords: profile.fixedKeywords)

        func input(_ p: SleepPreset, _ items: [PlanItem], fatigue: Int? = nil, now: Date? = nil,
                   skipped: @escaping (String) -> Bool = { _ in false }) -> DayPlanner.Input {
            let s = SleepStats(nights: nights(p))
            let sc = s.map { SleepScore.compute($0, goalMinutes: profile.goalSleepMinutes).total }
            return DayPlanner.Input(stats: s, score: sc,
                                    daily: DailyContext(date: today, fatigue: fatigue),
                                    profile: profile, items: items, now: now ?? morning, skipped: skipped)
        }

        let empty = DayPlanner.recommendations(input(.empty, focusDay))
        t.equal("기록 없음 → 판단 보류 1개", empty.map(\.key), ["nodata"])

        let low = input(.short, focusDay)
        t.check("수면 부족 신호", DayPlanner.lowSleepSignal(low))
        t.check("충분 + 피로 2 → 신호 없음", !DayPlanner.lowSleepSignal(input(.good, focusDay, fatigue: 2)))
        t.check("충분해도 피로 4 → 신호", DayPlanner.lowSleepSignal(input(.good, focusDay, fatigue: 4)))

        let recs = DayPlanner.recommendations(low)
        t.check("카페인 추천", recs.contains { $0.key == "caffeine" })
        t.check("첫 일정 전 산책 시각", recs.first { $0.key == "light-walk" }?.title.contains("7:50") == true,
                recs.first { $0.key == "light-walk" }?.title ?? "")
        let bedRec = recs.first { $0.key == "bedtime" }?.title ?? ""
        t.check("부족 → 30분 일찍 취침", bedRec.contains(Clock.text(profile.bedtimeMinutes - 30)), bedRec)
        t.check("오래된 기록 안내 먼저",
                DayPlanner.recommendations(input(.stale, focusDay)).first?.key == "stale")

        let reordered = DayPlanner.recommendations(input(.short, focusDay, skipped: { $0 == "light-walk" }))
        t.equal("자주 건너뛴 추천은 맨 뒤", reordered.last?.key, "light-walk")

        // 일정 조정안
        let props = DayPlanner.proposals(low)
        let move = props.first { $0.kind == .move }
        t.equal("오전 집중 작업 이동 제안", move?.title, "논문 집중 작업")
        t.check("오후(13시 이후)로 이동", (move.map { Clock.minutes(of: $0.toStart) } ?? 0) >= 13 * 60,
                move.map { Fmt.time.string(from: $0.toStart) } ?? "없음")
        t.check("고정 일정(수업·회의)은 옮기지 않음",
                !props.contains { $0.title.contains("수업") || $0.title.contains("회의") })
        if let m = move {
            let others = focusDay.filter { $0.id != m.itemID }
            let clash = others.contains { $0.start < m.toEnd && $0.end > m.toStart }
            t.check("옮긴 시간이 다른 일정과 안 겹침", !clash)
            t.equal("길이 유지", Int(m.toEnd.timeIntervalSince(m.toStart) / 60), 120)
        }
        t.check("충분 + 피로 2 → 조정안 없음", DayPlanner.proposals(input(.good, focusDay, fatigue: 2)).isEmpty)
        t.check("이미 지난 일정은 옮기지 않음",
                DayPlanner.proposals(input(.short, focusDay, now: at(0, 11))).first { $0.kind == .move } == nil)

        let busyProps = DayPlanner.proposals(input(.short, busyDay))
        t.check("연속 일정 뒤 휴식 추가 제안", busyProps.contains { $0.kind == .addBreak })
        if let b = busyProps.first(where: { $0.kind == .addBreak }) {
            t.check("휴식이 다른 일정과 안 겹침",
                    !busyDay.contains { $0.start < b.toEnd && $0.end > b.toStart })
        }
        let block = DayPlanner.longestBackToBackBlock(busyDay)
        t.equal("연속 일정 7시간", block?.minutes, 420)

        let free = DayPlanner.freeSlot(in: focusDay, from: 12 * 60, to: 18 * 60, minutes: 60, day: today)
        t.check("빈 시간 찾기 (점심 뒤 13:00)", free.map { Clock.minutes(of: $0) } == 13 * 60,
                free.map { Fmt.time.string(from: $0) } ?? "없음")

        // GUARD
        let fixedMove = AgentGuard.check(AgentAction(kind: .calendarChange, title: "수업", requiresApproval: true,
                                                     touchesFixedEvent: true), profile: profile)
        t.check("GUARD: 고정 일정 변경 차단", !fixedMove.allowed)
        let noApproval = AgentGuard.check(AgentAction(kind: .calendarChange, title: "작업", requiresApproval: false),
                                          profile: profile)
        t.check("GUARD: 승인 없는 변경 차단", !noApproval.allowed)

        let markers = DayPlanner.markers(low)
        t.check("타임라인 취침 표시 = 30분 일찍",
                markers.contains { $0.label.contains("취침") && Clock.minutes(of: $0.time) == profile.bedtimeMinutes - 30 })
    }

    // MARK: 7. 시나리오 04 기상 알람

    static func alarmTests(_ t: TestRecorder) {
        t.group = "04 기상 알람"
        let p = UserProfile()   // 준비 60, 이동 30, 최소 6:00, 평소 7:00, 목표 7.5h
        let nine = AlarmPlanner.plan(profile: p, tomorrowItems: [item("AI 수업", 9, 0, 10, 30, day: 1)])
        t.equal("9시 수업 → 07:30 기상", Clock.hhmm(nine.wakeMinutes), "07:30")
        t.equal("취침 목표 23:45", Clock.hhmm(nine.bedtimeMinutes), "23:45")

        let seven = AlarmPlanner.plan(profile: p, tomorrowItems: TestData.day(.early, on: at(1, 0), fixedKeywords: p.fixedKeywords))
        t.equal("7시 일정 → 최소 기상 06:00", Clock.hhmm(seven.wakeMinutes), "06:00")
        t.check("최소 기상으로 조정 표시", seven.clampedByEarliest)
        t.equal("가장 이른 일정 기준", seven.firstEvent?.title, "아침 운동")

        let none = AlarmPlanner.plan(profile: p, tomorrowItems: [])
        t.equal("일정 없음 → 평소 07:00", Clock.hhmm(none.wakeMinutes), "07:00")

        let late = AlarmPlanner.plan(profile: p, tomorrowItems: TestData.day(.late, on: at(1, 0), fixedKeywords: p.fixedKeywords))
        t.equal("오후 3시 일정 → 늦잠 제한 08:00", Clock.hhmm(late.wakeMinutes), "08:00")

        let odd = AlarmPlanner.plan(profile: p, tomorrowItems: [item("수업", 9, 7, 10, 0, day: 1)])
        t.equal("5분 단위 내림 (9:07 → 07:35)", Clock.hhmm(odd.wakeMinutes), "07:35")

        let allDay = PlanItem(id: "ad", title: "휴가", start: at(1, 0), end: at(2, 0), isAllDay: true,
                              isFixed: false, canModify: true, calendarName: "")
        t.equal("종일 일정은 무시", Clock.hhmm(AlarmPlanner.plan(profile: p, tomorrowItems: [allDay]).wakeMinutes), "07:00")

        let alarm = AgentGuard.check(AgentAction(kind: .alarm, title: "07:30", requiresApproval: false), profile: p)
        t.check("GUARD: 알람은 항상 허용", alarm.allowed)
    }

    // MARK: 8. 시나리오 02 취침 준비

    static func windDownTests(_ t: TestRecorder) {
        t.group = "02 취침 준비"
        var p = UserProfile()   // 23:30, 90분 전
        let steps = WindDownPlan.steps(p)
        t.equal("단계 시각 22:00 · 22:30 · 23:00", steps.map { Clock.hhmm($0.minutes) }, ["22:00", "22:30", "23:00"])
        t.equal("목표 확인 알림에 +5/+10 버튼", steps[1].category, NotificationService.screenCheckCategory)

        t.check("GUARD: 알림 최대 개수 초과 차단",
                !AgentGuard.check(AgentAction(kind: .notify, title: "x", requiresApproval: false),
                                  profile: p, eveningNotificationsSent: p.maxEveningNotifications).allowed)
        p.notifyWindDown = false
        t.check("GUARD: 알림 끔이면 차단",
                !AgentGuard.check(AgentAction(kind: .notify, title: "x", requiresApproval: false), profile: p).allowed)
        p = UserProfile()

        t.check("메시지: 기록 없음", WindDownPlan.screenMessage(count: 0, goal: 50, unit: "개", stopped: false).contains("아직"))
        t.check("메시지: 5개 남음", WindDownPlan.screenMessage(count: 45, goal: 50, unit: "개", stopped: false).contains("5개"))
        t.check("메시지: 목표 도달", WindDownPlan.screenMessage(count: 50, goal: 50, unit: "개", stopped: false).contains("도달"))
        t.check("메시지: 초과", WindDownPlan.screenMessage(count: 60, goal: 50, unit: "개", stopped: false).contains("10개 더"))
        t.check("메시지: 멈춤", WindDownPlan.screenMessage(count: 60, goal: 50, unit: "개", stopped: true).contains("여기까지"))

        t.equal("21:00 → 취침까지 150분", RealtimeContext(now: at(0, 21), profile: p, todayItems: []).minutesToBedtime, 150)
        t.equal("23:00 → 30분", RealtimeContext(now: at(0, 23), profile: p, todayItems: []).minutesToBedtime, 30)
        t.check("02:00 → 지남(음수)", RealtimeContext(now: at(0, 2), profile: p, todayItems: []).minutesToBedtime < 0)
        t.equal("12:00 → 690분", RealtimeContext(now: at(0, 12), profile: p, todayItems: []).minutesToBedtime, 690)

        var p2 = UserProfile()
        p2.bedtimeMinutes = 30   // 00:30 취침
        t.equal("자정 넘는 취침 목표: 23:00 → 90분",
                RealtimeContext(now: at(0, 23), profile: p2, todayItems: []).minutesToBedtime, 90)
        t.equal("자정 넘는 취침 단계 첫 알림 23:00", Clock.hhmm(WindDownPlan.steps(p2)[0].minutes), "23:00")

        let music = WindDownPlan.music(for: .stressed, preference: "피아노")
        t.equal("음악 3곡", music.count, 3)
        t.check("스트레스 → 빗소리", music.first?.title.contains("빗소리") == true)

        let rt = RealtimeContext(now: at(0, 9), profile: p, todayItems: [item("수업", 10, 0, 11, 0), item("회의", 8, 0, 8, 30)])
        t.equal("다음 일정 = 지금 이후 첫 일정", rt.nextEvent?.title, "수업")
    }

    // MARK: 9. 시각 유틸 · 컨디션 곡선

    static func clockTests(_ t: TestRecorder) {
        t.group = "시각 · 컨디션 곡선"
        t.equal("음수 분 → 23:45", Clock.hhmm(-15), "23:45")
        t.equal("오후 11:30", Clock.text(23 * 60 + 30), "오후 11:30")
        t.equal("자정 = 오전 12:00", Clock.text(0), "오전 12:00")
        t.equal("정오 = 오후 12:00", Clock.text(12 * 60), "오후 12:00")
        t.equal("분 → 날짜 → 분", Clock.minutes(of: Clock.date(fromMinutes: 7 * 60 + 5)), 7 * 60 + 5)
        t.equal("기간 표시", Clock.durationText(95), "1시간 35분")

        let curve = EnergyModel.curve(wakeMinutes: 7 * 60, bedMinutes: 23 * 60 + 30, score: 85, day: today)
        t.check("곡선 시작 = 기상", curve.first.map { Clock.minutes(of: $0.time) } == 7 * 60)
        t.check("곡선 끝 = 취침", curve.last.map { Clock.minutes(of: $0.time) } == 23 * 60 + 30)
        t.check("시간 순서", zip(curve, curve.dropFirst()).allSatisfy { $0.time < $1.time })
        let lateBed = EnergyModel.curve(wakeMinutes: 7 * 60, bedMinutes: 30, score: 85, day: today)
        t.check("자정 넘는 취침도 끝이 다음 날", (lateBed.last?.time ?? .distantPast) > (lateBed.first?.time ?? .distantFuture))
        let lowCurve = EnergyModel.curve(wakeMinutes: 7 * 60, bedMinutes: 23 * 60 + 30, score: 40, day: today)
        t.check("점수 낮으면 컨디션 최고점도 낮음",
                (lowCurve.map(\.level).max() ?? 0) < (curve.map(\.level).max() ?? 0))
        let earlyWake = EnergyModel.curve(wakeMinutes: 5 * 60, bedMinutes: 22 * 60, score: 80, day: today)
        t.check("일찍 일어나도 곡선 생성", earlyWake.count >= 5, "\(earlyWake.count)점")
    }

    // MARK: 10. 수면 코치 (요약 갱신)

    static func coachTests(_ t: TestRecorder) {
        t.group = "05 수면 코치"
        let coach = CoachStore()
        let good = nights(.good)
        let short = nights(.short)
        let g = SleepStats(nights: good)
        let s = SleepStats(nights: short)
        t.check("두 프리셋의 통계가 다름", g != s)
        coach.report = nil
        coach.debugUpdateSync(nights: good)
        let first = coach.report?.summary
        coach.debugUpdateSync(nights: short)
        let second = coach.report?.summary
        t.check("같은 날이라도 수치가 바뀌면 요약 갱신", first != nil && second != nil && first != second)
        coach.debugUpdateSync(nights: short)
        t.equal("수치가 같으면 요약 유지", coach.report?.summary, second)
        coach.debugUpdateSync(nights: [])
        t.check("기록 없으면 요약 없음", coach.report == nil)
    }

    // MARK: 11. 테스트 프리셋 자체 검사

    static func presetTests(_ t: TestRecorder) {
        t.group = "테스트 데이터 프리셋"
        for p in SleepPreset.allCases where p != .empty {
            let n = nights(p)
            t.check("‘\(p.rawValue)’ 밤 생성", !n.isEmpty)
        }
        let nap = nights(.withNap)
        t.check("낮잠 프리셋: 낮잠 분리됨", nap.contains { $0.napSleep >= 30 * 60 })
        let kw = UserProfile().fixedKeywords
        for d in DayPreset.allCases {
            let items = TestData.day(d, on: today, fixedKeywords: kw)
            t.check("‘\(d.rawValue)’ 일정 시간 순·겹침 없음",
                    zip(items, items.dropFirst()).allSatisfy { $0.end <= $1.start })
        }
    }
}

// MARK: - 화면

struct SelfTestView: View {
    @State private var results: [TestResult] = []
    @State private var ran = false

    private var groups: [String] {
        var seen: [String] = []
        for r in results where !seen.contains(r.group) { seen.append(r.group) }
        return seen
    }

    var body: some View {
        List {
            Section {
                let failed = results.filter { !$0.passed }.count
                HStack {
                    Image(systemName: !ran ? "checklist" : (failed == 0 ? "checkmark.seal.fill" : "xmark.octagon.fill"))
                        .font(.largeTitle)
                        .foregroundStyle(!ran ? Color.secondary : (failed == 0 ? Color.green : Color.red))
                    VStack(alignment: .leading) {
                        Text(!ran ? "아직 실행 전" : (failed == 0 ? "모두 통과" : "\(failed)개 실패"))
                            .font(.headline)
                        if ran { Text("총 \(results.count)개 검사").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button(ran ? "다시 실행" : "실행") { runNow() }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(groups, id: \.self) { g in
                let list = results.filter { $0.group == g }
                Section {
                    ForEach(list) { r in
                        HStack(alignment: .top) {
                            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.callout)
                                if !r.detail.isEmpty {
                                    Text(r.detail).font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(g)  \(list.filter(\.passed).count)/\(list.count)")
                }
            }
        }
        .navigationTitle("셀프 테스트")
        .onAppear { if !ran && UserDefaults.standard.bool(forKey: "runSelfTests") { runNow() } }
    }

    private func runNow() {
        results = SelfTestSuite.run()
        ran = true
    }
}

/// CI용: 실행 인자 -runSelfTests YES 이면 시작할 때 실행하고 결과를 stderr로 출력
@MainActor
enum SelfTestCLI {
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "runSelfTests") else { return }
        let results = SelfTestSuite.run()
        for r in results {
            let line = "[SelfTest] \(r.passed ? "PASS" : "FAIL") [\(r.group)] \(r.name)\(r.detail.isEmpty ? "" : " — \(r.detail)")\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        let failed = results.filter { !$0.passed }.count
        FileHandle.standardError.write(Data("[SelfTest] SUMMARY total=\(results.count) failed=\(failed)\n".utf8))
    }

}

@MainActor
extension SelfTestSuite {
    // MARK: Jev (요청 형식 · 응답 해석 · 규칙 대체)

    static func jevTests(_ t: TestRecorder) {
        t.group = "Jev 빠른 판단"
        let body = JevClient.body(model: "jev-latest", state: ["a": 1],
                                  questions: ["q": .noul(instructions: "nudge?", yes: "y", no: "n"),
                                              "c": .choice(instructions: "kind", options: ["x": "X", "y": "Y"]),
                                              "s": .score(instructions: "focus", levels: ["low", "mid", "high"])])
        let qs = body["questions"] as? [String: Any] ?? [:]
        t.equal("모델 이름", body["model"] as? String ?? "", "jev-latest")
        t.equal("질문 3개 인코딩", qs.count, 3)
        t.equal("noul 타입", (qs["q"] as? [String: Any])?["type"] as? String ?? "", "noul")
        t.equal("score 단계 수", (((qs["s"] as? [String: Any])?["criteria"]) as? [Any])?.count ?? 0, 3)
        t.check("JSON 직렬화 가능", JSONSerialization.isValidJSONObject(body))

        let sample = """
        {"answers":{"nudge":{"type":"noul","noul":0.82,"confidence":0.9},
         "kind":{"type":"choice","choice":"deep_focus","confidence":0.7,"probabilities":{"deep_focus":0.7,"errand":0.3}},
         "focus":{"type":"score","score":1.6,"legend":{"0":"low","1":"mid","2":"high"}}}}
        """
        if let a = try? JevClient.parse(Data(sample.utf8)) {
            t.check("noul 확률", abs((a["nudge"]?.noul ?? 0) - 0.82) < 0.001)
            t.equal("choice 값", a["kind"]?.choice ?? "", "deep_focus")
            t.check("choice 확률표", abs((a["kind"]?.probabilities["errand"] ?? 0) - 0.3) < 0.001)
            t.check("score 값", abs((a["focus"]?.score ?? 0) - 1.6) < 0.001)
        } else { t.check("샘플 응답 해석", false, "parse 실패") }
        t.check("잘못된 응답 → 오류", (try? JevClient.parse(Data("{}".utf8))) == nil)

        // ① 취침 개입 규칙
        let calm = JevDecisions.windDownRule(WindDownInput(minutesToBed: 120, screenCount: 2, screenGoal: 10, stopped: false))
        t.check("여유 있을 때 말 안 걸기", !calm.nudge)
        let over = JevDecisions.windDownRule(WindDownInput(minutesToBed: 60, screenCount: 15, screenGoal: 10, stopped: false))
        t.check("목표 초과 → 개입", over.nudge)
        t.equal("목표 초과 → 단호한 톤", over.tone, .firm)
        t.equal("목표 초과 → 취침 모드 제안", over.action, .focusMode)
        let near = JevDecisions.windDownRule(WindDownInput(minutesToBed: 15, screenCount: 3, screenGoal: 10, stopped: false))
        t.equal("취침 직전 → 호흡", near.action, .breathing)
        let stopped = JevDecisions.windDownRule(WindDownInput(minutesToBed: 10, screenCount: 20, screenGoal: 10, stopped: true))
        t.check("이미 멈췄으면 개입 안 함", !stopped.nudge)
        let anxious = JevDecisions.windDownRule(WindDownInput(minutesToBed: 25, screenCount: 8, screenGoal: 10,
                                                              stopped: false, mood: .anxious))
        t.equal("불안 → 수면 사운드", anxious.action, .sound)

        // ② 할 일 분류 규칙
        t.equal("발표 준비 → 집중", JevDecisions.classifyRule("AI융합연구 발표 PPT 마무리").kind, .deepFocus)
        t.equal("시험 복습 → 집중", JevDecisions.classifyRule("시험 범위 복습").kind, .deepFocus)
        t.equal("종합시험 → 약속", JevDecisions.classifyRule("석사 종합시험").kind, .appointment)
        t.equal("마트 → 볼일", JevDecisions.classifyRule("마트: 대파, 두부").kind, .errand)
        t.equal("저녁 운동 → 자기 관리", JevDecisions.classifyRule("저녁 운동 30분").kind, .selfCare)
        t.equal("특강 → 약속", JevDecisions.classifyRule("대학원동 1층 특강").kind, .appointment)
        t.equal("모르는 일 → 가벼운 일", JevDecisions.classifyRule("이것저것").kind, .light)

        // ③ 사운드 규칙
        t.equal("스트레스 → 빗소리", JevDecisions.soundRule(mood: .stressed, fatigue: nil, preference: ""), .rain)
        t.equal("피곤 → 백색소음", JevDecisions.soundRule(mood: .tired, fatigue: nil, preference: ""), .whiteNoise)
        t.equal("선호 로파이", JevDecisions.soundRule(mood: nil, fatigue: 1, preference: "lofi"), .lofi)
        t.check("유튜브 링크 2개(앱·웹)", SoundType.rain.youtubeURLs.count == 2)
        t.check("웹 링크는 https", SoundType.piano.youtubeURLs.last?.scheme == "https")

        // ④ Claude 게이트 규칙
        if let good = SleepStats(nights: nights(.good)) {
            t.check("평범한 밤 → Claude 생략", !JevDecisions.llmGateRule(good))
        } else { t.check("충분 데이터", false, "nil") }
        if let short = SleepStats(nights: nights(.short)) {
            t.check("부족한 밤 → Claude 사용", JevDecisions.llmGateRule(short))
        } else { t.check("부족 데이터", false, "nil") }
    }

    // MARK: 노션 할 일 (페이지 블록 · DB · 추천 시간)

    static func notionTests(_ t: TestRecorder) {
        t.group = "Claude 응답 형식"
        let toolResp: [String: Any] = ["stop_reason": "tool_use", "content": [
            ["type": "tool_use", "name": "sleep_report",
             "input": ["summary": "요약 \"따옴표\" 포함", "recommendations": ["a", "b", ""], "speech": "음성"]]]]
        let tr = try? ClaudeClient.parseResponse(toolResp, day: today, model: "m")
        t.equal("도구 응답 → 요약", tr?.summary ?? "", "요약 \"따옴표\" 포함")
        t.equal("도구 응답 → 빈 추천 제거", tr?.recommendations.count ?? 0, 2)
        let textResp: [String: Any] = ["content": [["type": "text", "text": "{\"summary\":\"s\",\"recommendations\":[\"r\"],\"speech\":\"v\"}"]]]
        t.check("글 응답도 해석", (try? ClaudeClient.parseResponse(textResp, day: today, model: "m")) != nil)
        let cut: [String: Any] = ["stop_reason": "max_tokens", "content": [["type": "text", "text": "{\"summary\": \"잘린"]]]
        t.check("잘린 응답 → 오류", (try? ClaudeClient.parseResponse(cut, day: today, model: "m")) == nil)

        if let ns = SleepStats(nights: nights(.withNap), now: at(0, 9)) {
            t.equal("전날 낮잠 40분 → 요약 입력에 포함", ns.napBeforeMin, 40)
            t.check("Claude 입력에 낮잠", ClaudeClient.userMessage(ns).contains("nap_yesterday_before_last_night"))
        }
        if let gs = SleepStats(nights: nights(.good), now: at(0, 9)) {
            t.check("낮잠 없으면 입력에 없음", !ClaudeClient.userMessage(gs).contains("nap_"))
        }
        t.equal("시간 문자열 7:15", SleepStats.hm(435), "7시간 15분")
        t.equal("시간 문자열 7:00", SleepStats.hm(420), "7시간")
        t.equal("시간 문자열 45분", SleepStats.hm(45), "45분")
        let long = String(repeating: "가나다라마바사아자차. ", count: 30)
        t.check("긴 음성 원고 → 220자 이내로 자름", ClaudeClient.trimSpeech(long).count <= 220)
        t.equal("짧은 음성 원고는 그대로", ClaudeClient.trimSpeech("짧아요."), "짧아요.")

        t.group = "노션 할 일"
        let now = at(0, 9)
        let f = DateFormatter()
        f.dateFormat = "M/d"
        let todayStr = f.string(from: today)
        let tomorrowStr = f.string(from: today.addingTimeInterval(86400))
        let oldStr = f.string(from: today.addingTimeInterval(-6 * 86400))

        t.check("제목 날짜 ‘\(todayStr) 월’", NotionParse.headingDate("\(todayStr) 월", now: now) == today)
        t.check("요일 앞 ‘금\(todayStr)’", NotionParse.headingDate("금\(todayStr)", now: now) == today)
        t.check("날짜 없는 제목 → nil", NotionParse.headingDate("메모", now: now) == nil)
        let jan = NotionParse.headingDate("1/3", now: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 30))!)
        t.equal("12월에 본 1/3 → 다음 해", jan.map { Calendar.current.component(.year, from: $0) } ?? 0, 2027)

        func rt(_ s: String, strike: Bool = false) -> [String: Any] {
            ["type": "text", "plain_text": s, "annotations": ["strikethrough": strike]]
        }
        func heading(_ s: String) -> [String: Any] { ["type": "heading_1", "heading_1": ["rich_text": [rt(s)]]] }
        func todo(_ id: String, _ rich: [[String: Any]], checked: Bool = false) -> [String: Any] {
            ["id": id, "type": "to_do", "to_do": ["rich_text": rich, "checked": checked]]
        }
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime]
        let mentionTime = iso.string(from: at(1, 13, 20))
        let mention: [String: Any] = ["type": "mention", "plain_text": "@",
                                      "mention": ["type": "date", "date": ["start": mentionTime]],
                                      "annotations": ["strikethrough": false]]
        let blocks: [[String: Any]] = [
            heading("\(tomorrowStr) 화"),
            todo("a", [rt("석사 종합시험 "), mention]),
            todo("b", [rt("시험 범위 복습")]),
            heading("\(todayStr) 월"),
            todo("c", [rt("발표 PPT 마무리")]),
            todo("d", [rt("치과 예약")], checked: true),
            todo("e", [rt("취소된 약속", strike: true)]),
            ["type": "paragraph", "paragraph": ["rich_text": [rt("메모")]]],
            heading("\(oldStr) 화"),
            todo("f", [rt("오래된 일")]),
        ]
        let days: Set<Date> = [today, today.addingTimeInterval(86400)]
        let r = NotionParse.tasks(fromBlocks: blocks, days: days, carryHeading: nil, now: now)
        t.equal("오늘·내일 할 일 4개 (취소선 제외)", r.tasks.count, 4)
        t.check("오래된 제목에서 멈춤", r.shouldStop)
        t.check("취소선 항목 제외", !r.tasks.contains { $0.id == "e" })
        t.check("체크 → 완료", r.tasks.first { $0.id == "d" }?.done == true)
        t.check("날짜 제목 아래 → 그 날짜", r.tasks.first { $0.id == "c" }?.day == today)
        let exam = r.tasks.first { $0.id == "a" }
        t.check("멘션 시각 13:20", exam?.time.map { Clock.minutes(of: $0) } == 13 * 60 + 20,
                "\(String(describing: exam?.time))")
        t.equal("멘션 제목 정리", exam?.title ?? "", "석사 종합시험")

        // 다음 페이지로 이어지는 제목 (페이지 넘김)
        let cont = NotionParse.tasks(fromBlocks: [todo("g", [rt("이어지는 일")])], days: days, carryHeading: today, now: now)
        t.equal("페이지 넘김 뒤에도 날짜 유지", cont.tasks.first?.day, today)

        // 데이터베이스 모드
        let dbRows: [[String: Any]] = [
            ["id": "p1", "properties": ["이름": ["type": "title", "title": [rt("보고서 작성")]],
                                        "날짜": ["type": "date", "date": ["start": iso.string(from: at(0, 15))]],
                                        "상태": ["type": "status", "status": ["name": "완료"]]]],
            ["id": "p2", "properties": ["Name": ["type": "title", "title": [rt("다른 날")]],
                                        "Due": ["type": "date", "date": ["start": "2020-01-01"]]]],
        ]
        let db = NotionParse.tasks(fromDatabaseResults: dbRows, days: days)
        t.equal("DB: 오늘 항목만", db.count, 1)
        t.check("DB: 상태 ‘완료’ → done", db.first?.done == true)

        // 링크 → ID
        t.equal("링크에서 ID 추출",
                NotionParse.id(fromLink: "https://www.notion.so/ws/할-일-3e44fcefFEAF80c29912faf6fe117532?pvs=4") ?? "",
                "3e44fcefFEAF80c29912faf6fe117532".lowercased())
        t.check("잘못된 링크 → nil", NotionParse.id(fromLink: "https://notion.so/abc") == nil)

        // 추천 시간: 집중 일 → 컨디션 높은 때, 빈 시간
        let items = [item("수업", 10, 0, 12, 0)]
        let curve = EnergyModel.curve(wakeMinutes: 7 * 60, bedMinutes: 23 * 60 + 30, score: 80, day: today)
        let focus = NotionParse.suggestedSlot(for: TaskClass(kind: .deepFocus, focus: 2, path: .rule),
                                              items: items, curve: curve, day: today, now: now)
        if let fs = focus {
            let m = Clock.minutes(of: fs)
            t.check("집중 추천은 수업과 안 겹침", !(m < 12 * 60 && m + 60 > 10 * 60), "\(m / 60):\(m % 60)")
            let lvl = curve.min { abs($0.time.timeIntervalSince(fs)) < abs($1.time.timeIntervalSince(fs)) }?.level ?? 0
            let avg = curve.map { $0.level }.reduce(0, +) / Double(curve.count)
            t.check("집중 추천은 평균 이상 컨디션", lvl >= avg, "level \(Int(lvl)) avg \(Int(avg))")
        } else { t.check("집중 일 추천 시간 있음", false, "nil") }
        t.check("약속은 추천 시간 없음",
                NotionParse.suggestedSlot(for: TaskClass(kind: .appointment, focus: 1, path: .rule),
                                          items: items, curve: curve, day: today, now: now) == nil)
    }
}
