import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class SleepStore {
    private let healthStore = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let log = AppLog.shared

    var nights: [SleepNight] = []
    var isLoading = false
    var errorMessage: String?
    var hasRequestedAuthorization = false
    var lastLoadedAt: Date?

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 권한 요청 후 최근 N일 수면 데이터를 불러온다.
    func connectAndLoad(days: Int = 14) async {
        guard isHealthDataAvailable else {
            errorMessage = "이 기기에서는 건강 데이터를 사용할 수 없습니다."
            log.add("HealthKit 사용 불가 (시뮬레이터 또는 미지원 기기)")
            return
        }
        do {
            log.add("HealthKit 읽기 권한 요청")
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            hasRequestedAuthorization = true
            log.add("권한 요청 완료 (iOS는 읽기 권한 허용 여부를 앱에 알려주지 않음)")
        } catch {
            errorMessage = "권한 요청 실패: \(error.localizedDescription)"
            log.add("권한 요청 실패: \(error)")
            return
        }
        await load(days: days)
    }

    func load(days: Int = 14) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )

        do {
            log.add("수면 샘플 조회: 최근 \(days)일")
            let samples = try await descriptor.result(for: healthStore)
            log.add("샘플 \(samples.count)개 수신")

            let segments: [SleepSegment] = samples.compactMap { s in
                guard let stage = SleepStage(rawValue: s.value) else {
                    log.add("알 수 없는 수면 값 무시: \(s.value)")
                    return nil
                }
                return SleepSegment(
                    id: s.uuid,
                    stage: stage,
                    start: s.startDate,
                    end: s.endDate,
                    sourceName: s.sourceRevision.source.name,
                    sourceID: s.sourceRevision.source.bundleIdentifier
                )
            }

            nights = Self.groupIntoNights(segments)
            lastLoadedAt = Date()
            log.add("\(nights.count)일치 수면으로 묶음")
            if let latest = nights.first {
                log.add("최근 밤: 수면 \(Fmt.duration(latest.asleep)), 소스 \(latest.allSourceNames.joined(separator: ", "))")
            }
            if samples.isEmpty {
                errorMessage = "수면 데이터가 없습니다. 건강 앱에 수면 기록이 있는지, 그리고 설정 → 건강 → 데이터 접근 및 기기 → SleepMate에서 '수면'이 켜져 있는지 확인하세요."
            }
        } catch {
            errorMessage = "조회 실패: \(error.localizedDescription)"
            log.add("조회 실패: \(error)")
        }
    }

    /// 18:00 이후 잠든 수면은 다음 날(기상일) 밤으로 묶는다.
    static func groupIntoNights(_ segments: [SleepSegment], calendar: Calendar = .current) -> [SleepNight] {
        let grouped = Dictionary(grouping: segments) { seg in
            calendar.startOfDay(for: seg.start.addingTimeInterval(6 * 3600))
        }
        return grouped
            .map { SleepNight(day: $0.key, rawSegments: $0.value) }
            .filter { $0.asleep > 0 || $0.inBed > 0 }
            .sorted { $0.day > $1.day }
    }
}
