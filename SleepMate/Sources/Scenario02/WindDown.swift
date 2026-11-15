import SwiftUI

// 시나리오 02: 취침 전 사용자를 편안하게
// 발생 조건: 취침 준비 시간(취침 90분 전) + 화면 사용
// 개입 단계: 90분 전 패턴 확인 → 목표 접근 알림 → 30분 전 준비 시작(집중 모드·음악)
// 제약: 실제 앱 사용량 자동 측정(Screen Time API)은 Apple 승인 권한(Family Controls)이 필요해
//       무료 계정 설치로는 불가 → MVP는 사용자가 직접/알림 버튼으로 기록

enum WindDownPlan {
    struct Step: Identifiable {
        let id: String
        let minutes: Int          // 자정 기준
        let title: String
        let body: String
        let category: String?
    }

    static func steps(_ p: UserProfile) -> [Step] {
        let bed = p.bedtimeMinutes
        return [
            Step(id: "winddown-1", minutes: bed - p.windDownLeadMinutes,
                 title: "취침 준비 \(p.windDownLeadMinutes)분 전이에요",
                 body: "오늘 화면 목표는 \(p.screenGoal)\(p.screenUnit)예요. 슬슬 마무리할 준비를 해 볼까요?",
                 category: NotificationService.windDownCategory),
            Step(id: "winddown-2", minutes: bed - 60,
                 title: "화면 목표 확인",
                 body: "지금까지 얼마나 봤는지 버튼으로 기록해 주세요. 목표에 가까우면 여기서 멈춰도 좋아요.",
                 category: NotificationService.screenCheckCategory),
            Step(id: "winddown-3", minutes: bed - 30,
                 title: "취침 준비 시작",
                 body: "화면 밝기를 낮추고 집중 모드를 켜 보세요. SleepMate에서 오늘 기분에 맞는 수면 음악을 골라 드려요.",
                 category: NotificationService.windDownCategory),
        ]
    }

    /// GUARD를 통과한 단계만 매일 알림으로 등록
    @MainActor
    static func schedule(_ p: UserProfile) async -> Int {
        await NotificationService.shared.cancel(prefix: "winddown-")
        var sent = 0
        for st in steps(p) {
            let g = AgentGuard.check(AgentAction(kind: .notify, title: st.title, requiresApproval: false),
                                     profile: p, eveningNotificationsSent: sent)
            AgentLog.shared.add(.windDown, path: .rule, action: "\(Clock.text(st.minutes)) ‘\(st.title)’",
                                guardNote: g.allowed ? "허용" : g.note)
            guard g.allowed else { continue }
            NotificationService.shared.scheduleDaily(id: st.id, minutes: st.minutes, title: st.title,
                                                     body: st.body, category: st.category)
            sent += 1
        }
        return sent
    }

    /// 화면 목표 메시지 (처벌이 아니라 안내 톤)
    static func screenMessage(count: Int, goal: Int, unit: String, stopped: Bool) -> String {
        if stopped { return "오늘은 여기까지 하기로 했어요. 잘 하셨어요 👏" }
        let left = goal - count
        if count == 0 { return "아직 기록이 없어요. 볼 때마다 + 버튼으로 기록해 주세요." }
        if left > 10 { return "오늘 목표까지 \(left)\(unit) 남았어요." }
        if left > 0 { return "목표까지 \(left)\(unit) 남았어요. 슬슬 마무리해 볼까요?" }
        if left == 0 { return "목표에 도달했어요. 오늘은 여기까지 어때요?" }
        return "목표보다 \(-left)\(unit) 더 봤어요. 지금 멈추면 내일 아침이 더 가벼울 거예요."
    }

    struct MusicPick: Hashable {
        let title: String
        let query: String
    }

