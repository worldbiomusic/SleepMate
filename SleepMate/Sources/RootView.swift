import SwiftUI

enum AppTab: String {
    case home, today, winddown, alarm, guide
}

/// 설정은 탭 대신 홈 오른쪽 위 톱니바퀴에서 연다 (iPhone 탭은 5개까지가 한 번에 보임)
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showSettings = UserDefaults.standard.string(forKey: "demoTab") == "settings"
}

/// 앱의 최상위 화면: 시나리오별 탭
///  홈(05 수면 요약·대시보드) · 오늘(01 행동·일정 추천) · 취침 준비(02) · 알람(04) · 소개(프로젝트 설명)
///  설정(Context)은 홈 오른쪽 위 톱니바퀴
struct ContentView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @State private var router = AppRouter.shared
    @State private var tour = DemoTour.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = {
        if let t = UserDefaults.standard.string(forKey: "demoTab"), let v = AppTab(rawValue: t) { return v }
        return .home
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openToday: { tab = .today })
                .tabItem { Label("홈", systemImage: "moon.stars.fill") }
                .tag(AppTab.home)
            TodayView()
                .tabItem { Label("오늘", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            WindDownView()
                .tabItem { Label("취침 준비", systemImage: "bed.double.fill") }
                .tag(AppTab.winddown)
            AlarmView()
                .tabItem { Label("알람", systemImage: "alarm.fill") }
                .tag(AppTab.alarm)
            GuideView()
                .tabItem { Label("소개", systemImage: "book.pages.fill") }
                .tag(AppTab.guide)
        }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .sheet(isPresented: $tour.showMemory) {
            NavigationStack { MemoryView() }
                .overlay(alignment: .bottom) { if let c = tour.caption { TourCaption(text: c, bottom: 40) } }
        }
        .overlay(alignment: .bottom) {
            if let c = tour.caption { TourCaption(text: c) }
        }
        .overlay {
            if tour.marker { Color(red: 1, green: 0, blue: 1).ignoresSafeArea() }
        }
        .onChange(of: tour.tab) { _, t in tab = t }
        .safeAreaInset(edge: .top, spacing: 0) { TestModeBanner() }
        .environment(\.locale, Locale(identifier: "ko_KR"))   // 차트 축(시각·요일)을 한국어로
        // SleepMate가 앞으로 나오면: 다른 앱 사용은 끝난 것 + 기억 통합(하루 첫 실행 · 새 수면 기록)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !TestLab.shared.isOn, !DemoMode.isOn else { return }
            Task {
                await UsageStore.shared.closeAll()
                MemoryStore.shared.consolidate(nights: store.nights, ctx: ctx)
                WatchBridge.shared.push()
            }
        }
        .onChange(of: store.lastLoadedAt) { _, _ in
            guard !TestLab.shared.isOn, !DemoMode.isOn else { return }
            MemoryStore.shared.consolidate(nights: store.nights, ctx: ctx)
        }
        .task {
            WatchBridge.shared.start(store: store, ctx: ctx, calendar: calendar)
            if DemoTour.shared.isOn {
                await DemoTour.shared.run(store: store, ctx: ctx, calendar: calendar)
                return
            }
            SelfTestCLI.runIfRequested()
            await LiveAPITests.runIfRequested()
            // CI: -testSleep short -testToday morningFocus -testTomorrow early -testClock evening
            let d = UserDefaults.standard
            if let name = d.string(forKey: "testSleep"),
               let p = SleepPreset.allCases.first(where: { "\($0)" == name }) {
                let lab = TestLab.shared
                lab.sleep = p
                if let n = d.string(forKey: "testToday"), let v = DayPreset.allCases.first(where: { "\($0)" == n }) { lab.today = v }
                if let n = d.string(forKey: "testTomorrow"), let v = DayPreset.allCases.first(where: { "\($0)" == n }) { lab.tomorrow = v }
                if let n = d.string(forKey: "testClock"), let v = TestLab.ClockMode.allCases.first(where: { "\($0)" == n }) { lab.clock = v }
                lab.apply(store: store, ctx: ctx, calendar: calendar)
                return
            }
            guard DemoMode.isOn else { return }
            ctx.seedDemo()
            // CI 스크린샷: 홈이 아닌 탭으로 바로 열 때도 데모 데이터 준비
            if UserDefaults.standard.string(forKey: "demoTab") != nil, !store.isDemo {
                store.loadDemo()
            }
        }
    }
}
