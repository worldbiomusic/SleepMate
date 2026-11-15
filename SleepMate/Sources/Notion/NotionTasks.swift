import Foundation
import Observation

// 노션 할 일 연동 (읽기 전용)
// 두 가지 형태를 지원:
//  A) 페이지: "11/16 월" 같은 날짜 제목 아래에 체크박스(할 일)를 쌓는 방식  ← 이정한 님 '할 일' 페이지
//     · 체크박스 안의 날짜 멘션(@2026-11-26 13:20)이 있으면 그 시각을 사용
//     · 취소선 항목은 취소로 보고 제외
//  B) 데이터베이스: 제목 + 날짜 속성 + (체크박스/상태) 속성을 자동으로 찾아서 사용
// 오늘·내일 할 일만 읽고, 기기에만 잠시 보관한다.

struct NotionTask: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var day: Date               // 날짜(자정)
    var time: Date?             // 시각이 있으면
    var done: Bool
    var cls: TaskClass?         // 분류 (Jev 또는 규칙)
}

enum NotionParse {
    /// "11/16 월", "금10/9", "12/16 수" → 날짜
    static func headingDate(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let r = text.range(of: #"(\d{1,2})\s*/\s*(\d{1,2})"#, options: .regularExpression) else { return nil }
        let parts = text[r].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        var dc = calendar.dateComponents([.year], from: now)
        dc.month = parts[0]
        dc.day = parts[1]
        guard var d = calendar.date(from: dc) else { return nil }
        // 연도가 없으므로 지금과 가장 가까운 해로 맞춘다 (12월에 보는 1월 → 다음 해)
        if d.timeIntervalSince(now) > 200 * 86400 { d = calendar.date(byAdding: .year, value: -1, to: d) ?? d }
        if now.timeIntervalSince(d) > 200 * 86400 { d = calendar.date(byAdding: .year, value: 1, to: d) ?? d }
        return calendar.startOfDay(for: d)
    }

    static func plainText(_ rich: [[String: Any]]) -> (text: String, mentionDate: String?, struck: Bool) {
        var text = ""
        var mention: String?
        var allStruck = !rich.isEmpty
        for r in rich {
            let struck = ((r["annotations"] as? [String: Any])?["strikethrough"] as? Bool) ?? false
            if r["type"] as? String == "mention",
               let m = r["mention"] as? [String: Any], m["type"] as? String == "date",
               let d = m["date"] as? [String: Any], let start = d["start"] as? String {
                mention = start
                if !struck { allStruck = false }
                continue
            }
            let t = r["plain_text"] as? String ?? ""
            if !t.trimmingCharacters(in: .whitespaces).isEmpty && !struck { allStruck = false }
            text += t
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), mention, allStruck)
    }

