import SwiftUI

/// '지금' 탭에서 여는 자세한 화면 (예전 탭들 — 지우지 않고 시트로 연다)
enum NowDetail: String, Identifiable {
    case today, winddown, alarm, guide, sound, breathing, usageSetup, shortcutGuide
    var id: String { rawValue }
}

/// '지금' 탭: 시간대에 맞는 카드 하나 + 버튼 1~2개
/// 내부 판단(규칙/Jev/Claude, 확률)은 '왜 이런 제안?' 안에만 보여 준다.
struct NowView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @Environment(CoachStore.self) private var coach
    @State private var router = AppRouter.shared
    @State private var usage = UsageStore.shared
    @State private var notion = NotionStore.shared
    @State private var nudge: WindDownDecision?
    @State private var showWhy = false
    @State private var notifOn = true
    @AppStorage("showScoreNumber") private var showScore = false

    var body: some View {
        // 1분마다 다시 그려 카운트다운·모드가 저절로 바뀐다
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content(now: AppClock.now)
        }
        .task {
            notifOn = await NotificationService.shared.isAuthorized()
            if UserDefaults.standard.bool(forKey: "demoWhy") {      // CI 스크린샷용
                try? await Task.sleep(for: .seconds(2))
                showWhy = true
            }
        }
        .sheet(isPresented: $showWhy) { WhySheet(nudge: router.lastNudge ?? nudge) }
    }

    // MARK: 공통 계산

    private var stats: SleepStats? { SleepStats(nights: store.nights) }
    private var score: SleepScore.Breakdown? {
        stats.map { SleepScore.compute($0, goalMinutes: ctx.profile.goalSleepMinutes) }
    }
    private var hasData: Bool { store.hasData || store.isDemo }

    private func mode(_ now: Date) -> NowMode {
        let wake = stats.flatMap { s in
            s.wakeTime.flatMap { Calendar.current.isDate($0, inSameDayAs: now) ? Clock.minutes(of: $0) : nil }
        }
        return NowPlanner.mode(now: now, profile: ctx.profile, hasData: hasData, wakeMinutes: wake)
    }

    private func plannerInput(_ now: Date) -> DayPlanner.Input {
        DayPlanner.Input(stats: stats, score: score?.total, daily: ctx.today, profile: ctx.profile,
                         items: calendar.items(on: now, fixedKeywords: ctx.profile.fixedKeywords),
                         now: now, skipped: { ctx.isOftenSkipped($0) })
    }

    private func topRec(_ now: Date) -> DayRecommendation? {
        DayPlanner.recommendations(plannerInput(now)).first { $0.key != "stale" && $0.key != "nodata" }
    }

    private func tomorrowPlan(_ now: Date) -> AlarmPlanner.Plan {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return AlarmPlanner.plan(profile: ctx.profile,
                                 tomorrowItems: calendar.items(on: tomorrow, fixedKeywords: ctx.profile.fixedKeywords))
    }

    // MARK: 화면

    @ViewBuilder
    private func content(now: Date) -> some View {
        let m = mode(now)
        NavigationStack {
            List {
                switch m {
                case .start: OnboardingCard()
                case .morning: morningCard(now)
                case .day: dayCard(now)
                case .night: nightCard(now)
                }
                if m != .start {
                    if m == .day { MemoryQuestionCard() }
                    suggestions(m)
                    if m != .morning { wakeRow(now) }
                    whyRow
                    detailSection(m)
                }
            }
            .navigationTitle(title(m, now))
            .task(id: nightKey(m, now)) { await decideNight(m, now) }
            .onChange(of: m) { _, new in
                AgentLog.shared.add(.planToday, path: .rule, action: "지금 화면: \(new.rawValue) 모드")
            }
        }
    }

    private func title(_ m: NowMode, _ now: Date) -> String {
        switch m {
        case .start: return "시작하기"
        case .morning: return "좋은 아침이에요"
        case .day: return "오늘"
        case .night: return "오늘 밤"
        }
    }

    // MARK: 아침

    @ViewBuilder
    private func morningCard(_ now: Date) -> some View {
        Section {
            if let s = stats, let sc = score {
                let st = SleepStatus.from(score: sc.total)
                let line = NowPlanner.sleepLine(s)
                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(status: st, score: showScore ? sc.total : nil, big: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.main).font(.title3.weight(.semibold))
                        if let c = line.compare {
                            Text(c).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let r = topRec(now) {
                        OneThing(rec: r)
                    }
                    Button {
                        if coach.speech.isSpeaking { coach.stopSpeaking() } else {
                            coach.speak()
                            ctx.record(scenario: "05", key: "listen", title: "수면 요약 듣기", response: .helpful)
                        }
                    } label: {
                        Label(coach.speech.isSpeaking ? "그만 듣기" : "들어보기",
                              systemImage: coach.speech.isSpeaking ? "stop.fill" : "play.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coach.report == nil)
                    CheckInRow()
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: 낮

    @ViewBuilder
    private func dayCard(_ now: Date) -> some View {
        let input = plannerInput(now)
        let next = NowPlanner.nextThree(now: now, events: input.items, tasks: notion.tasks,
                                        tips: DayPlanner.recommendations(input))
        let proposals = DayPlanner.proposals(input)
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if let sc = score {
                    StatusBadge(status: .from(score: sc.total), score: showScore ? sc.total : nil, big: false)
                }
                if let r = topRec(now) { OneThing(rec: r) }
            }
            .padding(.vertical, 4)
        }
        Section {
            if next.isEmpty {
                Text("남은 일정이 없어요. 편하게 보내세요.").foregroundStyle(.secondary)
            }
            ForEach(next) { n in
                HStack(spacing: 12) {
                    Text(n.time.map { Fmt.time.string(from: $0) } ?? (n.kind == .tip ? "추천" : "오늘"))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(n.time == nil ? .secondary : .primary)
                        .frame(width: 52, alignment: .leading)
                    Image(systemName: n.icon).foregroundStyle(n.kind == .tip ? Color.orange : Color.accentColor)
                        .frame(width: 22)
                    Text(n.title).lineLimit(2)
                }
            }
            if !proposals.isEmpty {
                Button {
                    router.detail = .today
                } label: {
                    Label("일정 조정 제안 \(proposals.count)개 보기", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("다음 3가지")
        }
    }

    // MARK: 밤

    @ViewBuilder
    private func nightCard(_ now: Date) -> some View {
        let rt = RealtimeContext(now: now, profile: ctx.profile, todayItems: [])
        let used = usage.eveningMinutes(now: now, profile: ctx.profile)
        let limit = usage.settings.eveningLimitMinutes
        let stopped = ctx.today.stoppedScreen
        Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NowPlanner.countdown(minutesToBed: rt.minutesToBedtime))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(rt.minutesToBedtime < 0 ? .orange : .primary)
                    Text("취침 목표 \(Clock.hhmm(ctx.profile.bedtimeMinutes))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                UsageBar(used: used, limit: limit)
                if stopped {
                    Label("오늘은 여기까지 했어요. 잘 자요", systemImage: "moon.zzz.fill")
                        .font(.headline).foregroundStyle(.indigo)
                } else {
                    Text(nudge?.message ?? "지금 상황을 살펴보는 중이에요…")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        ctx.stopScreen()
                        ctx.record(scenario: "02", key: "screen-stop", title: "화면 그만 보기", response: .accepted)
                        MemoryStore.shared.markLatestAccepted(kinds: [.windDown, .appLimit, .bedtimeNotice], now: Date())
                        WatchBridge.shared.push()
                    } label: {
                        Text("오늘은 여기까지").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                }
                HStack(spacing: 10) {
                    Button { router.detail = .breathing } label: {
                        Label("호흡", systemImage: "wind").frame(maxWidth: .infinity)
                    }
                    Button { router.detail = .sound } label: {
                        Label("수면 소리", systemImage: "music.note").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 6)
        }
    }

    private func nightKey(_ m: NowMode, _ now: Date) -> String {
        guard m == .night else { return "off" }
        return "\(usage.eveningMinutes(now: now, profile: ctx.profile))-\(ctx.today.stoppedScreen)-\(ctx.today.mood?.rawValue ?? "")"
    }

    private func decideNight(_ m: NowMode, _ now: Date) async {
        guard m == .night else { return }
        let rt = RealtimeContext(now: now, profile: ctx.profile, todayItems: [])
        let input = WindDownInput(minutesToBed: rt.minutesToBedtime,
                                  screenCount: usage.eveningMinutes(now: now, profile: ctx.profile),
                                  screenGoal: usage.settings.eveningLimitMinutes,
                                  stopped: ctx.today.stoppedScreen,
                                  mood: ctx.today.mood, fatigue: ctx.today.fatigue,
                                  snapshot: MemoryStore.shared.snapshot(now: now, profile: ctx.profile))
        let d = await JevDecisions.windDown(input)
        withAnimation(.snappy) { nudge = d }
        router.lastNudge = d
        if d.nudge && !TestLab.shared.isOn && !DemoMode.isOn {
            MemoryStore.shared.recordInAppNudge(tone: d.tone.rawValue, detail: d.action.rawValue, now: Date())
        }
    }

    // MARK: 필요한 순간에만 보이는 연결 제안

    @ViewBuilder
    private func suggestions(_ m: NowMode) -> some View {
        if !DemoTour.shared.isOn && !DemoMode.isOn && !TestLab.shared.isOn {
            if m == .night && usage.lastEvent == nil {
                SuggestionRow(icon: "hourglass", text: "유튜브 같은 앱 시간을 자동으로 재 볼까요?") {
                    router.detail = .usageSetup
                }
            } else if m == .night && !notifOn {
                SuggestionRow(icon: "bell.badge", text: "취침 준비 알림을 켜면 화면을 안 열어도 돼요") {
                    Task {
                        notifOn = await NotificationService.shared.requestAuthorization()
                        if notifOn { _ = await WindDownPlan.schedule(ctx.profile) }
                    }
                }
            } else if m == .day && !calendar.isAuthorized {
                SuggestionRow(icon: "calendar", text: "캘린더를 연결하면 다음 일정도 함께 보여 줘요") {
                    Task { await calendar.requestAccess() }
                }
            }
        }
    }

    private func wakeRow(_ now: Date) -> some View {
        let p = tomorrowPlan(now)
        return Section {
            Button { router.detail = .alarm } label: {
                HStack(spacing: 12) {
                    Image(systemName: "alarm.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("내일 \(Clock.hhmm(p.wakeMinutes)) 기상").font(.headline).foregroundStyle(.primary)
                        Text(p.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var whyRow: some View {
        Section {
            Button { showWhy = true } label: {
                Label("왜 이런 제안?", systemImage: "questionmark.circle")
            }
        }
    }

    private func detailSection(_ m: NowMode) -> some View {
        Section {
            Button { router.detail = .today } label: { Label("오늘 계획 자세히", systemImage: "sun.max") }
            Button { router.detail = .winddown } label: { Label("취침 준비 자세히", systemImage: "bed.double") }
            Button { router.detail = .alarm } label: { Label("알람 자세히", systemImage: "alarm") }
        } header: {
            Text("자세히")
        }
        .font(.callout)
    }
}

// MARK: - 작은 부품

/// 상태 단어 + 색 (점수 숫자는 선택)
struct StatusBadge: View {
    let status: SleepStatus
    var score: Int?
    var big = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.icon)
                .font(big ? .title : .title3)
                .foregroundStyle(status.color)
            Text(status.word)
                .font(big ? .title.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(status.color)
            if let score {
                Text("\(score)점").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 오늘의 한 가지
struct OneThing: View {
    let rec: DayRecommendation
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: rec.icon).font(.title3).foregroundStyle(.orange).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("오늘의 한 가지").font(.caption).foregroundStyle(.secondary)
                Text(rec.title).font(.headline)
                Text(rec.detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
    }
}

/// 아침 한 번 탭 체크인 — 안 눌러도 된다 (수면으로 추정)
struct CheckInRow: View {
    @Environment(ContextStore.self) private var ctx

    var body: some View {
        let current = CheckIn.from(fatigue: ctx.today.fatigue)
        VStack(alignment: .leading, spacing: 6) {
            Text(current == nil ? "지금 컨디션은? (안 눌러도 돼요)" : "컨디션 기록됨 · 바꾸려면 다시 누르세요")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(CheckIn.allCases) { c in
                    Button {
                        ctx.today.fatigue = c.fatigue
                        if let m = c.mood { ctx.today.mood = m }
                        ctx.save()
                        WatchBridge.shared.push()
                    } label: {
                        Text("\(c.emoji) \(c.rawValue)").font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(current == c ? .accentColor : .gray)
                }
            }
        }
    }
}

/// 오늘 밤 앱 사용 막대
struct UsageBar: View {
    let used: Int
    let limit: Int
    var body: some View {
        let r = min(1.0, Double(used) / Double(max(limit, 1)))
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("오늘 밤 앱 사용", systemImage: "hourglass").font(.subheadline)
                Spacer()
                Text("\(used) / \(limit)분").font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(used > limit ? .red : .primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule().fill(r >= 1 ? Color.red : (r >= 0.8 ? .orange : .teal)).frame(width: g.size.width * r)
                }
            }
            .frame(height: 8)
        }
    }
}

struct SuggestionRow: View {
    let icon: String
    let text: String
    let action: () -> Void
    var body: some View {
        Section {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(.blue)
                    Text(text).font(.callout).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - 시작 3단계

struct OnboardingCard: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @State private var router = AppRouter.shared
    @State private var notifOn = false
    @AppStorage("onboardBedtimeSet") private var bedtimeSet = false

    private var bedtime: Binding<Date> {
        Binding(get: { Clock.date(fromMinutes: ctx.profile.bedtimeMinutes) },
                set: { ctx.profile.bedtimeMinutes = Clock.minutes(of: $0); ctx.save() })
    }

    var body: some View {
        Section {
            Text("세 가지만 하면 매일 따로 입력하지 않아도 돼요.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section {
            step(1, done: store.hasData, title: "수면 기록 연결",
                 sub: "단축어를 한 번 만들어 두면, 아침에 알람을 끌 때 자동으로 기록이 들어와요.") {
                Button { store.runShortcut() } label: {
                    Label("단축어로 가져오기", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                HStack {
                    Button("설정 방법") { router.detail = .shortcutGuide }
                    Spacer()
                    Button("예시 데이터로 둘러보기") { store.loadDemo() }
                }
                .font(.footnote).buttonStyle(.borderless)
            }
        }
        Section {
            step(2, done: bedtimeSet, title: "취침 목표",
                 sub: "이 시각을 기준으로 밤 준비와 내일 알람을 계산해요.") {
                DatePicker("취침", selection: bedtime, displayedComponents: .hourAndMinute)
                if !bedtimeSet {
                    Button("이 시각으로 할게요") { bedtimeSet = true }.buttonStyle(.bordered)
                }
            }
        }
        Section {
            step(3, done: notifOn, title: "알림 허용",
                 sub: "밤 준비 시작과 앱 시간 초과를 알려 줘요. 저녁 알림은 최대 \(ctx.profile.maxEveningNotifications)개.") {
                if !notifOn {
                    Button("알림 허용") {
                        Task {
                            notifOn = await NotificationService.shared.requestAuthorization()
                            if notifOn { _ = await WindDownPlan.schedule(ctx.profile) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } footer: {
            Text("노션 할 일, 앱 사용시간, AI 키는 필요할 때 '지금' 화면에서 제안하거나 설정에서 연결해요.")
        }
        .task { notifOn = await NotificationService.shared.isAuthorized() }
    }

    @ViewBuilder
    private func step<C: View>(_ n: Int, done: Bool, title: String, sub: String,
                               @ViewBuilder actions: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 30, height: 30)
                if done { Image(systemName: "checkmark").font(.callout.bold()).foregroundStyle(.white) }
                else { Text("\(n)").font(.callout.bold()).foregroundStyle(Color.accentColor) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(sub).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if !done || n == 2 { actions() }
    }
}

// MARK: - 왜 이런 제안?

struct WhySheet: View {
    var nudge: WindDownDecision?
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CoachStore.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = SleepStats(nights: store.nights)
        let sc = stats.map { SleepScore.compute($0, goalMinutes: ctx.profile.goalSleepMinutes) }
        let snap = MemoryStore.shared.snapshot(now: AppClock.now, profile: ctx.profile)
        NavigationStack {
            List {
                Section {
                    PathSteps(active: nudge?.view.path ?? .rule)
                    Text("대부분은 규칙으로 바로 정해요. 애매할 때만 빠른 판단 AI(Jev)에게 묻고, 아침 요약 문장은 Claude가 써요. 어떤 경우에도 일정·알람을 마음대로 바꾸지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("판단 순서") }

                if let n = nudge {
                    Section {
                        DecisionBars(decision: n.view)
                        if let note = n.learnedNote {
                            Label(note, systemImage: "brain").font(.caption).foregroundStyle(.purple)
                        }
                    } header: { Text("오늘 밤 한마디는 이렇게 정했어요") }
                }

                if let sc {
                    Section {
                        LabeledContent("수면 점수", value: "\(sc.total) / 100")
                        ScoreBreakdownRow(sc: sc)
                        Text("85 이상 ‘충분히 잤어요’ · 70 이상 ‘괜찮아요’ · 55 이상 ‘조금 부족해요’")
                            .font(.caption).foregroundStyle(.secondary)
                        if let r = coach.report {
                            LabeledContent("아침 요약", value: r.source == .claude ? "Claude가 작성" : "규칙으로 작성")
                        }
                        LabeledContent("컨디션",
                                       value: ctx.today.fatigue == nil ? "수면 기록으로 짐작" : "직접 고른 값 사용")
                    } header: { Text("상태 단어 계산") }
                }

                Section {
                    if snap.lines.isEmpty {
                        Text("아직 확실히 배운 습관이 없어요. 기록이 쌓이면 판단에 같이 써요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(snap.lines, id: \.self) { Label($0, systemImage: "brain").font(.callout) }
                    NavigationLink("나에 대한 기억 전체") { MemoryView() }
                } header: { Text("판단에 쓴 기억") }

                Section {
                    NavigationLink("판단 기록 전체") { AgentLogView() }
                }
            }
            .navigationTitle("왜 이런 제안?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

/// 규칙 → Jev → Claude 세 칸 (이번 판단이 쓴 칸을 진하게)
struct PathSteps: View {
    let active: ReasonPath
    var body: some View {
        HStack(spacing: 6) {
            chip("규칙", on: active == .rule)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            chip("Jev", on: active == .light)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            chip("Claude", on: active == .llm)
        }
    }
    private func chip(_ t: String, on: Bool) -> some View {
        Text(t).font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.accentColor : Color.gray.opacity(0.15)))
            .foregroundStyle(on ? .white : .secondary)
    }
}

/// 시트로 여는 자세한 화면
struct NowDetailSheet: View {
    let detail: NowDetail

    var body: some View {
        Group {
            switch detail {
            case .today: TodayView()
            case .winddown: WindDownView()
            case .alarm: AlarmView()
            case .guide: GuideView()
            case .shortcutGuide: ShortcutGuideView()
            case .sound:
                NavigationStack { List { SoundscapeSection() }.navigationTitle("수면 소리") }
            case .breathing:
                NavigationStack {
                    List { Section { BreathingGuide().padding(.vertical, 8) } footer: {
                        Text("4초 들이쉬고, 7초 멈추고, 8초 내쉬어요. 3~4번이면 충분해요.")
                    } }
                    .navigationTitle("호흡")
                }
            case .usageSetup:
                NavigationStack { UsageSetupView() }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
