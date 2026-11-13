import SwiftUI

@main
struct SleepMateApp: App {
    @State private var store = SleepStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onOpenURL { url in store.handle(url: url) }
        }
    }
}
