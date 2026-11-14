import SwiftUI

// 시나리오 04: 문맥 + 수면 데이터 기반 기상 알람
// 발생 조건: 다음 날 기상 제약(첫 일정)이 있을 때
// 판단: 첫 일정 − 준비 시간 − 이동 시간 → 기상 시각, 기상 − 목표 수면 − 15분 → 취침 목표 (규칙)
// 실행: 단축어로 아이폰 '시계' 앱에 진짜 알람 생성 (무음 모드에서도 울림, 네트워크 불필요)
//       + 백업 알림. 수면 단계 기반 '최적 기상 순간'은 측정 오차 때문에 MVP에서 비활성.

enum AlarmPlanner {
    struct Plan: Equatable {
        let wakeMinutes: Int          // 자정 기준
        let bedtimeMinutes: Int
        let firstEvent: PlanItem?
        let reason: String
        let clampedByEarliest: Bool
    }

    /// 순수 계산 (화면에서 자주 불러도 됨 — 기록은 남기지 않음)
    static func plan(profile p: UserProfile, tomorrowItems: [PlanItem]) -> Plan {
        let timed = tomorrowItems.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        // 첫 일정 = 가장 이른 일정 (고정이든 아니든 기상 제약)
        let first = timed.first
        var wake: Int
        var reason: String
        var clamped = false

        if let f = first {
            let start = Clock.minutes(of: f.start)
            wake = start - p.prepMinutes - p.commuteMinutes
            reason = "‘\(f.title)’ \(Clock.text(start)) − 준비 \(p.prepMinutes)분 − 이동 \(p.commuteMinutes)분"
            if wake < p.earliestWakeMinutes {
                wake = p.earliestWakeMinutes
                clamped = true
                reason += " (너무 일러서 최소 기상 \(Clock.text(p.earliestWakeMinutes))로 맞춤)"
            }
            if wake > p.defaultWakeMinutes + 120 {
                // 일정이 늦게 있어도 너무 늦잠 자지 않도록
                wake = p.defaultWakeMinutes + 60
                reason += " · 리듬 유지를 위해 평소 기상보다 1시간 늦은 정도로 제한"
            }
        } else {
            wake = p.defaultWakeMinutes
            reason = "내일 일정이 없어 평소 기상 시각을 사용"
        }
        wake = (wake / 5) * 5                          // 5분 단위로 내림
        let bed = wake - p.goalSleepMinutes - 15       // 잠드는 데 15분
        return Plan(wakeMinutes: wake, bedtimeMinutes: bed, firstEvent: first,
                    reason: reason, clampedByEarliest: clamped)
    }
}

