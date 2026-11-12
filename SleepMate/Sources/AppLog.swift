import Foundation
import Observation

/// 맥/디버거 없이 실기기에서 문제를 추적하기 위한 앱 내부 로그.
@MainActor
@Observable
final class AppLog {
    static let shared = AppLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let message: String
    }

    private(set) var entries: [Entry] = []

    func add(_ message: String) {
        entries.append(Entry(message: message))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        print("[SleepMate] \(message)")
    }

    func clear() { entries.removeAll() }

    var text: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
    }
}
