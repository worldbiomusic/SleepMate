import SwiftUI

extension PersonalStore {
    /// 데모·테스트에서는 예시 사용자를 보여 준다 (저장 안 함)
    var effective: PersonalProfile {
        if (DemoMode.isOn || TestLab.shared.isOn || DemoTour.shared.isOn) && !profile.interviewDone {
            return Self.example
        }
        return profile
    }

    static var example: PersonalProfile {
        var p = PersonalProfile()
        p.workdayBed = 60; p.workdayWake = 8 * 60
        p.freeBed = 3 * 60; p.freeWake = 11 * 60
        p.problems = [.lateBed, .wakeTired]
        p.caffeineCups = 3; p.lastCaffeine = 17 * 60
        p.exercise = .evening; p.naps = false; p.alcoholPerWeek = 1
        p.lifestyle = "수업·연구"
        p.chosen = ["caffeine-cutoff", "morning-light", "screen-off", "todo-offload"]
        p.interviewDone = true
        return p
    }
}

// MARK: - 근거 수준 배지

struct EvidenceBadge: View {
    let level: EvidenceLevel
    var body: some View {
        Text("근거 \(level.grade)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch level.grade { case "A": return .green; case "B": return .blue; default: return .gray }
    }
}

// MARK: - 전략 고르기

struct StrategyPick: Identifiable {
    let strategy: SleepStrategy
    let reason: String
    var id: String { strategy.id }
}

struct StrategyPickerView: View {
    @Environment(ContextStore.self) private var ctx
    @State private var store = PersonalStore.shared
    @State private var showInterview = false

    var body: some View {
        let p = store.effective
        let recs = StrategyLibrary.recommend(p, bedtime: ctx.profile.bedtimeMinutes)
            .map { StrategyPick(strategy: $0.0, reason: $0.1) }
        let recIDs = Set(recs.map(\.id))
        List {
            Section {
                if p.interviewDone {
                    personalSummary(p)
                } else {
                    Button { showInterview = true } label: {
                        Label("AI와 2분 대화하고 맞춤 추천 받기", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    NavigationLink("대화 없이 직접 입력") { ManualProfileForm() }
                }
            } header: { Text("나") }

            Section {
                ForEach(recs) { r in
                    StrategyRow(strategy: r.strategy, reason: r.reason, chosen: p.chosen.contains(r.id)) {
                        store.toggle(r.id)
                    }
                }
            } header: {
                Text("나에게 추천")
            } footer: {
                Text("2~3개만 골라도 충분해요. 고른 전략은 '지금' 화면의 알맞은 시간대에 한 줄씩 나와요.")
            }

            Section {
                ForEach(StrategyLibrary.all.filter { !recIDs.contains($0.id) }) { s in
                    StrategyRow(strategy: s, reason: nil, chosen: p.chosen.contains(s.id)) { store.toggle(s.id) }
                }
            } header: {
                Text("모든 전략")
            } footer: {
                Text("근거 A: 임상 가이드라인·메타분석·전문가 합의 · B: 무작위 시험·대규모 관찰 연구 · C: 소규모 실험·리뷰. 각 전략을 누르면 논문 원문(DOI)으로 바로 갈 수 있어요. SleepMate는 의료 진단·치료를 대신하지 않아요.")
            }
        }
        .navigationTitle("수면 전략")
        .sheet(isPresented: $showInterview) { NavigationStack { InterviewView() } }
    }

    @ViewBuilder
    private func personalSummary(_ p: PersonalProfile) -> some View {
        if let c = StrategyLibrary.chronotype(p) {
            LabeledContent("크로노타입", value: c.rawValue)
        }
        if let j = StrategyLibrary.socialJetlag(p) {
            LabeledContent("평일·쉬는 날 차이", value: Clock.durationText(j))
        }
        if !p.problems.isEmpty {
            LabeledContent("고민", value: p.problems.map(\.label).joined(separator: ", "))
        }
        if p.redFlag {
            Label("대화 중 말한 증상은 전문가 상담을 권해요. 수면 클리닉이나 가까운 병원과 이야기해 보세요.",
                  systemImage: "cross.case").font(.footnote).foregroundStyle(.orange)
        }
        Button("다시 대화하기") { showInterview = true }.font(.callout)
        NavigationLink("직접 고치기") { ManualProfileForm() }.font(.callout)
    }
}

struct StrategyRow: View {
    let strategy: SleepStrategy
    let reason: String?
    let chosen: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(chosen ? Color.accentColor : Color.gray)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chosen ? "선택 해제" : "선택")
            NavigationLink {
                StrategyDetailView(strategy: strategy)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: strategy.icon).foregroundStyle(.indigo)
                        Text(strategy.title).font(.subheadline.weight(.semibold))
                    }
                    Text(reason ?? strategy.summary).font(.caption).foregroundStyle(.secondary)
                    EvidenceBadge(level: strategy.bestLevel)
                }
            }
        }
    }
}

