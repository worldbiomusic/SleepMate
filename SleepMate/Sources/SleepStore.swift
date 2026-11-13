import Foundation
import HealthKit
import Observation
import UIKit

enum DataSource: String, Codable {
    case shortcut = "단축어"
    case healthExport = "건강 데이터 내보내기"
    case healthKit = "HealthKit"
    case demo = "데모"
}

@MainActor
@Observable
final class SleepStore {
    /// 단축어 이름. 앱의 새로고침 버튼이 이 이름의 단축어를 실행한다.
    static let shortcutName = "SleepMate 동기화"

    private let healthStore = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let log = AppLog.shared

    private(set) var segments: [SleepSegment] = []
    private(set) var nights: [SleepNight] = []
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?
    var hasRequestedAuthorization = false
    var lastLoadedAt: Date?
    var lastSource: DataSource?
    var isDemo = false

    /// 최근 몇 일치를 보관할지
    private let keepDays = 90

    init() {
        loadCache()
    }

    var hasData: Bool { !segments.isEmpty }

    // MARK: - 단축어 / URL

    /// sleepmate://import?data=...   (data 없으면 클립보드에서 읽음)
    func handle(url: URL) {
        log.add("URL 수신: \(url.scheme ?? "")://\(url.host ?? "")  (\(url.absoluteString.count)자)")
        guard url.scheme?.lowercased() == "sleepmate" else { return }
        switch url.host?.lowercased() {
        case "import":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let data = items.first(where: { $0.name == "data" })?.value, !data.isEmpty {
                importShortcutText(data, via: "URL")
            } else {
                importFromClipboard()
            }
        default:
            log.add("알 수 없는 URL 경로: \(url.host ?? "-")")
        }
    }

