import SwiftUI

struct ContentView: View {
    @Environment(SleepStore.self) private var store
    @State private var demoDestination: String?

    var body: some View {
        NavigationStack {
            List {
                if !store.hasRequestedAuthorization && store.nights.isEmpty {
                    connectSection
                }

                if let error = store.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if let latest = store.nights.first {
                    Section("지난밤") {
                        LatestNightCard(night: latest)
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
                        Text(store.isDemo ? "데모 데이터 (실제 기록 아님)" : "마지막 갱신: \(Fmt.time.string(from: t))")
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
                        Button {
                            Task { await store.connectAndLoad() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { if !store.isDemo { await store.load() } }
            .navigationDestination(item: $demoDestination) { screen in
                if screen == "log" {
                    LogView()
                } else if let night = store.nights.first {
                    NightDetailView(night: night)
                }
            }
            .task {
                guard DemoMode.isOn, !store.isDemo else { return }
                store.loadDemo()
                if let screen = DemoMode.screen, screen != "home" {
                    demoDestination = screen
                }
            }
        }
    }

    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Watch 수면 데이터 연결")
                    .font(.headline)
                Text("건강 앱에 저장된 수면 기록(코어·깊은·REM 수면, 깨어 있음)을 읽어옵니다. 데이터는 기기 밖으로 전송되지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await store.connectAndLoad() }
                } label: {
                    Label("건강 데이터 연결하기", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
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

            StageBar(night: night)
                .frame(height: 14)

            StageLegend(night: night)

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
