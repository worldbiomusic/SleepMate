import Foundation
import SwiftUI

/// HKCategoryValueSleepAnalysis 원시값과 1:1 대응.
enum SleepStage: Int, CaseIterable, Identifiable {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case core = 3
    case deep = 4
    case rem = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .inBed: return "침대에 있음"
        case .asleepUnspecified: return "수면(단계 미상)"
        case .awake: return "깨어 있음"
        case .core: return "코어 수면"
        case .deep: return "깊은 수면"
        case .rem: return "REM 수면"
        }
    }

    var color: Color {
        switch self {
        case .inBed: return .gray.opacity(0.4)
        case .asleepUnspecified: return .teal
        case .awake: return .orange
        case .core: return .blue
        case .deep: return .indigo
        case .rem: return .cyan
        }
    }

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: return true
        case .inBed, .awake: return false
        }
    }

    var isDetailedStage: Bool {
        self == .core || self == .deep || self == .rem
    }
}

struct SleepSegment: Identifiable {
    let id: UUID
    let stage: SleepStage
    let start: Date
    let end: Date
    let sourceName: String
    let sourceID: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 하룻밤 수면. `day`는 "기상한 날" 기준 (18:00 이후 잠든 수면은 다음 날로 묶음).
struct SleepNight: Identifiable {
    let day: Date
    let segments: [SleepSegment]      // 실제 집계에 사용한 구간
    let allSourceNames: [String]      // 디버깅용: 이 밤에 데이터를 남긴 모든 기기/앱
    let stageTotals: [SleepStage: TimeInterval]
    let asleep: TimeInterval
    let awake: TimeInterval
    let inBed: TimeInterval
    let bedtime: Date?
    let wakeTime: Date?
    let hasDetailedStages: Bool

    var id: Date { day }

    init(day: Date, rawSegments: [SleepSegment]) {
        self.day = day
        self.allSourceNames = Array(Set(rawSegments.map(\.sourceName))).sorted()

        // 아이폰과 워치가 같은 밤을 동시에 기록하면 시간이 이중으로 합산된다.
        // 단계(코어/깊은/REM)를 기록한 소스(=Apple Watch)가 있으면 그 소스만 사용한다.
        let stagedSources = Set(rawSegments.filter { $0.stage.isDetailedStage }.map(\.sourceID))
        let used = stagedSources.isEmpty
            ? rawSegments
            : rawSegments.filter { stagedSources.contains($0.sourceID) }

        self.segments = used.sorted { $0.start < $1.start }
        self.hasDetailedStages = !stagedSources.isEmpty

        var totals: [SleepStage: TimeInterval] = [:]
        for stage in SleepStage.allCases {
            let intervals = used.filter { $0.stage == stage }.map { ($0.start, $0.end) }
            let total = Self.mergedDuration(intervals)
            if total > 0 { totals[stage] = total }
        }
        self.stageTotals = totals

        let asleepIntervals = used.filter { $0.stage.isAsleep }.map { ($0.start, $0.end) }
        self.asleep = Self.mergedDuration(asleepIntervals)
        self.awake = totals[.awake] ?? 0
        self.inBed = totals[.inBed] ?? 0

        let sleepSegs = used.filter { $0.stage.isAsleep }
        self.bedtime = sleepSegs.map(\.start).min()
        self.wakeTime = sleepSegs.map(\.end).max()
    }

    /// 겹치는 구간을 합친 뒤 총 길이 (중복 합산 방지).
    static func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for next in sorted.dropFirst() {
            if next.0 <= current.1 {
                current.1 = max(current.1, next.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = next
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total
    }
}

enum Fmt {
    static func duration(_ t: TimeInterval) -> String {
        let minutes = Int((t / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()
}
