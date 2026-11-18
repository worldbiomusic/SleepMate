import AppIntents
import Foundation

// 단축어 앱에서 쓰는 동작 (SleepMate 화면을 열지 않고 백그라운드로 실행)
//  자동화 예) "YouTube가 열릴 때 → SleepMate: 앱 사용 시작 기록(앱 이름: YouTube)"
//            "YouTube가 닫힐 때 → SleepMate: 앱 사용 종료 기록(앱 이름: YouTube)"

struct AppOpenedIntent: AppIntent {
    static var title: LocalizedStringResource = "앱 사용 시작 기록"
    static var description = IntentDescription("다른 앱이 열릴 때 SleepMate에 사용 시작을 기록하고, 한도를 넘을 시각에 알림을 예약해요.")
    static var openAppWhenRun = false

    @Parameter(title: "앱 이름", default: "YouTube")
    var appName: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let profile = ContextStore.savedProfile()
        let msg = await UsageStore.shared.appOpened(appName, profile: profile)
        return .result(value: msg)
    }
}

struct AppClosedIntent: AppIntent {
    static var title: LocalizedStringResource = "앱 사용 종료 기록"
    static var description = IntentDescription("다른 앱이 닫힐 때 SleepMate에 사용 종료를 기록해요.")
    static var openAppWhenRun = false

    @Parameter(title: "앱 이름", default: "YouTube")
    var appName: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let msg = await UsageStore.shared.appClosed(appName)
        return .result(value: msg)
    }
}