// MARK: - 전략 자세히 (근거 확인)

struct StrategyDetailView: View {
    let strategy: SleepStrategy
    @Environment(ContextStore.self) private var ctx
    @State private var store = PersonalStore.shared

    var body: some View {
        let chosen = store.effective.chosen.contains(strategy.id)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(strategy.title, systemImage: strategy.icon).font(.title3.weight(.bold))
                    Text(strategy.summary).foregroundStyle(.secondary)
                    Text("오늘 할 일: " + StrategyLibrary.todayAction(strategy, profile: ctx.profile, personal: store.effective))
                        .font(.callout.weight(.semibold))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.08)))
                }
                .padding(.vertical, 4)
                Button {
                    store.toggle(strategy.id)
                } label: {
                    Label(chosen ? "이 전략 그만 쓰기" : "이 전략 쓰기",
                          systemImage: chosen ? "minus.circle" : "plus.circle.fill")
                }
            }
            Section {
                ForEach(strategy.evidence) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            EvidenceBadge(level: e.level)
                            Text(e.level.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(e.finding).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(e.citation).font(.caption.weight(.semibold))
                        Text(e.title).font(.caption2).foregroundStyle(.secondary).italic()
                        Link(destination: e.url) {
                            Label("논문 보기 · doi:\(e.doi)", systemImage: "arrow.up.right.square").font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("근거")
            }
            Section {
                Text(strategy.appHelp).font(.callout)
                if let c = strategy.caution {
                    Label(c, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("SleepMate가 돕는 방법")
            }
        }
        .navigationTitle("근거 확인")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - '지금' 화면용: 고른 전략 한 줄씩

struct StrategyNowSection: View {
    let mode: NowMode
    @Environment(ContextStore.self) private var ctx
    @State private var store = PersonalStore.shared
    @State private var open: SleepStrategy?

    var body: some View {
        let p = store.effective
        let list = StrategyLibrary.forNow(mode, personal: p)
        if !list.isEmpty {
            Section {
                ForEach(list) { s in
                    Button { open = s } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.icon).foregroundStyle(.indigo).frame(width: 24)
                            Text(StrategyLibrary.todayAction(s, profile: ctx.profile, personal: p))
                                .font(.callout).foregroundStyle(.primary)
                            Spacer()
                            EvidenceBadge(level: s.bestLevel)
                        }
                    }
                    // 자기 전 할 일 적기 → 노션으로 바로
                    if s.id == "todo-offload", NotionStore.shared.isConfigured,
                       let url = URL(string: NotionStore.shared.link) {
                        Link(destination: url) {
                            Label("노션에 내일 할 일 적기", systemImage: "square.and.pencil").font(.footnote)
                        }
                    }
                }
            } header: {
                Text("내 전략")
            }
            .sheet(item: $open) { s in
                NavigationStack { StrategyDetailView(strategy: s) }
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - AI 인터뷰

struct InterviewView: View {
    @Environment(ContextStore.self) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var store = PersonalStore.shared
    @State private var shown: [InterviewClient.Turn] = [.init(role: .assistant, text: InterviewClient.opening.reply)]
    @State private var history: [InterviewClient.Turn] = []
    @State private var quick: [String] = InterviewClient.opening.quickReplies
    @State private var text = ""
    @State private var loading = false
    @State private var error: String?
    @State private var done = false
    @State private var redFlag = false
    private let hasKey = KeyStore.load() != nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("대화 내용은 답을 만들려고 Claude API로 보내져요. 결과는 이 기기에만 저장해요. 이름이나 병명은 말하지 않아도 돼요.",
                              systemImage: "lock.shield")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                            bubble(t)
                        }
                        if loading { ProgressView().padding(.leading, 8) }
                        if redFlag {
                            Label("말씀하신 증상은 앱보다 전문가가 더 잘 도와줄 수 있어요. 수면 클리닉 상담을 권해요.",
                                  systemImage: "cross.case.fill")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        if let error {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(error).font(.footnote).foregroundStyle(.orange)
                                NavigationLink("대화 없이 직접 입력하기") { ManualProfileForm() }
                            }
                        }
                        if done {
                            NavigationLink {
                                StrategyPickerView()
                            } label: {
                                Label("나에게 맞는 전략 보기", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .onChange(of: shown.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
            }
            if !done {
                inputBar
            }
        }
        .navigationTitle("나에게 맞추기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if !done && history.count >= 2 { Button("여기까지") { finish() } }
            }
        }
        .task {
            if !hasKey { error = "AI 키가 없어 대화를 할 수 없어요. 직접 입력으로 바로 정할 수 있어요." }
        }
    }

    private func bubble(_ t: InterviewClient.Turn) -> some View {
        HStack {
            if t.role == .user { Spacer(minLength: 40) }
            Text(t.text)
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(t.role == .user ? Color.accentColor : Color.gray.opacity(0.15)))
                .foregroundStyle(t.role == .user ? Color.white : Color.primary)
            if t.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !quick.isEmpty && !loading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(quick, id: \.self) { q in
                            Button(q) { send(q) }.buttonStyle(.bordered).font(.footnote)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            HStack {
                TextField("편하게 적어 주세요", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button { send(text) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || loading || !hasKey)
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(.bar)
    }

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, hasKey, !loading else { return }
        text = ""
        quick = []
        error = nil
        let turn = InterviewClient.Turn(role: .user, text: t)
        shown.append(turn)
        history.append(turn)
        loading = true
        Task {
            defer { loading = false }
            do {
                let step = try await InterviewClient.next(history: history, known: store.profile,
                                                          model: CoachSettings.load().model)
                store.update { $0.merge(step.update) }
                if step.redFlag { redFlag = true; store.update { $0.redFlag = true } }
                let reply = InterviewClient.Turn(role: .assistant, text: step.reply)
                shown.append(reply)
                history.append(reply)
                quick = step.quickReplies
                AgentLog.shared.add(.planToday, path: .llm, action: "첫 설정 대화 \(history.count / 2)턴")
                if step.done || store.profile.missingTopics.isEmpty { finish() }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finish() {
        store.update { p in
            p.interviewDone = true
            if p.chosen.isEmpty {
                p.chosen = StrategyLibrary.recommend(p, bedtime: p.workdayBed ?? ctx.profile.bedtimeMinutes, limit: 3).map { $0.0.id }
            }
        }
        store.applyToContext(ctx)
        done = true
    }
}

// MARK: - 대화 없이 직접 입력

struct ManualProfileForm: View {
    @Environment(ContextStore.self) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var store = PersonalStore.shared
    @State private var p = PersonalStore.shared.profile

    private func time(_ kp: WritableKeyPath<PersonalProfile, Int?>, _ def: Int) -> Binding<Date> {
        Binding(get: { Clock.date(fromMinutes: p[keyPath: kp] ?? def) },
                set: { p[keyPath: kp] = Clock.minutes(of: $0) })
    }

    var body: some View {
        Form {
            Section("평일") {
                DatePicker("취침", selection: time(\.workdayBed, ctx.profile.bedtimeMinutes), displayedComponents: .hourAndMinute)
                DatePicker("기상", selection: time(\.workdayWake, ctx.profile.defaultWakeMinutes), displayedComponents: .hourAndMinute)
            }
            Section("쉬는 날") {
                DatePicker("취침", selection: time(\.freeBed, 60), displayedComponents: .hourAndMinute)
                DatePicker("기상", selection: time(\.freeWake, 9 * 60), displayedComponents: .hourAndMinute)
            }
            Section("고민 (여러 개 가능)") {
                ForEach(SleepProblem.allCases) { pr in
                    Toggle(pr.label, isOn: Binding(
                        get: { p.problems.contains(pr) },
                        set: { on in
                            if on { if !p.problems.contains(pr) { p.problems.append(pr) } }
                            else { p.problems.removeAll { $0 == pr } }
                        }))
                }
            }
            Section("카페인") {
                Stepper("하루 \(p.caffeineCups ?? 0)잔", value: Binding(get: { p.caffeineCups ?? 0 },
                                                                     set: { p.caffeineCups = $0 }), in: 0...10)
                DatePicker("마지막 카페인", selection: time(\.lastCaffeine, 15 * 60), displayedComponents: .hourAndMinute)
                Toggle("카페인에 예민한 편", isOn: Binding(get: { p.caffeineSensitive ?? false },
                                                        set: { p.caffeineSensitive = $0 }))
            }
            Section("생활") {
                Picker("운동", selection: Binding(get: { p.exercise ?? .rarely }, set: { p.exercise = $0 })) {
                    ForEach(PersonalProfile.ExerciseTime.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("낮잠을 자는 편", isOn: Binding(get: { p.naps ?? false }, set: { p.naps = $0 }))
                Stepper("술 주 \(p.alcoholPerWeek ?? 0)회", value: Binding(get: { p.alcoholPerWeek ?? 0 },
                                                                       set: { p.alcoholPerWeek = $0 }), in: 0...7)
                Picker("생활 형태", selection: Binding(get: { p.lifestyle ?? "수업·연구" }, set: { p.lifestyle = $0 })) {
                    ForEach(["수업·연구", "출근", "교대 근무", "자유"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
                Button("저장하고 추천 보기") {
                    var q = p
                    q.interviewDone = true
                    if q.chosen.isEmpty {
                        q.chosen = StrategyLibrary.recommend(q, bedtime: q.workdayBed ?? ctx.profile.bedtimeMinutes, limit: 3).map { $0.0.id }
                    }
                    store.update { $0 = q }
                    store.applyToContext(ctx)
                    dismiss()
                }
            } footer: {
                Text("이 기기에만 저장해요. 평일 취침·기상 시각은 앱의 취침 목표·평소 기상으로도 쓰여요.")
            }
        }
        .navigationTitle("직접 입력")
    }
}
