import SwiftUI

@main
struct SleepMateApp: App {
    @State private var store = SleepStore()
    @State private var coach = CoachStore()
    @State private var context = ContextStore()
    @State private var calendar = CalendarService()

    init() {
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(coach)
                .environment(context)
                .environment(calendar)
                .onOpenURL { url in store.handle(url: url) }
        }
    }
}
