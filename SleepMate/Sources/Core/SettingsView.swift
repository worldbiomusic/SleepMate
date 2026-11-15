import SwiftUI

/// 설정 탭: 장기 Context 편집 · 평가 지표 · 에이전트 기록 · 권한 · AI 설정
struct SettingsView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @State private var showCoach = false
    @State private var showGuide = false
    @State private var keywords = ""
    @State private var notifAllowed: Bool?

    private func bind<T>(_ kp: WritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(get: { ctx.profile[keyPath: kp] },
                set: { ctx.profile[keyPath: kp] = $0; ctx.save() })
    }

    private func timeBind(_ kp: WritableKeyPath<UserProfile, Int>) -> Binding<Date> {
        Binding(get: { Clock.date(fromMinutes: ctx.profile[keyPath: kp]) },
                set: { ctx.profile[keyPath: kp] = Clock.minutes(of: $0); ctx.save() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FeedbackDonut(feedback: ctx.feedback.filter { $0.date >= Date().addingTimeInterval(-14 * 86400) })
                    ScenarioAcceptChart(feedback: ctx.feedback)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("판단 경로 (EVENT → REASON)").font(.caption).foregroundStyle(.secondary)
                        AgentPathChart(entries: AgentLog.shared.entries)
                    }
                } header: {
                    Text("한눈에 보기 · 최근 14일")
                }
                sleepGoalSection
                morningSection
                eveningSection
                personalSection
                metricsSection
                systemSection
            }
            .navigationTitle("설정 · Context")
            .sheet(isPresented: $showCoach) { CoachSettingsView() }
            .sheet(isPresented: $showGuide) { ShortcutGuideView() }
            .onAppear { keywords = ctx.profile.fixedKeywords.joined(separator: ", ") }
            .task { notifAllowed = await NotificationService.shared.isAuthorized() }
        }
    }

    // MARK: 장기 Context

    private var sleepGoalSection: some View {
        Section {
            Stepper("목표 수면 \(Clock.durationText(ctx.profile.goalSleepMinutes))",
                    value: bind(\.goalSleepMinutes), in: 300...600, step: 15)
            DatePicker("취침 목표", selection: timeBind(\.bedtimeMinutes), displayedComponents: .hourAndMinute)
        } header: {
            Text("수면 목표 (장기 Context)")
        }
    }

    private var morningSection: some View {
        Section {
            DatePicker("평소 기상", selection: timeBind(\.defaultWakeMinutes), displayedComponents: .hourAndMinute)
            DatePicker("최소 기상 (이보다 일찍 X)", selection: timeBind(\.earliestWakeMinutes),
                       displayedComponents: .hourAndMinute)
            Stepper("준비 시간 \(ctx.profile.prepMinutes)분", value: bind(\.prepMinutes), in: 10...180, step: 5)
            Stepper("이동 시간 \(ctx.profile.commuteMinutes)분", value: bind(\.commuteMinutes), in: 0...180, step: 5)
        } header: {
            Text("아침 · 기상 알람")
        }
    }

    private var eveningSection: some View {
        Section {
            Stepper("취침 \(ctx.profile.windDownLeadMinutes)분 전부터 준비",
                    value: bind(\.windDownLeadMinutes), in: 30...180, step: 15)
            Stepper("화면 목표 \(ctx.profile.screenGoal)\(ctx.profile.screenUnit)",
                    value: bind(\.screenGoal), in: 0...300, step: 5)
            HStack {
                Text("단위")
                TextField("개", text: bind(\.screenUnit)).multilineTextAlignment(.trailing)
            }
            Toggle("취침 준비 알림", isOn: bind(\.notifyWindDown))
            Stepper("저녁 알림 최대 \(ctx.profile.maxEveningNotifications)개",
                    value: bind(\.maxEveningNotifications), in: 0...5)
        } header: {
            Text("취침 전")
        } footer: {
            Text("바꾼 뒤에는 ‘취침 준비’ 탭에서 알림을 다시 등록해 주세요.")
        }
    }

    private var personalSection: some View {
        Section {
            HStack {
                Text("수면 음악 취향")
                TextField("잔잔한 피아노", text: bind(\.musicPreference)).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("고정 일정 키워드")
                TextField("수업, 회의, 약속", text: $keywords, axis: .vertical)
                    .font(.callout)
                    .onSubmit(saveKeywords)
                Button("키워드 저장", action: saveKeywords).font(.footnote)
            }
        } header: {
            Text("선호도")
        } footer: {
            Text("이 단어가 제목에 들어간 일정은 절대 옮기지 않아요 (GUARD).")
        }
    }

    private func saveKeywords() {
        ctx.profile.fixedKeywords = keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        ctx.save()
        calendar.revision += 1
    }

    // MARK: 평가 지표 (추천 수락률 · 완료율 · 취침 규칙성 · 만족도)

    private var metricsSection: some View {
        let m = ctx.metrics()
        let stats = SleepStats(nights: store.nights)
        return Section {
            LabeledContent("추천 반응 (14일)", value: "\(m.total)회")
            LabeledContent("수락률", value: m.total == 0 ? "-" : "\(m.acceptRate)%")
            LabeledContent("건너뛰기·거절", value: "\(m.skipped)회")
            LabeledContent("나중에", value: "\(m.later)회")
            LabeledContent("취침 규칙성 (편차)",
                           value: stats?.bedtimeSpreadMin.map { "±\($0)분" } ?? "기록 부족")
            NavigationLink("에이전트 판단 기록") { AgentLogView() }
            NavigationLink("최근 피드백") { FeedbackListView() }
        } header: {
            Text("평가 지표")
        }
    }

    // MARK: 시스템

    private var systemSection: some View {
        Section {
            NavigationLink {
                TestLabView()
            } label: {
                Label("테스트 · 더미 데이터 · 셀프 테스트", systemImage: "testtube.2")
            }
            NavigationLink {
                NotionSettingsView()
            } label: {
                LabeledContent {
                    Text(NotionStore.shared.isConfigured ? "연결됨" : "연결 안 됨")
                        .foregroundStyle(NotionStore.shared.isConfigured ? .green : .secondary)
                } label: {
                    Label("노션 할 일", systemImage: "checklist")
                }
            }
            NavigationLink {
                JevSettingsView()
            } label: {
                LabeledContent {
                    Text(JevClient.isConfigured ? "연결됨" : "규칙으로 동작")
                        .foregroundStyle(JevClient.isConfigured ? .green : .secondary)
                } label: {
                    Label("Jev · 빠른 판단 AI", systemImage: "bolt.horizontal.circle")
                }
            }
            Button("AI 요약 설정 (Claude)") { showCoach = true }
            Button("단축어 설정 방법") { showGuide = true }
            HStack {
                Text("캘린더")
                Spacer()
                if calendar.isAuthorized {
                    Text("연결됨").foregroundStyle(.green)
                } else {
                    Button("연결") { Task { await calendar.requestAccess() } }
                }
            }
            HStack {
                Text("알림")
                Spacer()
                if notifAllowed == true {
                    Text("허용됨").foregroundStyle(.green)
                } else {
                    Button("허용") {
                        Task { notifAllowed = await NotificationService.shared.requestAuthorization() }
                    }
                }
            }
            NavigationLink("앱 로그") { LogView() }
        } header: {
            Text("연결 · 권한")
        } footer: {
            Text("SleepMate는 웰니스·생활 습관 지원 서비스이며 의료 진단이나 치료를 대체하지 않습니다.")
        }
    }
}

