import SwiftUI

/// 홈 맨 위: 처음 쓰는 사람을 위한 '시작하기' 체크리스트 (모두 끝나면 사라짐, 접기 가능)
struct SetupChecklist: View {
    @Environment(SleepStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    @Environment(CoachStore.self) private var coach
    @State private var notion = NotionStore.shared
    @State private var notifOn = false
    @State private var showGuide = false
    @State private var showCoach = false
    @AppStorage("setupChecklistHidden") private var hidden = false

    private struct Step: Identifiable {
        let id: String
        let title: String
        let sub: String
        let done: Bool
        let optional: Bool
    }

    private var steps: [Step] {
        [Step(id: "sleep", title: "수면 기록 가져오기", sub: "단축어 ‘SleepMate 동기화’", done: store.hasData, optional: false),
         Step(id: "calendar", title: "캘린더 연결", sub: "일정 맞춤 추천·알람", done: calendar.isAuthorized, optional: false),
         Step(id: "notif", title: "알림 허용", sub: "취침 준비 단계 알림", done: notifOn, optional: false),
         Step(id: "notion", title: "노션 할 일 연결", sub: "할 일을 컨디션에 맞게 배치", done: notion.isConfigured, optional: true),
         Step(id: "jev", title: "Jev 연결", sub: "빠른 판단 AI", done: JevClient.isConfigured, optional: true),
         Step(id: "claude", title: "Claude 키", sub: "자세한 아침 요약", done: coach.hasKey, optional: true)]
    }

    var body: some View {
        let list = steps
        let doneCount = list.filter(\.done).count
        if !hidden && doneCount < list.count && !DemoMode.isOn && !DemoTour.shared.isOn {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        Circle().trim(from: 0, to: CGFloat(doneCount) / CGFloat(list.count))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(doneCount)/\(list.count)").font(.caption.bold())
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("시작하기").font(.headline)
                        Text("필수 3개만 하면 대부분의 기능이 동작해요.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { hidden = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(list) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(s.done ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(s.title).font(.subheadline).strikethrough(s.done)
                                if s.optional { Text("선택").font(.system(size: 9)).foregroundStyle(.secondary) }
                            }
                            Text(s.sub).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !s.done { action(for: s.id) }
                    }
                }
            }
            .task { notifOn = await NotificationService.shared.isAuthorized() }
            .sheet(isPresented: $showGuide) { ShortcutGuideView() }
            .sheet(isPresented: $showCoach) { CoachSettingsView() }
        }
    }

    @ViewBuilder
    private func action(for id: String) -> some View {
        switch id {
        case "sleep":
            Button("방법") { showGuide = true }.buttonStyle(.bordered).font(.caption)
        case "calendar":
            Button("연결") { Task { await calendar.requestAccess() } }.buttonStyle(.bordered).font(.caption)
        case "notif":
            Button("허용") {
                Task { notifOn = await NotificationService.shared.requestAuthorization() }
            }
            .buttonStyle(.bordered).font(.caption)
        case "notion":
            NavigationLink("연결") { NotionSettingsView() }.font(.caption)
        case "jev":
            NavigationLink("연결") { JevSettingsView() }.font(.caption)
        default:
            Button("입력") { showCoach = true }.buttonStyle(.bordered).font(.caption)
        }
    }
}
