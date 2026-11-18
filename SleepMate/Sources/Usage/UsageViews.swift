import Charts
import SwiftUI

/// 취침 준비 탭: 오늘 밤 앱 사용시간 (쇼츠 개수 대신 '분')
struct TonightUsageSection: View {
    @Environment(ContextStore.self) private var ctx
    @State private var usage = UsageStore.shared
    @State private var showSetup = false

    var body: some View {
        let now = AppClock.now
        let evening = usage.eveningMinutes(now: now, profile: ctx.profile)
        let limit = usage.settings.eveningLimitMinutes
        Section {
            HStack(spacing: 18) {
                ScreenGauge(count: evening, goal: limit, unit: "분").padding(.leading, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message(evening: evening, limit: limit)).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let open = usage.openSession {
                        Label("지금 \(UsageMath.displayName(open.app)) 사용 중 · \(UsageMath.minutes([open], from: .distantPast, to: .distantFuture, now: now))분",
                              systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 6)

            // 앱별 오늘 사용 vs 하루 한도
            ForEach(usage.settings.limits.filter(\.enabled)) { l in
                let used = usage.todayMinutes(l.app, now: now)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(UsageMath.displayName(l.app)).font(.subheadline)
                        Spacer()
                        Text("\(used) / \(l.dailyMinutes)분").font(.caption.monospacedDigit())
                            .foregroundStyle(used >= l.dailyMinutes ? .red : .secondary)
                    }
                    GeometryReader { g in
                        let r = min(1.0, Double(used) / Double(max(l.dailyMinutes, 1)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                            Capsule().fill(r >= 1 ? Color.red : (r >= 0.8 ? .orange : .teal)).frame(width: g.size.width * r)
                        }
                    }
                    .frame(height: 7)
                }
            }

            HStack {
                Button("+5분") { usage.addManual(minutes: 5) }.buttonStyle(.bordered)
                Button("+10분") { usage.addManual(minutes: 10) }.buttonStyle(.bordered)
                Spacer()
                Button("오늘은 여기까지") {
                    ctx.stopScreen()
                    ctx.record(scenario: "02", key: "screen-stop", title: "화면 그만 보기", response: .accepted)
                    MemoryStore.shared.markLatestAccepted(kinds: [.windDown, .appLimit, .bedtimeNotice], now: Date())
                }
                .buttonStyle(.borderedProminent)
                .disabled(ctx.today.stoppedScreen)
            }
            Button {
                showSetup = true
            } label: {
                Label(usage.lastEvent == nil ? "자동 기록 설정하기 (단축어)" : "자동 기록 · 한도 설정",
                      systemImage: usage.lastEvent == nil ? "exclamationmark.circle" : "gearshape")
            }
            .font(.callout)
        } header: {
            Text("오늘 밤 앱 사용시간")
        } footer: {
            Text(usage.lastEvent.map { "마지막 자동 기록 \(Fmt.time.string(from: $0)) · 한도를 넘는 순간 알림이 와요." }
                 ?? "단축어 자동화를 설정하면 유튜브 등을 열고 닫을 때 자동으로 시간을 재고, 한도를 넘는 순간 알림을 보내요. 설정 전에는 +5분 버튼으로 기록할 수 있어요.")
        }
        .sheet(isPresented: $showSetup) { NavigationStack { UsageSetupView() } }
    }

    private func message(evening: Int, limit: Int) -> String {
        if ctx.today.stoppedScreen { return "오늘은 여기까지 하기로 했어요. 잘 하셨어요 👏" }
        if evening == 0 { return "취침 준비 시간 동안 아직 감시 앱을 쓰지 않았어요." }
        let left = limit - evening
        if left > 5 { return "오늘 밤 한도까지 \(left)분 남았어요." }
        if left > 0 { return "한도까지 \(left)분 남았어요. 슬슬 마무리해 볼까요?" }
        return "오늘 밤 한도보다 \(-left)분 더 썼어요. 지금 멈추면 내일 아침이 가벼워져요."
    }
}

/// 단축어 자동화 안내 + 한도 설정
struct UsageSetupView: View {
    @State private var usage = UsageStore.shared
    @State private var newApp = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                step(1, "단축어 앱 → 자동화 → + → ‘앱’", "앱 선택에서 YouTube를 고르고 ‘열릴 때’만 체크 → ‘즉시 실행’ 선택")
                step(2, "동작 추가 → ‘SleepMate’ 검색 → ‘앱 사용 시작 기록’", "앱 이름에 YouTube 입력 (한도 목록의 이름과 같게)")
                step(3, "같은 방법으로 ‘닫힐 때’ 자동화 하나 더", "동작은 ‘앱 사용 종료 기록’, 앱 이름 YouTube")
                step(4, "다른 앱도 반복", "인스타그램, 틱톡 등. 아래 한도 목록에 있는 앱만 알림이 와요")
            } header: {
                Text("자동 기록 설정 (앱마다 2개)")
            } footer: {
                Text("SleepMate 화면은 열리지 않고 뒤에서 기록만 해요. 유료 개발자 계정 없이 앱 사용시간을 재는 방법이에요. 잠금 등으로 ‘닫힘’을 놓치면 한 번에 최대 3시간까지만 셉니다.")
            }

            Section {
                ForEach($usage.settings.limits) { $l in
                    HStack {
                        Toggle(isOn: $l.enabled) { Text(UsageMath.displayName(l.app)) }
                        Stepper("\(l.dailyMinutes)분", value: $l.dailyMinutes, in: 10...300, step: 10)
                            .fixedSize()
                    }
                }
                .onDelete { usage.settings.limits.remove(atOffsets: $0); usage.save() }
                HStack {
                    TextField("앱 이름 추가 (예: Netflix)", text: $newApp)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("추가") {
                        let n = newApp.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        usage.settings.limits.append(AppLimit(app: n, dailyMinutes: 30))
                        newApp = ""
                        usage.save()
                    }
                }
            } header: {
                Text("앱별 하루 한도")
            }

            Section {
                Stepper("취침 준비 시간 합계 \(usage.settings.eveningLimitMinutes)분",
                        value: $usage.settings.eveningLimitMinutes, in: 0...120, step: 5)
                Stepper("초과 뒤 \(usage.settings.repeatMinutes)분마다 다시 알림",
                        value: $usage.settings.repeatMinutes, in: 5...30, step: 5)
                Toggle("한도 알림 켜기", isOn: $usage.settings.enabled)
            } header: {
                Text("잠들기 전 한도")
            } footer: {
                Text("하루 한도와 취침 전 한도 중 먼저 닿는 쪽에서 알림이 와요. 알림 후 5분 안에 앱을 닫으면 ‘받아들임’으로 기억해서 다음 알림 말투에 반영해요.")
            }

            Section {
                let recent = usage.sessions.suffix(8).reversed()
                if recent.isEmpty { Text("아직 기록이 없어요").foregroundStyle(.secondary) }
                ForEach(Array(recent)) { s in
                    HStack {
                        Text(UsageMath.displayName(s.app))
                        Spacer()
                        Text("\(Fmt.time.string(from: s.start)) – \(s.end.map { Fmt.time.string(from: $0) } ?? "사용 중")")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("최근 기록")
            }
        }
        .navigationTitle("앱 사용시간")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { usage.save(); dismiss() } } }
        .onChange(of: usage.settings) { _, _ in usage.save() }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