struct AgentLogView: View {
    @State private var log = AgentLog.shared

    var body: some View {
        List {
            Section {
                Text("EVENT → REASON(규칙 / 경량 AI / LLM) → GUARD → ACT 순서로 기록됩니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if log.entries.isEmpty {
                Text("아직 기록이 없어요. 앱을 사용하면 쌓입니다.").foregroundStyle(.secondary)
            }
            ForEach(log.entries) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(e.event).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(e.path.rawValue)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(e.path == .llm ? Color.orange.opacity(0.2)
                                                       : Color.blue.opacity(0.15)))
                    }
                    Text(e.action).font(.footnote)
                    if let g = e.guardNote {
                        Label(g, systemImage: "shield.lefthalf.filled").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(Fmt.time.string(from: e.date)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("에이전트 기록")
    }
}

struct FeedbackListView: View {
    @Environment(ContextStore.self) private var ctx

    var body: some View {
        List {
            if ctx.feedback.isEmpty {
                Text("아직 피드백이 없어요.").foregroundStyle(.secondary)
            }
            ForEach(Array(ctx.feedback.reversed().prefix(50))) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("시나리오 \(f.scenario)").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(f.response.rawValue).font(.caption.weight(.semibold))
                            .foregroundStyle(f.response.isPositive ? .green : .secondary)
                    }
                    Text(f.itemTitle).font(.callout)
                    Text("\(Fmt.day.string(from: f.date)) \(Fmt.time.string(from: f.date))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("최근 피드백")
    }
}