    func importFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            errorMessage = "클립보드에 수면 데이터가 없습니다. 단축어를 다시 실행해 주세요."
            log.add("클립보드 비어 있음")
            return
        }
        importShortcutText(text, via: "클립보드")
    }

    func importShortcutText(_ text: String, via channel: String) {
        let result = SleepImport.parseShortcutText(text)
        log.add("단축어 데이터(\(channel)): \(result.segments.count)개 해석, \(result.skipped.count)줄 건너뜀")
        for line in result.skipped.prefix(3) {
            log.add("  해석 실패한 줄 예: \(line)")
        }
        guard !result.segments.isEmpty else {
            errorMessage = "수면 기록을 하나도 읽지 못했습니다. 로그 화면에서 '해석 실패한 줄'을 확인해 주세요."
            return
        }
        merge(result.segments, source: .shortcut)
    }

    /// 단축어 앱에서 'SleepMate 동기화' 단축어를 실행 → 단축어가 데이터를 담아 다시 앱을 연다.
    func runShortcut() {
        var c = URLComponents()
        c.scheme = "shortcuts"
        c.host = "run-shortcut"
        c.queryItems = [URLQueryItem(name: "name", value: Self.shortcutName)]
        guard let url = c.url else { return }
        log.add("단축어 실행 요청: \(Self.shortcutName)")
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok {
                Task { @MainActor in
                    self?.errorMessage = "단축어 앱을 열 수 없습니다."
                }
            }
        }
    }

    // MARK: - 건강 앱 export.xml

    func importHealthExport(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        log.add("내보내기 파일 읽기: \(url.lastPathComponent)")
        do {
            let segs = try await Task.detached(priority: .userInitiated) {
                try SleepImport.parseHealthExport(at: url, sinceDays: 60)
            }.value
            log.add("export.xml에서 수면 기록 \(segs.count)개")
            guard !segs.isEmpty else {
                errorMessage = "최근 60일 수면 기록을 찾지 못했습니다. zip을 풀어서 나온 'export.xml'(또는 '내보내기.xml')을 골랐는지 확인하세요."
                return
            }
            merge(segs, source: .healthExport)
        } catch {
            errorMessage = "파일을 읽지 못했습니다: \(error.localizedDescription)"
            log.add("export.xml 실패: \(error)")
        }
    }

    // MARK: - HealthKit (유료 개발자 계정으로 설치한 경우에만 동작)

    func connectHealthKit(days: Int = 14) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "이 기기에서는 HealthKit을 사용할 수 없습니다."
            return
        }
        do {
            log.add("HealthKit 읽기 권한 요청")
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            hasRequestedAuthorization = true
        } catch {
            log.add("HealthKit 권한 실패: \(error)")
            if (error as NSError).localizedDescription.contains("entitlement") {
                errorMessage = "무료 Apple ID로 설치한 앱은 HealthKit을 직접 쓸 수 없습니다. '단축어로 가져오기'를 사용하세요."
            } else {
                errorMessage = "HealthKit 권한 요청 실패: \(error.localizedDescription)"
            }
            return
        }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType,
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            log.add("HealthKit 샘플 \(samples.count)개")
            let segs: [SleepSegment] = samples.compactMap { s in
                guard let stage = SleepStage(rawValue: s.value) else { return nil }
                return SleepSegment(id: s.uuid, stage: stage, start: s.startDate, end: s.endDate,
                                    sourceName: s.sourceRevision.source.name,
                                    sourceID: s.sourceRevision.source.bundleIdentifier)
            }
            if segs.isEmpty {
                errorMessage = "HealthKit에서 수면 기록을 찾지 못했습니다."
            } else {
                merge(segs, source: .healthKit)
            }
        } catch {
            errorMessage = "HealthKit 조회 실패: \(error.localizedDescription)"
            log.add("HealthKit 조회 실패: \(error)")
        }
    }

    // MARK: - 데모

    func loadDemo() {
        isDemo = true
        segments = DemoData.segments()
        nights = Self.groupIntoNights(segments)
        lastLoadedAt = Date()
        lastSource = .demo
        log.add("데모 데이터 로드: \(nights.count)일")
    }

    // MARK: - 병합 · 저장

    private func merge(_ new: [SleepSegment], source: DataSource) {
        isDemo = false
        errorMessage = nil
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)

        // 같은 구간(시작·끝·단계·소스)이 이미 있으면 중복으로 본다.
        func key(_ s: SleepSegment) -> String {
            "\(Int(s.start.timeIntervalSince1970))-\(Int(s.end.timeIntervalSince1970))-\(s.stage.rawValue)-\(s.sourceID)"
        }
        var map: [String: SleepSegment] = [:]
        for s in segments where s.end >= cutoff { map[key(s)] = s }
        let before = map.count
        for s in new where s.end >= cutoff { map[key(s)] = s }

        segments = map.values.sorted { $0.start < $1.start }
        nights = Self.groupIntoNights(segments)
        lastLoadedAt = Date()
        lastSource = source
        infoMessage = "\(source.rawValue)에서 새 기록 \(map.count - before)개를 가져왔습니다."
        log.add("병합 완료: 총 \(segments.count)개 구간, \(nights.count)일")
        saveCache()
    }

    private struct Cache: Codable {
        var segments: [SleepSegment]
        var lastLoadedAt: Date?
        var lastSource: DataSource?
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sleep_cache.json")
    }

    private func saveCache() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Cache(segments: segments, lastLoadedAt: lastLoadedAt,
                                                      lastSource: lastSource))
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            log.add("캐시 저장 실패: \(error)")
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        segments = cache.segments
        nights = Self.groupIntoNights(segments)
        lastLoadedAt = cache.lastLoadedAt
        lastSource = cache.lastSource
        log.add("저장된 기록 불러옴: \(segments.count)개 구간")
    }

    func clearAll() {
        segments = []
        nights = []
        lastLoadedAt = nil
        lastSource = nil
        try? FileManager.default.removeItem(at: cacheURL)
        log.add("저장된 기록 삭제")
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
