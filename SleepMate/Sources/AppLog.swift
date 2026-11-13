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
        // stderr는 버퍼링되지 않아 CI(simctl launch --stderr)에서도 바로 보인다.
        FileHandle.standardError.write(Data("[SleepMate] \(message)\n".utf8))
    }

    func clear() { entries.removeAll() }

    var text: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
    }
}