struct AlarmView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @Environment(\.openURL) private var openURL

    @State private var tomorrowItems: [PlanItem] = []
    @State private var customWake: Date?
    @State private var backupScheduled = false
    @State private var message: String?

    private var plan: AlarmPlanner.Plan {
        AlarmPlanner.plan(profile: ctx.profile, tomorrowItems: tomorrowItems)
    }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() }
    private var wakeMinutes: Int { customWake.map { Clock.minutes(of: $0) } ?? plan.wakeMinutes }

    var body: some View {
        NavigationStack {
            List {
                planSection
                Section {
                    WakeHistoryChart(nights: store.nights, plannedWake: wakeMinutes)
                        .padding(.vertical, 4)
                } header: {
                    Text("최근 기상 시각 vs 내일 추천")
                }
                tomorrowSection
                alarmSection
                preferenceSection
                experimentalSection
            }
            .navigationTitle("기상 알람")
            .task(id: calendar.revision) {
                tomorrowItems = calendar.items(on: tomorrow, fixedKeywords: ctx.profile.fixedKeywords)
            }
        }
    }

    private var planSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("취침 목표").font(.caption).foregroundStyle(.secondary)
                        Text(Clock.hhmm(wakeMinutes - ctx.profile.goalSleepMinutes - 15))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.bottom, 8)
                    VStack(alignment: .leading) {
                        Text("WAKE UP").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        Text(Clock.hhmm(wakeMinutes))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                    }
                }
                TomorrowPlanChart(bedMinutes: wakeMinutes - ctx.profile.goalSleepMinutes - 15,
                                  wakeMinutes: wakeMinutes,
                                  prep: ctx.profile.prepMinutes,
                                  commute: ctx.profile.commuteMinutes,
                                  firstEvent: plan.firstEvent)
                Text(customWake == nil ? plan.reason : "직접 정한 시각 (사용자 알람이 항상 우선)")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("목표 수면 \(Clock.durationText(ctx.profile.goalSleepMinutes)) + 잠드는 시간 15분 기준")
                    .font(.caption2).foregroundStyle(.secondary)

                DatePicker("직접 조정", selection: Binding(
                    get: { customWake ?? Clock.date(fromMinutes: plan.wakeMinutes, on: tomorrow) },
                    set: { customWake = $0 }), displayedComponents: .hourAndMinute)
                if customWake != nil {
                    Button("추천 시각으로 되돌리기") { customWake = nil }.font(.footnote)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("내일 추천 (\(Fmt.day.string(from: tomorrow)))")
        }
    }

    private var tomorrowSection: some View {
        Section {
            if !calendar.canShowItems {
                Button {
                    Task { await calendar.requestAccess() }
                } label: {
                    Label("캘린더 연결해서 첫 일정 반영하기", systemImage: "calendar.badge.plus")
                }
            } else if tomorrowItems.isEmpty {
                Text("내일 일정이 없어요.").foregroundStyle(.secondary)
            } else {
                ForEach(tomorrowItems) { it in
                    HStack {
                        Text(it.isAllDay ? "종일" : Fmt.time.string(from: it.start))
                            .font(.callout.monospacedDigit()).frame(width: 80, alignment: .leading)
                        Text(it.title)
                        Spacer()
                        if it.id == plan.firstEvent?.id {
                            Text("기준").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                        }
                    }
                }
            }
            HStack {
                Text("준비 \(ctx.profile.prepMinutes)분 · 이동 \(ctx.profile.commuteMinutes)분")
                Spacer()
                Text("설정에서 변경").font(.caption).foregroundStyle(.secondary)
            }
            .font(.footnote)
        } header: {
            Text("내일 일정")
        }
    }

    private var alarmSection: some View {
        Section {
            Button {
                setClockAlarm()
            } label: {
                Label("시계 앱에 \(Clock.hhmm(wakeMinutes)) 알람 만들기", systemImage: "alarm.fill")
                    .font(.body.weight(.semibold))
            }
            Text("단축어 ‘SleepMate 알람’이 아이폰 기본 시계 앱에 알람을 만들어요. 무음 모드에서도 울리고, 인터넷이 없어도 동작해요.")
                .font(.footnote).foregroundStyle(.secondary)

            Button {
                Task {
                    var ok = await NotificationService.shared.isAuthorized()
                    if !ok { ok = await NotificationService.shared.requestAuthorization() }
                    guard ok else { message = "알림 권한이 필요해요."; return }
                    let date = Clock.date(fromMinutes: wakeMinutes, on: tomorrow)
                    NotificationService.shared.scheduleOnce(id: "alarm-backup", at: date,
                                                            title: "좋은 아침이에요 ☀️",
                                                            body: "SleepMate를 열면 지난밤 요약을 읽어 드려요.")
                    backupScheduled = true
                    AgentLog.shared.add(.planAlarm, path: .rule, action: "백업 알림 \(Clock.hhmm(wakeMinutes))",
                                        guardNote: "네트워크 불필요")
                }
            } label: {
                Label(backupScheduled ? "백업 알림 등록됨" : "백업 알림도 등록 (선택)", systemImage: "bell")
            }
            Text("백업 알림은 무음 모드에서는 소리가 나지 않아요. 진짜 알람은 위 버튼(시계 앱)을 쓰세요.")
                .font(.caption2).foregroundStyle(.secondary)
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
        } header: {
            Text("알람 설정")
        }
    }

    private var preferenceSection: some View {
        Section {
            Picker("알람 방식", selection: Binding(
                get: { ctx.profile.alarmStyle },
                set: { ctx.profile.alarmStyle = $0; ctx.save() })) {
                ForEach(AlarmStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Text("알람음")
                Spacer()
                Text(ctx.profile.alarmSoundName).foregroundStyle(.secondary)
            }
            Text("알람음·진동은 시계 앱에 만들어진 알람에서 바꿀 수 있어요. 여기 저장한 선호는 다음 추천에 참고합니다.")
                .font(.caption2).foregroundStyle(.secondary)
        } header: {
            Text("선호 설정")
        }
    }

    private var experimentalSection: some View {
        Section {
            Toggle("수면 단계 기반 최적 기상 (실험)", isOn: .constant(false))
                .disabled(true)
            Text("얕은 잠일 때 깨우는 기능은 측정 오차가 있어 MVP에서는 꺼 두었어요. 사용자가 정한 알람이 항상 우선합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("선택 기능")
        }
    }

    private func setClockAlarm() {
        let action = AgentAction(kind: .alarm, title: Clock.hhmm(wakeMinutes), requiresApproval: false)
        let g = AgentGuard.check(action, profile: ctx.profile)
        AgentLog.shared.add(.planAlarm, path: .rule, action: "시계 알람 \(Clock.hhmm(wakeMinutes)) 요청",
                            guardNote: g.note)
        var c = URLComponents()
        c.scheme = "shortcuts"
        c.host = "run-shortcut"
        c.queryItems = [
            URLQueryItem(name: "name", value: "SleepMate 알람"),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: Clock.hhmm(wakeMinutes)),
        ]
        if let u = c.url { openURL(u) }
        ctx.record(scenario: "04", key: "alarm", title: "알람 \(Clock.hhmm(wakeMinutes))",
                   response: customWake == nil ? .accepted : .rejected)
    }
}
