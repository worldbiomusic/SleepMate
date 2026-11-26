import SwiftUI

/// 탭 3개: 지금 · 기록 · 설정
enum AppTab: String {
    case now, records, settings

    /// CI 스크린샷 인자(-demoTab)를 새 구조로: 예전 탭 이름은 '지금' 위의 자세히 시트로 연다
    static func fromDemo(_ s: String?) -> (AppTab, NowDetail?)? {
        switch s {
        case "now": return (.now, nil)
        case "home", "records": return (.records, nil)
        case "settings": return (.settings, nil)
        case "today": return (.now, .today)
        case "winddown": return (.now, .winddown)
        case "alarm": return (.now, .alarm)
        case "guide": return (.settings, .guide)
        default: return nil
        }
    }
}

/// 어느 탭에서든 여는 자세한 화면(시트)
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var detail: NowDetail? = AppTab.fromDemo(UserDefaults.standard.string(forKey: "demoTab"))?.1
    var lastNudge: WindDownDecision?      // '왜 이런 제안?'에서 보여 줄 최근 밤 판단
}

/// 앱의 최상위 화면
///  지금(시간대별 카드 하나) · 기록(05 수면 요약·리포트·기억) · 설정(목표·연결·소개·테스트)
///  예전 오늘(01)·취침 준비(02)·알람(04) 화면은 '지금'의 '자세히'에서 시트로 연다
struct ContentView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @Environment(CoachStore.self) private var coach
    @State private var router = AppRouter.shared
    @State private var tour = DemoTour.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = {
        let d = UserDefaults.standard
        if let t = AppTab.fromDemo(d.string(forKey: "demoTab")) { return t.0 }
        // -demoScreen 화면들은 기록 탭(예전 홈)에서 연다 (first = 처음 실행 화면은 '지금')
        if let sc = DemoMode.screen, sc != "first" { return .records }
        return .now
    }()

    var body: some View {
        TabView(selection: $tab) {
            NowView()
                .tabItem { Label("지금", systemImage: "sparkles") }
                .tag(AppTab.now)
            HomeView(openToday: { router.detail = .today })
                .tabItem { Label("기록", systemImage: "chart.bar.fill") }
                .tag(AppTab.records)
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .sheet(item: $router.detail) { d in
            NowDetailSheet(detail: d)
                .overlay(alignment: .bottom) { if let c = tour.caption { TourCaption(text: c, bottom: 40) } }
        }
        .sheet(isPresented: $tour.showWhy) {
            WhySheet(nudge: router.lastNudge)
                .overlay(alignment: .bottom) { if let c = tour.caption { TourCaption(text: c, bottom: 40) } }
        }
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
            // 새 기록이 들어오면 아침 요약 갱신 (단축어로 가져온 경우 설정에 따라 Claude 요약·자동 읽기)
            let imported = store.lastChangeWasImport
            let persist = !store.isDemo
            Task { await coach.update(nights: store.nights, fromImport: imported, persist: persist) }
            guard !TestLab.shared.isOn, !DemoMode.isOn else { return }
            MemoryStore.shared.consolidate(nights: store.nights, ctx: ctx)
        }
        .task {
            WatchBridge.shared.start(store: store, ctx: ctx, calendar: calendar)
            await coach.update(nights: store.nights, fromImport: false)
            if DemoTour.shared.isOn {
                await DemoTour.shared.run(store: store, ctx: ctx, calendar: calendar)
                return
            }
            // CI 검증용: `-testImportURL "sleepmate://import?data=..."` 로 실행하면
            // 단축어가 앱을 열 때와 같은 처리 경로(store.handle)를 탄다.
            if let s = UserDefaults.standard.string(forKey: "testImportURL"), let url = URL(string: s) {
                store.handle(url: url)
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
            // CI 스크린샷: 어느 탭으로 열어도 데모 데이터 준비 (first = 처음 실행 화면은 빈 상태)
            if DemoMode.screen != "first", !store.isDemo {
                store.loadDemo()
            }
        }
    }
}
