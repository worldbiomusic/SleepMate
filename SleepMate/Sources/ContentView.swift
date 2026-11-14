import SwiftUI
import UniformTypeIdentifiers

/// 홈 탭 (시나리오 05: 수면 리포트 · 요약 듣기 + 대시보드)
struct HomeView: View {
    var openToday: () -> Void = {}
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CoachStore.self) private var coach
    @State private var demoDestination: String?
    @State private var showCoachSettings = false
    @State private var showGuide = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            List {
                if !store.hasData && !store.isDemo {
                    connectSection
                }

                if let error = store.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if let info = store.infoMessage, store.errorMessage == nil {
                    Section {
                        Label(info, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }

                if store.hasData || store.isDemo {
                    Section {
                        DashboardHeader(openToday: openToday)
                    }
                }

                if let latest = store.nights.first {
                    Section("지난밤 수면 단계") {
                        LatestNightCard(night: latest)
                    }
                    Section {
                        CoachCard()
                    }
                    Section {
                        WeekStageChart(nights: store.nights, goalMinutes: ctx.profile.goalSleepMinutes)
                            .padding(.vertical, 4)
                        NavigationLink {
                            SleepReportView()
                        } label: {
                            Label("수면 리포트 전체 보기", systemImage: "chart.xyaxis.line")
                        }
                    } header: {
                        Text("최근 7일 · 단계별 수면 시간")
                    }
                }

                if store.nights.count > 1 {
                    Section("최근 기록") {
                        ForEach(store.nights) { night in
                            NavigationLink {
                                NightDetailView(night: night)
                            } label: {
                                NightRow(night: night)
                            }
                        }
                    }
                }

                if let t = store.lastLoadedAt {
                    Section {
                        Text(footer(t))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("SleepMate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        LogView()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Menu {
                            Button {
                                store.runShortcut()
                            } label: {
                                Label("단축어로 가져오기", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button {
                                store.importFromClipboard()
                            } label: {
                                Label("클립보드에서 가져오기", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                showImporter = true
                            } label: {
                                Label("건강 데이터 내보내기 파일 열기", systemImage: "doc.badge.arrow.up")
                            }
                            Divider()
                            Button {
                                showGuide = true
                            } label: {
                                Label("단축어 설정 방법", systemImage: "questionmark.circle")
                            }
                            Button {
                                Task { await store.connectHealthKit() }
                            } label: {
                                Label("HealthKit 직접 연결 (유료 계정 전용)", systemImage: "heart.text.square")
                            }
                            Button {
                                showCoachSettings = true
                            } label: {
                                Label("AI 요약 설정", systemImage: "gearshape")
                            }
                            Button(role: .destructive) {
                                store.clearAll()
                                coach.clear()
                            } label: {
                                Label("저장된 기록 지우기", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        } primaryAction: {
                            store.runShortcut()
                        }
                    }
                }
            }
            .sheet(isPresented: $showGuide) {
                ShortcutGuideView()
            }
            .sheet(isPresented: $showCoachSettings) {
                CoachSettingsView()
            }
            // 새 기록이 들어오면 요약 갱신 (단축어로 가져온 경우 설정에 따라 Claude 요약·자동 읽기)
            .onChange(of: store.lastLoadedAt) { _, _ in
                let imported = store.lastChangeWasImport
                let persist = !store.isDemo
                Task { await coach.update(nights: store.nights, fromImport: imported, persist: persist) }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.xml, .data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await store.importHealthExport(from: url) }
                }
            }
            .navigationDestination(item: $demoDestination) { screen in
                if screen == "log" {
                    LogView()
                } else if screen == "selftest" {
                    SelfTestView()
                } else if screen == "testlab" {
                    TestLabView()
                } else if screen == "report" {
                    SleepReportView()
                } else if screen == "coach" {
                    List { Section { CoachCard() } }
                        .navigationTitle("수면 코치")
                } else if let night = store.nights.first {
                    NightDetailView(night: night)
                }
            }
            .task {
                // 앱 시작 시 저장된 기록으로 요약 준비 (이미 같은 밤 요약이 있으면 유지)
                await coach.update(nights: store.nights, fromImport: false)

                // CI 검증용: `-testImportURL "sleepmate://import?data=..."` 로 실행하면
                // 단축어가 앱을 열 때와 같은 처리 경로(store.handle)를 탄다.
                if let s = UserDefaults.standard.string(forKey: "testImportURL"),
                   let url = URL(string: s) {
                    store.handle(url: url)
                    return
                }
                if !DemoMode.isOn, let screen = DemoMode.screen, screen != "home" {
                    demoDestination = screen      // 실제 데이터로 특정 화면 확인 (CI 스크린샷용)
                    return
                }
                guard DemoMode.isOn, !store.isDemo else { return }
                if DemoMode.screen == "first" { return }
                if DemoMode.screen == "guide" { showGuide = true; return }
                if DemoMode.screen == "settings" { showCoachSettings = true; return }
                store.loadDemo()
                if let screen = DemoMode.screen, screen != "home" {
                    demoDestination = screen
                }
            }
        }
    }

    private func footer(_ t: Date) -> String {
        if store.isDemo { return "데모 데이터 (실제 기록 아님)" }
        let src = store.lastSource?.rawValue ?? "-"
        return "마지막 가져오기: \(Fmt.day.string(from: t)) \(Fmt.time.string(from: t)) · \(src)\n오른쪽 위 ↻ 버튼을 누르면 단축어로 최신 기록을 가져옵니다. 길게 누르면 다른 방법이 나옵니다."
    }

    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Watch 수면 데이터 가져오기")
                    .font(.headline)
                Text("아이폰 '단축어' 앱이 건강 앱의 수면 기록(코어·깊은·REM 수면, 깨어 있음)을 읽어 이 앱으로 넘겨줍니다. 데이터는 기기 밖으로 전송되지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    store.runShortcut()
                } label: {
                    Label("단축어로 가져오기", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)

                Button {
                    showGuide = true
                } label: {
                    Label("처음이라면: 단축어 설정 방법", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showImporter = true
                } label: {
                    Text("또는 건강 데이터 내보내기(export.xml) 파일 열기")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 지난밤 카드

struct LatestNightCard: View {
    let night: SleepNight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Fmt.day.string(from: night.day))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Fmt.duration(night.asleep))
                .font(.system(size: 40, weight: .bold, design: .rounded))

            if let bed = night.bedtime, let wake = night.wakeTime {
                Text("\(Fmt.time.string(from: bed)) → \(Fmt.time.string(from: wake))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if night.napSleep >= 5 * 60 {
                Label("낮잠 \(Fmt.duration(night.napSleep))은 밤잠과 따로 계산했어요", systemImage: "sun.haze")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HypnogramChart(night: night)

            StageBreakdownView(night: night)

            if !night.hasDetailedStages {
                Text("단계별 데이터가 없습니다. Apple Watch를 차고 자면 코어·깊은·REM 수면이 기록됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 단계 비율 막대

struct StageBar: View {
    let night: SleepNight
    private let order: [SleepStage] = [.deep, .core, .rem, .asleepUnspecified, .awake]

    var body: some View {
        let parts = order.compactMap { stage -> (SleepStage, TimeInterval)? in
            guard let t = night.stageTotals[stage], t > 0 else { return nil }
            return (stage, t)
        }
        let total = parts.reduce(0) { $0 + $1.1 }

        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(parts[i].0.color)
                        .frame(width: max(2, geo.size.width * parts[i].1 / max(total, 1) - 2))
                }
            }
        }
    }
}

struct StageLegend: View {
    let night: SleepNight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([SleepStage.deep, .core, .rem, .asleepUnspecified, .awake], id: \.self) { stage in
                if let t = night.stageTotals[stage], t > 0 {
                    HStack {
                        Circle().fill(stage.color).frame(width: 10, height: 10)
                        Text(stage.label).font(.callout)
                        Spacer()
                        Text(Fmt.duration(t)).font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}

// MARK: - 목록 행

struct NightRow: View {
    let night: SleepNight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.day.string(from: night.day))
                Spacer()
                Text(Fmt.duration(night.asleep))
                    .font(.body.monospacedDigit().bold())
            }
            StageBar(night: night).frame(height: 8)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 상세 (원시 구간 확인용)

struct NightDetailView: View {
    let night: SleepNight

    var body: some View {
        List {
            Section {
                LatestNightCard(night: night)
            }
            Section("데이터 소스") {
                ForEach(night.allSourceNames, id: \.self) { Text($0) }
            }
            Section("구간 (\(night.segments.count)개)") {
                ForEach(night.segments) { seg in
                    HStack {
                        Circle().fill(seg.stage.color).frame(width: 8, height: 8)
                        Text(seg.stage.label).font(.callout)
                        Spacer()
                        Text("\(Fmt.time.string(from: seg.start)) – \(Fmt.time.string(from: seg.end))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Fmt.day.string(from: night.day))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 로그

struct LogView: View {
    @State private var log = AppLog.shared

    var body: some View {
        ScrollView {
            Text(log.entries.isEmpty ? "로그 없음" : log.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("로그")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: log.text) { Image(systemName: "square.and.arrow.up") }
                Button("지우기") { log.clear() }
            }
        }
    }
}
