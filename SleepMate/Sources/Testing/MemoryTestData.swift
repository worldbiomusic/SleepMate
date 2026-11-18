import Foundation

/// 4주 사용 기록 시뮬레이션 (테스트 모드 · 셀프 테스트)
///  - '오늘과 같은 요일' 밤마다 75분 늦게 잠 + 밤 유튜브 50분
///  - 다른 날은 거의 제시간 + 밤 앱 10분
///  - 부드러운 말투 알림은 대부분 무시, 단호한 말투는 대부분 받아들임
extension TestData {
    struct MemoryHistory {
        var nights: [NightSummary]
        var sessions: [AppSession]
        var interventions: [InterventionRecord]
        var lateWeekday: Int
    }

    static func memoryHistory(profile: UserProfile, now: Date, weeks: Int = 4,
                              calendar: Calendar = .current) -> MemoryHistory {
        let today = calendar.startOfDay(for: now)
        let lateWeekday = calendar.component(.weekday, from: today)
        var nights: [NightSummary] = []
        var sessions: [AppSession] = []
        var ivs: [InterventionRecord] = []
        for k in 1...(weeks * 7) {
            let day = calendar.date(byAdding: .day, value: -k, to: today)!
            let late = calendar.component(.weekday, from: day) == lateWeekday
            let delay = late ? 75 : [0, 5, 10, 15, -5][k % 5]
            let bed = day.addingTimeInterval(TimeInterval((profile.bedtimeMinutes + delay) * 60))
            let asleep = late ? 350 : 425
            nights.append(NightSummary(day: calendar.date(byAdding: .day, value: 1, to: day)!,
                                       bedtime: bed, wake: bed.addingTimeInterval(TimeInterval((asleep + 15) * 60)),
                                       asleepMin: asleep))
            // 밤 유튜브 (취침 준비 구간 안)
            let evStart = day.addingTimeInterval(TimeInterval((profile.bedtimeMinutes - 60) * 60))
            sessions.append(AppSession(app: "YouTube", start: evStart,
                                       end: evStart.addingTimeInterval(TimeInterval((late ? 50 : 10) * 60))))
            // 낮 사용
            let noon = day.addingTimeInterval(13 * 3600)
            sessions.append(AppSession(app: "YouTube", start: noon, end: noon.addingTimeInterval(TimeInterval((20 + k % 3 * 10) * 60))))
            sessions.append(AppSession(app: "Instagram", start: noon.addingTimeInterval(4 * 3600),
                                       end: noon.addingTimeInterval(4 * 3600 + 15 * 60)))
            // 개입: 짝수 날 단호(5번 중 4번 수락), 홀수 날 부드럽게(4번 중 1번 수락)
            let firm = k % 2 == 0
            let accepted = firm ? (k % 10 != 0) : (k % 8 == 1)
            let t = day.addingTimeInterval(TimeInterval((profile.bedtimeMinutes - 20) * 60))
            ivs.append(InterventionRecord(time: t, kind: k % 3 == 0 ? .appLimit : .windDown,
                                          tone: firm ? "firm" : "gentle", channel: k % 3 == 0 ? .notification : .inApp,
                                          detail: "시뮬레이션", outcome: accepted ? .accepted : .ignored,
                                          outcomeTime: t.addingTimeInterval(accepted ? 120 : 3600)))
        }
        return MemoryHistory(nights: nights, sessions: sessions, interventions: ivs, lateWeekday: lateWeekday)
    }

    /// 오늘 밤 (테스트 시계 22:40 기준) 사용 기록: 유튜브 사용 중
    static func tonightSessions(now: Date, calendar: Calendar = .current) -> [AppSession] {
        let base = calendar.startOfDay(for: now)
        func at(_ h: Int, _ m: Int) -> Date { base.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
        return [AppSession(app: "YouTube", start: at(12, 30), end: at(13, 5)),
                AppSession(app: "YouTube", start: at(21, 40), end: at(22, 5)),
                AppSession(app: "Instagram", start: at(22, 10), end: at(22, 20)),
                AppSession(app: "YouTube", start: at(22, 30), end: nil)]
    }
}
