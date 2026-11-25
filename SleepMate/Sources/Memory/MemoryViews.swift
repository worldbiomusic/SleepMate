import Charts
import SwiftUI

/// 홈: 에이전트가 애매하게 알고 있는 것을 한 번 확인 (능동적 되묻기)
struct MemoryQuestionCard: View {
    @State private var memory = MemoryStore.shared

    var body: some View {
        if let q = memory.pendingQuestion, let text = q.question, !DemoTour.shared.isOn {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("SleepMate가 확인하고 싶어요", systemImage: "questionmark.bubble.fill")
                        .font(.caption.bold()).foregroundStyle(.purple)
                    Text(text).font(.headline)
                    Text("지금까지 본 것: \(q.title) (근거 \(q.evidence)번)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("맞아요") { withAnimation { memory.answer(q, yes: true) } }
                            .buttonStyle(.borderedProminent).tint(.purple)
                        Button("아니에요") { withAnimation { memory.answer(q, yes: false) } }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("나중에") { withAnimation { memory.skipQuestion(q) } }.font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// 홈: 기억 요약 → 자세히
struct MemorySummaryRow: View {
    @State private var memory = MemoryStore.shared

    var body: some View {
        NavigationLink {
            MemoryView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile").font(.title2).foregroundStyle(.purple)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.purple.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("나에 대한 기억").font(.headline)
                    Text(memory.facts.first.map { $0.title } ?? "기록이 쌓이면 습관과 잘 통하는 방법을 배워요")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(memory.facts.count)").font(.title3.bold().monospacedDigit()).foregroundStyle(.purple)
            }
        }
    }
}

/// 4층 기억을 그대로 보여 주는 화면 (투명성: 보고, 확인하고, 지울 수 있음)
struct MemoryView: View {
    @Environment(ContextStore.self) private var ctx
    @Environment(SleepStore.self) private var store
    @State private var memory = MemoryStore.shared
    @State private var usage = UsageStore.shared
    @State private var confirmReset = false

    var body: some View {
        let now = AppClock.now
        List {
            realtimeSection(now)
            episodeSection
            factSection(now)
            outcomeSection
            declaredSection
            Section {
                Button("기억 모두 지우기", role: .destructive) { confirmReset = true }
            } footer: {
                Text("기억은 이 아이폰 안에만 저장돼요. Claude에게는 신뢰도가 높은 습관 문장 3개까지만, Jev에게는 ‘오늘 늦게 자는 요일인지’ 같은 예/아니오만 보내요.")
            }
        }
        .navigationTitle("나에 대한 기억")
        .onAppear {
            if !TestLab.shared.isOn { memory.consolidate(nights: store.nights, ctx: ctx) }
        }
        .confirmationDialog("배운 습관과 개입 기록을 모두 지울까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("모두 지우기", role: .destructive) { memory.resetAll() }
        }
    }

    // 1층: 실시간
    private func realtimeSection(_ now: Date) -> some View {
        let rt = RealtimeContext(now: now, profile: ctx.profile, todayItems: [])
        return Section {
            row("clock", "지금", Fmt.time.string(from: now))
            row("moon.zzz", "취침까지", rt.minutesToBedtime >= 0 ? Clock.durationText(rt.minutesToBedtime) : "지남")
            row("play.rectangle", "열린 앱", usage.openSession.map { UsageMath.displayName($0.app) } ?? "없음")
            row("hourglass", "오늘 밤 앱 사용", "\(usage.eveningMinutes(now: now, profile: ctx.profile))분 / \(usage.settings.eveningLimitMinutes)분")
            row("face.smiling", "오늘 기분·피로", "\(ctx.today.mood?.rawValue ?? "-") · \(ctx.today.fatigue.map { "\($0)/5" } ?? "-")")
        } header: {
            layerHeader(1, "실시간", "저장하지 않고 매번 계산")
        }
    }

    // 2층: 일일 에피소드
    private var episodeSection: some View {
        let list = memory.episodes.prefix(14).reversed()
        return Section {
            if list.isEmpty {
                Text("수면 기록이나 앱 사용 기록이 쌓이면 하루 한 장씩 만들어져요.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(list)) { e in
                        if let d = e.bedDelayMin {
                            BarMark(x: .value("날짜", e.day, unit: .day), y: .value("늦게 잔 분", d))
                                .foregroundStyle(d >= 30 ? Color.orange : (d <= 0 ? Color.teal : Color.indigo))
                        }
                        if !e.interventions.isEmpty {
                            PointMark(x: .value("날짜", e.day, unit: .day), y: .value("개입", -20))
                                .symbol(.circle)
                                .foregroundStyle(e.interventions.contains { $0.outcome == .accepted } ? .green : .gray)
                        }
                    }
                    RuleMark(y: .value("목표", 0)).foregroundStyle(.secondary)
                }
                .chartYAxisLabel("목표 대비 취침 (분)")
                .frame(height: 170)
                Text("막대: 목표보다 늦게 잔 분 · 아래 점: 개입 (초록 = 받아들임)").font(.caption2).foregroundStyle(.secondary)
                ForEach(memory.episodes.prefix(5)) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.day.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.subheadline.bold())
                        Text(episodeLine(e)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            layerHeader(2, "일일 에피소드", "하루 한 장 · 60일")
        }
    }

    // 3층: 장기 패턴
    private func factSection(_ now: Date) -> some View {
        Section {
            if memory.facts.isEmpty {
                Text("아직 확실한 습관을 찾지 못했어요. 같은 요일이 3번 이상 쌓이면 패턴을 찾아요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(PatternFact.Category.allCases, id: \.self) { cat in
                let list = memory.facts.filter { $0.category == cat }
                if !list.isEmpty {
                    Text(cat.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(list) { f in
                        FactRow(fact: f, now: now)
                            .swipeActions {
                                Button("잊기", role: .destructive) { memory.forget(f) }
                            }
                    }
                }
            }
        } header: {
            layerHeader(3, "장기 패턴", "신뢰도 · 근거 · 시간이 지나면 흐려짐")
        } footer: {
            Text("왼쪽으로 밀어 ‘잊기’를 누르면 다시 쓰지 않아요. 신뢰도가 애매한 것은 홈에서 한 번 물어봐요.")
        }
    }

    // 배움: 개입 결과
    private var outcomeSection: some View {
        let resolved = memory.interventions.filter { $0.outcome != .pending }
        return Section {
            HStack(spacing: 14) {
                stat("\(resolved.count)", "결과가 난 개입")
                stat(memory.interruptionRate.map { "\(Int($0 * 100))%" } ?? "-", "방해율\n(무시된 비율)")
                stat(resolved.isEmpty ? "-" : "\(resolved.filter { $0.outcome == .accepted }.count * 100 / resolved.count)%", "받아들임")
            }
            ForEach(Array(memory.interventions.suffix(6).reversed())) { r in
                HStack {
                    Image(systemName: r.outcome == .accepted ? "checkmark.circle.fill" : (r.outcome == .ignored ? "xmark.circle" : "clock"))
                        .foregroundStyle(r.outcome == .accepted ? .green : (r.outcome == .ignored ? .gray : .orange))
                    VStack(alignment: .leading) {
                        Text("\(r.kindLabel) · \(toneLabel(r.tone))").font(.subheadline)
                        Text("\(r.time.formatted(.dateTime.month().day().hour().minute())) · \(r.detail)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("배움 — 개입과 결과")
        }
    }

    // 4층: 사용자 선언
    private var declaredSection: some View {
        Section {
            row("bed.double", "취침 목표", Clock.text(ctx.profile.bedtimeMinutes))
            row("target", "목표 수면", Clock.durationText(ctx.profile.goalSleepMinutes))
            row("bell.slash", "저녁 알림 최대", "\(ctx.profile.maxEveningNotifications)개")
            row("hourglass", "취침 전 앱 한도", "\(usage.settings.eveningLimitMinutes)분")
        } header: {
            layerHeader(4, "사용자 선언", "직접 정한 것 · 추론이 덮어쓰지 않음")
        } footer: {
            Text("설정에서 바꿀 수 있어요.")
        }
    }

    private func episodeLine(_ e: DayEpisode) -> String {
        var p: [String] = []
        if let d = e.bedDelayMin { p.append(d > 0 ? "\(d)분 늦게 잠" : "목표 시간에 잠") }
        if let a = e.asleepMin { p.append("수면 \(SleepStats.hm(a))") }
        if let m = e.mood { p.append(m.rawValue) }
        if e.eveningAppMin > 0 { p.append("밤 앱 \(e.eveningAppMin)분") }
        if !e.interventions.isEmpty {
            p.append("개입 \(e.interventions.count) (수락 \(e.interventions.filter { $0.outcome == .accepted }.count))")
        }
        return p.joined(separator: " · ")
    }

    private func toneLabel(_ t: String) -> String {
        t == "firm" ? "단호" : (t == "cheerful" ? "응원" : "부드럽게")
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func layerHeader(_ n: Int, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 6) {
            Text("\(n)층").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.purple.opacity(0.15))).foregroundStyle(.purple)
            Text(title)
            Text("· \(sub)").font(.caption2).foregroundStyle(.secondary).textCase(nil)
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.purple)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FactRow: View {
    let fact: PatternFact
    let now: Date

    var body: some View {
        let c = fact.confidence(now: now)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(fact.title).font(.subheadline)
                Spacer()
                Text(fact.source.rawValue).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(fact.source == .confirmed ? Color.green.opacity(0.15) : Color.gray.opacity(0.15)))
                    .foregroundStyle(fact.source == .confirmed ? .green : .secondary)
            }
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.15))
                        Capsule().fill(c >= 0.65 ? Color.purple : (c >= 0.4 ? .orange : .gray)).frame(width: g.size.width * c)
                    }
                }
                .frame(height: 6)
                Text("신뢰도 \(Int(c * 100))% · 근거 \(fact.evidence)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}