    /// 기분에 맞는 수면 음악 (검색어 3개)
    static func music(for mood: Mood?, preference: String) -> [MusicPick] {
        let pairs: [(String, String)]
        switch mood {
        case .stressed, .anxious:
            pairs = [("마음을 가라앉히는 빗소리", "빗소리 수면"), ("느린 호흡 명상 음악", "수면 명상 음악"),
                     (preference, preference + " 수면")]
        case .tired:
            pairs = [("바로 잠드는 화이트노이즈", "화이트노이즈 수면"), (preference, preference + " 수면"),
                     ("잔잔한 앰비언트", "앰비언트 수면 음악")]
        default:
            pairs = [(preference, preference + " 수면"), ("로파이 수면 음악", "lofi sleep"),
                     ("자연의 소리", "자연 소리 수면")]
        }
        return pairs.map { MusicPick(title: $0.0, query: $0.1) }
    }
}

/// "늦게 잘 경우" 가정형 시각화
struct LateSleepChart: View {
    let bedtimeMinutes: Int
    let wakeMinutes: Int
    let goalMinutes: Int

    private struct Row: Hashable {
        let label: String
        let sleep: Int
    }

    private var rows: [Row] {
        [0, 30, 60, 90].map { delay in
            let bed = bedtimeMinutes + delay
            var dur = wakeMinutes - bed
            if dur <= 0 { dur += 1440 }
            return Row(label: delay == 0 ? "\(Clock.text(bed)) (목표)" : "\(Clock.text(bed)) (+\(delay)분)",
                       sleep: dur)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(r.label)에 잔다면").font(.caption)
                        Spacer()
                        Text("약 \(Clock.durationText(r.sleep))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    GeometryReader { geo in
                        let ratio = min(1, Double(r.sleep) / Double(max(goalMinutes, 1)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                            Capsule().fill(ratio >= 0.95 ? Color.indigo : (ratio >= 0.8 ? Color.blue : Color.orange))
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 8)
                }
            }
            Text("기상 \(Clock.text(wakeMinutes)) 기준, 잠드는 데 걸리는 시간은 빼고 계산한 가정이에요.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct WindDownView: View {
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @Environment(\.openURL) private var openURL
    @State private var scheduledCount: Int?
    @State private var notifAllowed = true
    @State private var nudge: WindDownDecision?

    private var wakeMinutes: Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let items = calendar.items(on: tomorrow, fixedKeywords: ctx.profile.fixedKeywords)
        return AlarmPlanner.plan(profile: ctx.profile, tomorrowItems: items).wakeMinutes
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BedtimeCountdown(profile: ctx.profile, now: AppClock.now)
                    WindDownTimelineChart(profile: ctx.profile, now: AppClock.now)
                        .padding(.top, 8)
                } header: {
                    Text("지금")
                }
                nudgeSection
                screenSection
                SoundscapeSection()
                breathingSection
                prepareSection
                lateSection
                timelineSection
                limitSection
            }
            .navigationTitle("취침 준비")
            .onAppear {
                ctx.rollOverIfNeeded()
                ctx.syncScreenCountFromNotifications()
            }
            .task { notifAllowed = await NotificationService.shared.isAuthorized() }
        }
    }

    // 개입 단계
    private var timelineSection: some View {
        Section {
            ForEach(WindDownPlan.steps(ctx.profile)) { st in
                HStack(alignment: .top, spacing: 12) {
                    Text(Clock.hhmm(st.minutes))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.title).font(.subheadline.weight(.semibold))
                        Text(st.body).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                Text(Clock.hhmm(ctx.profile.bedtimeMinutes))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .frame(width: 52, alignment: .leading)
                Label("취침 목표", systemImage: "moon.zzz.fill").font(.subheadline.weight(.semibold))
            }
            Button {
                Task {
                    if !notifAllowed { notifAllowed = await NotificationService.shared.requestAuthorization() }
                    if notifAllowed { scheduledCount = await WindDownPlan.schedule(ctx.profile) }
                }
            } label: {
                Label(scheduledCount == nil ? "매일 이 순서로 알림 받기" : "알림 \(scheduledCount!)개 등록됨 (다시 등록)",
                      systemImage: "bell.badge")
            }
            if !notifAllowed {
                Text("알림이 꺼져 있어요. 설정 → 앱 → SleepMate → 알림에서 켜 주세요.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("오늘 밤 흐름")
        } footer: {
            Text("알림 빈도와 시각은 설정 탭에서 바꿀 수 있어요. 저녁 알림은 최대 \(ctx.profile.maxEveningNotifications)개까지만 보냅니다.")
        }
    }

    // 화면 목표 카운터
    private var screenSection: some View {
        let count = ctx.today.screenCount
        let goal = ctx.profile.screenGoal
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    ScreenGauge(count: count, goal: goal, unit: ctx.profile.screenUnit)
                        .padding(.leading, 8)
                    Text(WindDownPlan.screenMessage(count: count, goal: goal, unit: ctx.profile.screenUnit,
                                                    stopped: ctx.today.stoppedScreen))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                HStack {
                    ForEach([1, 5, 10], id: \.self) { n in
                        Button("+\(n)") { ctx.addScreen(n) }.buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("오늘은 여기까지") {
                        ctx.stopScreen()
                        ctx.record(scenario: "02", key: "screen-stop", title: "화면 그만 보기", response: .accepted)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ctx.today.stoppedScreen)
                }
                Button("초기화", role: .destructive) { ctx.resetScreen() }
                    .font(.caption)
                Text("최근 7일").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                ScreenHistoryChart(history: [ctx.today] + ctx.history, goal: goal)
            }
            .padding(.vertical, 4)
        } header: {
            Text("오늘 화면 목표 (예: 쇼츠 개수)")
        }
    }

    private var lateSection: some View {
        Section {
            LateSleepChart(bedtimeMinutes: ctx.profile.bedtimeMinutes, wakeMinutes: wakeMinutes,
                           goalMinutes: ctx.profile.goalSleepMinutes)
                .padding(.vertical, 4)
        } header: {
            Text("늦게 잔다면 수면 시간은?")
        }
    }

    // 집중 모드 · 수면 음악
    private var prepareSection: some View {
        Section {
            Button {
                var c = URLComponents()
                c.scheme = "shortcuts"; c.host = "run-shortcut"
                c.queryItems = [URLQueryItem(name: "name", value: "SleepMate 취침 모드")]
                if let u = c.url { openURL(u) }
                ctx.record(scenario: "02", key: "focus", title: "취침 모드", response: .accepted)
            } label: {
                Label("취침 모드 켜기 (단축어)", systemImage: "moon.circle")
            }
            Text("단축어 앱에 ‘SleepMate 취침 모드’를 만들어 두면(동작: 집중 모드 설정 → 수면 켜기, 밝기 설정 30%) 이 버튼으로 한 번에 켜져요.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("취침 모드")
        }
    }

    // AI(Jev 또는 규칙)가 지금 말을 걸지 판단
    private var nudgeSection: some View {
        Section {
            if let n = nudge {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: n.nudge ? "bell.badge.fill" : "moon.zzz")
                        .font(.title3)
                        .foregroundStyle(n.nudge ? .orange : .indigo)
                    Text(n.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                DecisionBars(decision: n.view)
            } else {
                HStack { ProgressView(); Text("지금 상황을 판단하는 중…").font(.caption) }
            }
        } header: {
            Text("SleepMate의 한마디")
        }
        .task(id: "\(ctx.today.screenCount)-\(ctx.today.stoppedScreen)-\(ctx.today.mood?.rawValue ?? "")") {
            let rt = RealtimeContext(now: AppClock.now, profile: ctx.profile, todayItems: [])
            let input = WindDownInput(minutesToBed: rt.minutesToBedtime, screenCount: ctx.today.screenCount,
                                      screenGoal: ctx.profile.screenGoal, stopped: ctx.today.stoppedScreen,
                                      mood: ctx.today.mood, fatigue: ctx.today.fatigue)
            let d = await JevDecisions.windDown(input)
            withAnimation(.snappy) { nudge = d }
        }
    }

    private var breathingSection: some View {
        Section {
            BreathingGuide().padding(.vertical, 6)
        } header: {
            Text("잠들기 전 1분 호흡")
        }
    }

    private var limitSection: some View {
        Section {
            Text("앱 사용 시간을 자동으로 세려면 Apple의 Screen Time 권한(Family Controls)이 필요한데, 이 권한은 유료 개발자 계정과 Apple 승인이 있어야 해요. 지금은 직접 기록하거나 알림의 +5/+10 버튼으로 기록합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("참고")
        }
    }
}