    static func parseNotionDate(_ s: String) -> (day: Date, time: Date?)? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return (Calendar.current.startOfDay(for: d), d) }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return (Calendar.current.startOfDay(for: d), d) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(s.prefix(10))) { return (d, nil) }
        return nil
    }

    /// 페이지 블록 목록(최신 날짜가 위) → 할 일. 반환: (할 일, 더 읽어야 하는지)
    static func tasks(fromBlocks blocks: [[String: Any]], days: Set<Date>, carryHeading: Date?,
                      now: Date = Date()) -> (tasks: [NotionTask], lastHeading: Date?, shouldStop: Bool) {
        var current = carryHeading
        var out: [NotionTask] = []
        let oldest = days.min() ?? Calendar.current.startOfDay(for: now)
        for b in blocks {
            let type = b["type"] as? String ?? ""
            if type.hasPrefix("heading_"), let h = b[type] as? [String: Any],
               let rich = h["rich_text"] as? [[String: Any]] {
                if let d = headingDate(plainText(rich).text, now: now) {
                    current = d
                    // 최신순으로 쓰는 페이지: 찾는 날보다 이틀 넘게 지난 제목이 나오면 그만 읽는다
                    if d < oldest.addingTimeInterval(-2 * 86400) { return (out, current, true) }
                }
                continue
            }
            guard type == "to_do", let td = b["to_do"] as? [String: Any],
                  let rich = td["rich_text"] as? [[String: Any]] else { continue }
            let p = plainText(rich)
            if p.struck || p.text.isEmpty && p.mentionDate == nil { continue }
            var day = current
            var time: Date?
            if let m = p.mentionDate, let parsed = parseNotionDate(m) {
                day = parsed.day
                time = parsed.time
            }
            guard let d = day, days.contains(d) else { continue }
            out.append(NotionTask(id: b["id"] as? String ?? UUID().uuidString,
                                  title: p.text.isEmpty ? "(제목 없음)" : p.text,
                                  day: d, time: time, done: td["checked"] as? Bool ?? false))
        }
        return (out, current, false)
    }

    /// 데이터베이스 결과 → 할 일
    static func tasks(fromDatabaseResults results: [[String: Any]], days: Set<Date>) -> [NotionTask] {
        var out: [NotionTask] = []
        for page in results {
            guard let props = page["properties"] as? [String: Any] else { continue }
            var title = ""
            var dateStr: String?
            var done = false
            for (_, raw) in props {
                guard let p = raw as? [String: Any], let t = p["type"] as? String else { continue }
                switch t {
                case "title":
                    title = plainText(p["title"] as? [[String: Any]] ?? []).text
                case "date":
                    if dateStr == nil { dateStr = (p["date"] as? [String: Any])?["start"] as? String }
                case "checkbox":
                    if p["checkbox"] as? Bool == true { done = true }
                case "status":
                    let name = ((p["status"] as? [String: Any])?["name"] as? String ?? "").lowercased()
                    if ["done", "완료", "complete", "completed"].contains(where: { name.contains($0) }) { done = true }
                default: break
                }
            }
            guard let ds = dateStr, let parsed = parseNotionDate(ds), days.contains(parsed.day) else { continue }
            out.append(NotionTask(id: page["id"] as? String ?? UUID().uuidString,
                                  title: title.isEmpty ? "(제목 없음)" : title,
                                  day: parsed.day, time: parsed.time, done: done))
        }
        return out
    }

    /// 노션 링크/ID → 32자리 ID
    static func id(fromLink s: String) -> String? {
        let hex = s.lowercased().replacingOccurrences(of: "-", with: "")
        guard let r = hex.range(of: #"[0-9a-f]{32}"#, options: .regularExpression) else { return nil }
        return String(hex[r])
    }

    /// 집중 필요도에 맞는 추천 시간대 (컨디션 곡선의 높은/낮은 때 + 빈 시간)
    @MainActor
    static func suggestedSlot(for c: TaskClass, items: [PlanItem], curve: [EnergyModel.Point],
                              day: Date, now: Date) -> Date? {
        guard c.kind != .appointment, !curve.isEmpty else { return nil }
        let earliest = max(Clock.minutes(of: now) + 15, 8 * 60)
        let sorted: [EnergyModel.Point]
        if c.focus >= 2 {
            sorted = curve.sorted { $0.level > $1.level }                    // 컨디션 높은 때부터
        } else if c.focus == 0 {
            sorted = curve.sorted { $0.level < $1.level }                    // 컨디션 낮은 때(가벼운 일)
        } else {
            sorted = curve
        }
        let length = c.focus >= 2 ? 60 : 30
        for p in sorted {
            let m = (Clock.minutes(of: p.time) / 15) * 15
            if m < earliest || m > 21 * 60 { continue }
            if let s = DayPlanner.freeSlot(in: items, from: max(earliest, m - 45), to: min(22 * 60, m + 90),
                                           minutes: length, day: day) {
                return s
            }
        }
        return nil
    }
}

enum NotionError: LocalizedError {
    case notConfigured, http(Int, String), notShared

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "노션 토큰과 페이지 링크를 넣어 주세요."
        case .notShared: return "페이지를 찾을 수 없어요. 노션 페이지 ⋯ → 연결(Connections)에 통합을 추가했는지 확인해 주세요."
        case .http(401, _): return "노션 토큰이 올바르지 않아요 (401)."
        case let .http(code, msg): return "노션 오류 \(code): \(msg.prefix(120))"
        }
    }
}

