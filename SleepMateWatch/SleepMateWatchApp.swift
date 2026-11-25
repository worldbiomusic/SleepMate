import SwiftUI

@main
struct SleepMateWatchApp: App {
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "ko_KR"))
        }
    }
}
