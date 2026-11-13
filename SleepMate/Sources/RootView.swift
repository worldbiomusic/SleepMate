import SwiftUI

enum AppTab: String {
    case home, today, winddown, alarm, settings
}

/// 앱의 최상위 화면: 시나리오별 탭
///  홈(05 수면 요약·대시보드) · 오늘(01 행동·일정 추천) · 취침 준비(02) · 알람(04) · 설정(Context)
struct ContentView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
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
            SettingsView()
                .tabItem { Label("설정", systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))   // 차트 축(시각·요일)을 한국어로
        .task {
            guard DemoMode.isOn else { return }
            ctx.seedDemo()
            // CI 스크린샷: 홈이 아닌 탭으로 바로 열 때도 데모 데이터 준비
            if UserDefaults.standard.string(forKey: "demoTab") != nil, !store.isDemo {
                store.loadDemo()
            }
        }
    }
}
