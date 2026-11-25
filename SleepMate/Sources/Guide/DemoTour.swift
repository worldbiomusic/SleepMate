import SwiftUI

/// 소개 영상용 자동 시연 (-demoTour YES). CI가 시뮬레이터 화면을 녹화한다.
/// 테스트 모드(4주 시뮬레이션) 위에서 아침 → 낮 → 밤 순서로 화면을 넘기며 자막을 띄운다.
@MainActor
@Observable
final class DemoTour {
    static let shared = DemoTour()

    struct Step {
        var tab: AppTab
        var clock: TestLab.ClockMode
        var caption: String
        var seconds: Double
        var memory = false
    }

    var isOn: Bool { UserDefaults.standard.bool(forKey: "demoTour") }
    var tab: AppTab = .home
    var caption: String?
    var showMemory = false
    var marker = false            // 녹화에서 시작·끝을 찾기 위한 전체 화면 표시 색
    var stepStart = Date()
    var stepSeconds = 4.0

    let steps: [Step] = [
        Step(tab: .home, clock: .morning, caption: "아침 7:30 · 어젯밤 수면을 점수와 요약으로 보여 줘요", seconds: 4.5),
        Step(tab: .today, clock: .morning, caption: "오늘 · 수면으로 추정한 컨디션과 일정, 쉬는 시간 제안", seconds: 4.5),
        Step(tab: .alarm, clock: .morning, caption: "알람 · 내일 첫 일정에서 거꾸로 계산한 기상 시각", seconds: 4.0),
        Step(tab: .winddown, clock: .evening, caption: "밤 10:40 · 취침까지 남은 시간과 오늘 밤 앱 사용시간", seconds: 4.5),
        Step(tab: .winddown, clock: .evening, caption: "기억을 바탕으로 한 한마디 · 늦게 자는 요일엔 미리, 잘 통한 말투로", seconds: 4.5),
        Step(tab: .winddown, clock: .evening, caption: "나에 대한 기억 · 4주 기록에서 배운 습관과 개입 결과", seconds: 5.0, memory: true),
        Step(tab: .guide, clock: .evening, caption: "소개 · 구조와 동작 방식을 한눈에", seconds: 3.5),
    ]

    private func log(_ s: String) { FileHandle.standardError.write(Data("[Tour] \(s)\n".utf8)) }

    func run(store: SleepStore, ctx: ContextStore, calendar: CalendarService) async {
        guard isOn else { return }
        let lab = TestLab.shared
        lab.sleep = .short
        lab.today = .morningFocus
        lab.tomorrow = .early
        lab.clock = .morning
        lab.apply(store: store, ctx: ctx, calendar: calendar)
        try? await Task.sleep(for: .seconds(1.0))
        // 모든 탭을 한 번씩 미리 그려 둔다 (CI 시뮬레이터는 첫 렌더가 느려 자막과 화면이 어긋남)
        for t in [AppTab.today, .alarm, .winddown, .guide, .home] {
            tab = t
            try? await Task.sleep(for: .seconds(1.5))
        }
        marker = true
        try? await Task.sleep(for: .seconds(1.2))
        marker = false
        log("start \(Date().timeIntervalSince1970)")
        for s in steps {
            if lab.clock != s.clock {
                caption = nil
                lab.clock = s.clock
                lab.apply(store: store, ctx: ctx, calendar: calendar)
                try? await Task.sleep(for: .seconds(1.0))
            }
            if tab != s.tab || showMemory != s.memory {
                tab = s.tab
                showMemory = s.memory
                try? await Task.sleep(for: .seconds(0.6))     // 화면이 먼저 바뀌고
            }
            stepStart = Date()
            stepSeconds = s.seconds
            withAnimation(.easeInOut(duration: 0.3)) { caption = s.caption }   // 그다음 자막
            try? await Task.sleep(for: .seconds(s.seconds))
        }
        showMemory = false
        caption = nil
        try? await Task.sleep(for: .seconds(0.6))
        marker = true
        try? await Task.sleep(for: .seconds(1.2))
        log("end \(Date().timeIntervalSince1970)")
    }
}

/// 화면 아래 자막 + 장면 진행 막대
/// (막대가 매 프레임 움직여야 시뮬레이터 녹화가 정지 화면을 건너뛰지 않는다)
struct TourCaption: View {
    let text: String
    var bottom: CGFloat = 96
    @State private var tour = DemoTour.shared

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            TimelineView(.animation) { tl in
                let p = min(1, max(0, tl.date.timeIntervalSince(tour.stepStart) / max(tour.stepSeconds, 0.1)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: g.size.width * p)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.78)))
        .padding(.horizontal, 20)
        .padding(.bottom, bottom)
        .transition(.opacity)
        .id(text)
    }
}
