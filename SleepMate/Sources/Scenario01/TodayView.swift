import SwiftUI

/// 시나리오 01 화면: 오늘 Context 입력 → 추천 → 피드백 → 일정 조정안 승인
struct TodayView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar

    @State private var items: [PlanItem] = []
    @State private var recs: [DayRecommendation] = []
    @State private var markers: [DayMarker] = []
    @State private var proposals: [ScheduleChange] = []
    @State private var decided: [UUID: FeedbackResponse] = [:]
    @State private var errorText: String?

    private var stats: SleepStats? { SleepStats(nights: store.nights) }
    private var score: SleepScore.Breakdown? {
        stats.map { SleepScore.compute($0, goalMinutes: ctx.profile.goalSleepMinutes) }
    }
    private var input: DayPlanner.Input {
        DayPlanner.Input(stats: stats, score: score?.total, daily: ctx.today, profile: ctx.profile,
                         items: items, now: AppClock.now, skipped: { ctx.isOftenSkipped($0) })
    }

    var body: some View {
        NavigationStack {
            List {
                contextSection
                flowSection
                recommendationSection
                NotionTasksSection(items: items,
                                   curve: EnergyModel.curve(wakeMinutes: wakeMinutesToday,
                                                            bedMinutes: ctx.profile.bedtimeMinutes,
                                                            score: score?.total, day: AppClock.now))
                scheduleSection
                if !proposals.isEmpty { proposalSection }
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("오늘의 추천")
            .task(id: calendar.revision) { reload() }
            .onChange(of: store.lastLoadedAt) { _, _ in reload() }
            .onChange(of: NotionStore.shared.lastSync) { _, _ in reload() }
            .onChange(of: ctx.today.fatigue) { _, _ in reload() }
            .refreshable { reload() }
        }
    }

    private func reload() {
        ctx.rollOverIfNeeded()
        items = calendar.items(on: AppClock.now, fixedKeywords: ctx.profile.fixedKeywords)
        recs = DayPlanner.recommendations(input)
        markers = DayPlanner.markers(input) + notionMarkers()
        proposals = DayPlanner.proposals(input)
        AgentLog.shared.add(.planToday, path: .rule,
                            action: "추천 \(recs.count)개 · 일정 조정안 \(proposals.count)개 (수면 부족 신호: \(DayPlanner.lowSleepSignal(input) ? "있음" : "없음"))")
        decided = [:]
    }

    // MARK: 오늘 Context (피로도·기분)

    private var contextSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                if let sc = score {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("수면 점수").font(.caption).foregroundStyle(.secondary)
                        Text("\(sc.total)").font(.system(size: 34, weight: .bold, design: .rounded))
                            + Text(" / 100").font(.callout).foregroundColor(.secondary)
                    }
                } else {
                    Text("수면 기록 없음").foregroundStyle(.secondary)
                }
                Spacer()
                if DayPlanner.lowSleepSignal(input) {
                    Label("회복 필요", systemImage: "battery.25")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("지금 피로도는요?").font(.subheadline)
                Picker("피로도", selection: Binding(
                    get: { ctx.today.fatigue ?? 0 },
                    set: { ctx.today.fatigue = $0 == 0 ? nil : $0; ctx.save() })) {
                    Text("-").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text("1 개운함 · 5 매우 피곤").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("기분").font(.subheadline)
                Spacer()
                ForEach(Mood.allCases) { m in
                    Button {
                        ctx.today.mood = (ctx.today.mood == m) ? nil : m
                        ctx.save()
                    } label: {
                        Text(m.emoji).font(.title3)
                            .padding(4)
                            .background(Circle().fill(ctx.today.mood == m ? Color.accentColor.opacity(0.25) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("오늘의 컨디션")
        }
    }

    /// 노션 할 일의 추천 시간 → 타임라인 표시
    private func notionMarkers() -> [DayMarker] {
        let curve = EnergyModel.curve(wakeMinutes: wakeMinutesToday, bedMinutes: ctx.profile.bedtimeMinutes,
                                      score: score?.total, day: AppClock.now)
        return NotionStore.shared.tasks(on: AppClock.now).compactMap { t in
            guard !t.done, t.time == nil, let c = t.cls,
                  let s = NotionParse.suggestedSlot(for: c, items: items, curve: curve,
                                                    day: AppClock.now, now: AppClock.now) else { return nil }
            return DayMarker(time: s, label: "📝" + String(t.title.prefix(4)), color: .purple)
        }
    }

    // MARK: 오늘의 흐름 (타임라인 + 추정 컨디션)

    private var wakeMinutesToday: Int {
        if let w = stats?.wakeTime, stats?.daysSinceLastNight ?? 9 <= 1 { return Clock.minutes(of: w) }
        return ctx.profile.defaultWakeMinutes
    }

    private var flowSection: some View {
        Section {
            DayTimelineChart(items: items, markers: markers, now: AppClock.now)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("예상 컨디션 흐름").font(.subheadline.weight(.semibold))
                EnergyCurveChart(points: EnergyModel.curve(wakeMinutes: wakeMinutesToday,
                                                           bedMinutes: ctx.profile.bedtimeMinutes,
                                                           score: score?.total),
                                 now: AppClock.now)
                Text("생체 리듬과 수면 점수로 만든 단순 추정이에요. 개인차가 있어요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("오늘의 흐름")
        } footer: {
            HStack(spacing: 12) {
                Label("고정 일정", systemImage: "square.fill").foregroundStyle(.gray)
                Label("조정 가능", systemImage: "square.fill").foregroundStyle(.green)
                Label("지금", systemImage: "line.diagonal").foregroundStyle(.red)
            }
            .font(.caption2)
        }
    }

    // MARK: 추천 + 피드백

    private var recommendationSection: some View {
        Section {
            ForEach(recs) { rec in
                RecommendationRow(rec: rec, response: ctx.todayResponse(for: rec.key)) { resp in
                    ctx.record(scenario: "01", key: rec.key, title: rec.title, response: resp)
                }
            }
        } header: {
            Text("AI가 제안하는 오늘의 행동")
        } footer: {
            Text("반응(도움 됐어요·나중에·건너뛰기)은 다음 추천에 반영돼요. 자주 건너뛴 추천은 뒤로 밀립니다.")
        }
    }

    // MARK: 오늘 일정

    private var scheduleSection: some View {
        Section {
            if !calendar.canShowItems {
                Button {
                    Task { await calendar.requestAccess() }
                } label: {
                    Label("아이폰 캘린더 연결하기", systemImage: "calendar.badge.plus")
                }
                Text("수업·회의 같은 일정을 보고 추천과 일정 조정안을 만들어요. iCloud·Google 캘린더가 아이폰에 연결돼 있으면 함께 보입니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("오늘 일정이 없어요.").foregroundStyle(.secondary)
            } else {
                ForEach(items) { it in
                    HStack {
                        Text(it.isAllDay ? "종일" : Fmt.time.string(from: it.start))
                            .font(.callout.monospacedDigit())
                            .frame(width: 80, alignment: .leading)
                        Text(it.title)
                        Spacer()
                        Text(it.isFixed ? "고정" : "조정 가능")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(it.isFixed ? Color.gray.opacity(0.2) : Color.green.opacity(0.18)))
                    }
                }
            }
        } header: {
            Text("오늘 일정")
        } footer: {
            if calendar.canShowItems {
                Text("제목에 ‘수업·회의·약속’ 등이 있거나 참석자가 있으면 고정 일정으로 보고 절대 옮기지 않아요. 키워드는 설정에서 바꿀 수 있어요.")
            }
        }
    }

    // MARK: 일정 조정안 (CURRENT → SUGGESTED, 승인 후 적용)

    private var proposalSection: some View {
        Section {
            ProposalCompareChart(items: items, proposals: proposals)
                .padding(.vertical, 4)
            ForEach(proposals) { p in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("현재").font(.caption2).foregroundStyle(.secondary)
                            Text(p.fromStart.map { Fmt.time.string(from: $0) } ?? "없음")
                                .font(.callout.monospacedDigit())
                                .strikethrough(p.kind == .move)
                        }
                        .frame(width: 80, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("제안").font(.caption2).foregroundStyle(.secondary)
                            Text("\(Fmt.time.string(from: p.toStart)) – \(Fmt.time.string(from: p.toEnd))")
                                .font(.callout.monospacedDigit().bold())
                        }
                        Spacer()
                    }
                    Text(p.kind == .move ? "‘\(p.title)’ 옮기기" : "‘\(p.title)’ 추가")
                        .font(.subheadline.weight(.semibold))
                    Text(p.reason).font(.footnote).foregroundStyle(.secondary)

                    if let d = decided[p.id] {
                        Label(d.rawValue, systemImage: d == .accepted ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.footnote).foregroundStyle(d == .accepted ? .green : .secondary)
                    } else {
                        HStack {
                            Button("적용") { apply(p) }.buttonStyle(.borderedProminent)
                            Button("거절") {
                                decided[p.id] = .rejected
                                ctx.record(scenario: "01", key: "schedule-\(p.kind == .move ? "move" : "break")",
                                           title: p.title, response: .rejected)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("일정 조정안")
        } footer: {
            Text("AI는 일정을 자동으로 바꾸지 않아요. ‘적용’을 눌렀을 때만 캘린더에 반영됩니다.")
        }
    }

    private func apply(_ p: ScheduleChange) {
        do {
            switch p.kind {
            case .move:
                if let id = p.itemID { try calendar.move(itemID: id, to: p.toStart) }
            case .addBreak:
                try calendar.add(title: p.title, start: p.toStart, end: p.toEnd, note: "SleepMate가 제안한 휴식")
            }
            decided[p.id] = .accepted
            ctx.record(scenario: "01", key: "schedule-\(p.kind == .move ? "move" : "break")",
                       title: p.title, response: .accepted)
            AgentLog.shared.add(.planToday, path: .rule, action: "일정 변경 적용: \(p.title)",
                                guardNote: "사용자 승인")
        } catch {
            errorText = "일정을 바꾸지 못했어요: \(error.localizedDescription)"
        }
    }
}

struct RecommendationRow: View {
    let rec: DayRecommendation
    let response: FeedbackResponse?
    let onFeedback: (FeedbackResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rec.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title).font(.body.weight(.semibold))
                    Text(rec.detail).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if rec.key != "nodata" && rec.key != "stale" {
                HStack(spacing: 8) {
                    ForEach([FeedbackResponse.helpful, .later, .skip], id: \.self) { r in
                        Button {
                            onFeedback(r)
                        } label: {
                            Text(r.rawValue).font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(response == r ? .accentColor : .gray)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
    }
}
