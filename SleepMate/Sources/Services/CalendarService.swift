import EventKit
import Foundation
import Observation

/// 캘린더 일정 한 개 (EventKit에 의존하지 않는 형태로 바꿔서 화면·로직에서 사용)
struct PlanItem: Identifiable, Equatable, Hashable {
    let id: String            // EKEvent.eventIdentifier (데모는 임의 값)
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var isFixed: Bool         // 수업·회의·약속 등 옮기면 안 되는 일정
    var canModify: Bool       // 캘린더가 수정 가능한지
    var calendarName: String

    var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// 계획서 피드백: "애플 순정 앱 접근이 편함" → Apple 캘린더(EventKit) 사용.
/// iCloud·Google 계정이 아이폰 캘린더에 연결돼 있으면 그 일정도 함께 보인다.
@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()
    private let log = AppLog.shared

    var isAuthorized = false
    var lastError: String?
    /// 바뀔 때마다 화면이 새로 일정을 읽도록 하는 표시
    var revision = 0

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let st = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (st == .fullAccess)
    }

    func requestAccess() async {
        do {
            let ok = try await store.requestFullAccessToEvents()
            isAuthorized = ok
            log.add("캘린더 권한: \(ok ? "허용" : "거부")")
            revision += 1
        } catch {
            lastError = error.localizedDescription
            log.add("캘린더 권한 요청 실패: \(error)")
        }
    }

    /// 특정 날짜의 일정
    /// 화면에 일정을 보여줄 수 있는 상태인지 (권한 있음 / 데모 / 테스트)
    var canShowItems: Bool { isAuthorized || DemoMode.isOn || TestLab.shared.isOn }

    func items(on day: Date, fixedKeywords: [String]) -> [PlanItem] {
        if TestLab.shared.isOn {
            return (TestLab.shared.items(on: day, fixedKeywords: fixedKeywords)
                    + NotionStore.shared.planItems(on: day)).sorted { $0.start < $1.start }
        }
        if DemoMode.isOn { return DemoData.planItems(on: day, fixedKeywords: fixedKeywords) }
        let notion = NotionStore.shared.planItems(on: day)
        guard isAuthorized else { return notion }
        return (calendarItems(on: day, fixedKeywords: fixedKeywords) + notion).sorted { $0.start < $1.start }
    }

    private func calendarItems(on day: Date, fixedKeywords: [String]) -> [PlanItem] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                let title = e.title ?? "(제목 없음)"
                return PlanItem(
                    id: e.eventIdentifier ?? UUID().uuidString,
                    title: title,
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    isFixed: Self.isFixed(title: title, hasAttendees: e.hasAttendees, keywords: fixedKeywords),
                    canModify: e.calendar?.allowsContentModifications ?? false,
                    calendarName: e.calendar?.title ?? ""
                )
            }
    }

    nonisolated static func isFixed(title: String, hasAttendees: Bool, keywords: [String]) -> Bool {
        if hasAttendees { return true }       // 다른 사람이 있는 일정은 고정
        let t = title.lowercased()
        return keywords.contains { !$0.isEmpty && t.contains($0.lowercased()) }
    }

    // MARK: 쓰기 (반드시 사용자 승인 후에만 호출 — GUARD)

    func move(itemID: String, to newStart: Date) throws {
        if TestLab.shared.isOn { TestLab.shared.move(id: itemID, to: newStart); revision += 1; return }
        if DemoMode.isOn { revision += 1; return }
        guard let e = store.event(withIdentifier: itemID) else {
            throw NSError(domain: "Calendar", code: 1, userInfo: [NSLocalizedDescriptionKey: "일정을 찾을 수 없습니다."])
        }
        let dur = e.endDate.timeIntervalSince(e.startDate)
        e.startDate = newStart
        e.endDate = newStart.addingTimeInterval(dur)
        try store.save(e, span: .thisEvent)
        log.add("일정 이동: \(e.title ?? "") → \(Fmt.time.string(from: newStart))")
        revision += 1
    }

    func add(title: String, start: Date, end: Date, note: String) throws {
        if TestLab.shared.isOn { TestLab.shared.add(title: title, start: start, end: end); revision += 1; return }
        if DemoMode.isOn { revision += 1; return }
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = end
        e.notes = note
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
        log.add("일정 추가: \(title) \(Fmt.time.string(from: start))")
        revision += 1
    }
}
