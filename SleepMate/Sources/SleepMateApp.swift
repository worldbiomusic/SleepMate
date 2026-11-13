import SwiftUI

@main
struct SleepMateApp: App {
    @State private var store = SleepStore()
    @State private var coach = CoachStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(coach)
                .onOpenURL { url in store.handle(url: url) }
        }
    }
}
