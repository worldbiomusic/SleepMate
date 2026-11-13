import Foundation

/// 시뮬레이터 미리보기·스크린샷용 데모 모드.
/// 실행 인자로만 켜진다: `-demoData YES [-demoScreen detail|log]`
/// 일반 실행(아이폰에서 아이콘 탭)에서는 절대 켜지지 않는다.
enum DemoMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoData") }
    static var screen: String? { UserDefaults.standard.string(forKey: "demoScreen") }
}

@MainActor
enum DemoData {
    /// 최근 7일치 가상의 Apple Watch 수면 기록.
    static func segments(calendar: Calendar = .current) -> [SleepSegment] {
        let pattern: [(SleepStage, Int)] = [
            (.core, 25), (.deep, 35), (.core, 30), (.rem, 15),
            (.core, 35), (.deep, 25), (.core, 30), (.awake, 4),
            (.rem, 25), (.core, 40), (.deep, 10), (.rem, 30),
            (.core, 35), (.awake, 6), (.rem, 30), (.core, 25),
        ]
        let bedOffsetsMin = [-35, 60, 10, -50, 25, -15, 40]   // 23:30 기준 취침 시각 편차
        let today = calendar.startOfDay(for: Date())
        var segments: [SleepSegment] = []

        for (i, offset) in bedOffsetsMin.enumerated() {
            guard let wakeDay = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            var t = wakeDay.addingTimeInterval(TimeInterval(-30 + offset) * 60)
            let trim = (i % 3) * 2      // 밤마다 길이를 조금씩 다르게
            for (stage, minutes) in pattern.dropLast(trim) {
                let end = t.addingTimeInterval(TimeInterval(minutes) * 60)
                segments.append(SleepSegment(
                    id: UUID(), stage: stage, start: t, end: end,
                    sourceName: "Apple Watch (데모)", sourceID: "demo.watch"
                ))
                t = end
            }
        }
        return segments
    }

    /// 데모용 캘린더 일정 (오늘/내일)
    nonisolated static func planItems(on day: Date, fixedKeywords: [String],
                                      calendar: Calendar = .current) -> [PlanItem] {
        let start = calendar.startOfDay(for: day)
        let isToday = calendar.isDateInToday(day)
        let rows: [(String, Int, Int)] = isToday
            ? [("논문 집중 작업", 9 * 60, 10 * 60 + 30),
               ("AI응용융합연구 수업", 10 * 60 + 30, 12 * 60),
               ("점심", 12 * 60 + 30, 13 * 60),
               ("개인 프로젝트 작업", 13 * 60, 15 * 60),
               ("팀 회의", 15 * 60, 16 * 60)]
            : [("AI응용융합연구 수업", 9 * 60, 10 * 60 + 30),
               ("SleepMate 개발", 14 * 60, 16 * 60)]
        return rows.map { title, s, e in
            PlanItem(id: "demo-\(isToday ? "t" : "n")-\(s)", title: title,
                     start: start.addingTimeInterval(TimeInterval(s * 60)),
                     end: start.addingTimeInterval(TimeInterval(e * 60)),
                     isAllDay: false,
                     isFixed: CalendarService.isFixed(title: title, hasAttendees: false, keywords: fixedKeywords),
                     canModify: true, calendarName: "데모")
        }
    }
}