enum NotionClient {
    static let tokenAccount = "notion-token"
    static let version = "2022-06-28"

    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let token = SecretStore.load(tokenAccount),
              let url = URL(string: "https://api.notion.com/v1/" + path) else { throw NotionError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(version, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw NotionError.notShared }
        guard code == 200 else { throw NotionError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// 데이터베이스면 DB 방식, 아니면 페이지 블록 방식으로 읽는다
    static func fetchTasks(id: String, days: Set<Date>) async throws -> (tasks: [NotionTask], mode: String) {
        if let _ = try? await request("databases/\(id)") {
            let oldest = days.min() ?? Date()
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            // 날짜 속성 이름을 몰라도 되도록, 최근 수정된 항목을 가져와 앱에서 거른다
            let r = try await request("databases/\(id)/query", method: "POST",
                                      body: ["page_size": 100,
                                             "filter": ["timestamp": "last_edited_time",
                                                        "last_edited_time": ["on_or_after": f.string(from: oldest.addingTimeInterval(-60 * 86400))]]])
            return (NotionParse.tasks(fromDatabaseResults: r["results"] as? [[String: Any]] ?? [], days: days), "데이터베이스")
        }
        var cursor: String?
        var heading: Date?
        var all: [NotionTask] = []
        for _ in 0..<8 {     // 최대 800블록
            let path = "blocks/\(id)/children?page_size=100" + (cursor.map { "&start_cursor=\($0)" } ?? "")
            let r = try await request(path)
            let blocks = r["results"] as? [[String: Any]] ?? []
            let part = NotionParse.tasks(fromBlocks: blocks, days: days, carryHeading: heading)
            all += part.tasks
            heading = part.lastHeading
            if part.shouldStop || r["has_more"] as? Bool != true { break }
            cursor = r["next_cursor"] as? String
        }
        return (all, "페이지")
    }
}

@MainActor
@Observable
final class NotionStore {
    static let shared = NotionStore()

    var tasks: [NotionTask] = []
    var lastSync: Date?
    var mode: String?
    var error: String?
    var syncing = false
    private(set) var link: String = UserDefaults.standard.string(forKey: "notionLink") ?? ""

    func setLink(_ l: String) {
        link = l.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(link, forKey: "notionLink")
    }
    var hasToken = SecretStore.load(NotionClient.tokenAccount) != nil

    var isConfigured: Bool { hasToken && NotionParse.id(fromLink: link) != nil }

    func setToken(_ t: String) {
        SecretStore.save(t, NotionClient.tokenAccount)
        hasToken = SecretStore.load(NotionClient.tokenAccount) != nil
    }

    func clearToken() {
        SecretStore.delete(NotionClient.tokenAccount)
        hasToken = false
        tasks = []
    }

    func tasks(on day: Date) -> [NotionTask] {
        let d = Calendar.current.startOfDay(for: day)
        if TestLab.shared.isOn { return TestData.notion(on: d) }
        return tasks.filter { $0.day == d }
    }

    /// 시각이 있는 할 일 → 타임라인·알람 계산용 일정
    func planItems(on day: Date) -> [PlanItem] {
        tasks(on: day).compactMap { t in
            guard let time = t.time, !t.done else { return nil }
            let cls = t.cls ?? JevDecisions.classifyRule(t.title)
            return PlanItem(id: "notion-\(t.id)", title: t.title, start: time, end: time.addingTimeInterval(3600),
                            isAllDay: false, isFixed: cls.kind == .appointment, canModify: false,
                            calendarName: "노션")
        }
    }

    func sync() async {
        guard let id = NotionParse.id(fromLink: link), hasToken else {
            error = NotionError.notConfigured.localizedDescription
            return
        }
        syncing = true
        error = nil
        defer { syncing = false }
        let today = Calendar.current.startOfDay(for: Date())
        let days: Set<Date> = [today, today.addingTimeInterval(86400)]
        do {
            let r = try await NotionClient.fetchTasks(id: id, days: days)
            var list = r.tasks
            let classes = await JevDecisions.classify(list.map(\.title))
            for i in list.indices where i < classes.count { list[i].cls = classes[i] }
            tasks = list
            mode = r.mode
            lastSync = Date()
            AppLog.shared.add("노션 동기화: \(r.mode), 오늘·내일 할 일 \(list.count)개")
        } catch {
            self.error = error.localizedDescription
            AppLog.shared.add("노션 실패: \(error)")
        }
    }
}
