import Foundation
import UserNotifications

/// 로컬 알림 (무료 계정 사이드로딩에서도 동작 — 푸시 서버 불필요)
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    static let windDownCategory = "WINDDOWN"
    static let screenCheckCategory = "SCREENCHECK"
    static let actionAdd5 = "ADD5"
    static let actionAdd10 = "ADD10"
    static let actionStop = "STOP"

    private let center = UNUserNotificationCenter.current()

    /// 앱 시작 시 한 번 호출
    func configure() {
        center.delegate = self
        let add5 = UNNotificationAction(identifier: Self.actionAdd5, title: "+5 기록", options: [])
        let add10 = UNNotificationAction(identifier: Self.actionAdd10, title: "+10 기록", options: [])
        let stop = UNNotificationAction(identifier: Self.actionStop, title: "오늘은 여기까지", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.screenCheckCategory, actions: [add5, add10, stop],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.windDownCategory, actions: [stop],
                                   intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// 매일 반복 알림 (자정 기준 분)
    func scheduleDaily(id: String, minutes: Int, title: String, body: String, category: String? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let category { c.categoryIdentifier = category }
        var dc = DateComponents()
        let m = ((minutes % 1440) + 1440) % 1440
        dc.hour = m / 60
        dc.minute = m % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    /// 한 번만 울리는 알림
    func scheduleOnce(id: String, at date: Date, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    func cancel(prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pendingIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).sorted()
    }

    // MARK: Delegate

    /// 앱이 켜져 있어도 배너 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// 알림의 버튼(+5, +10, 오늘은 여기까지) 처리 — 앱이 꺼져 있어도 UserDefaults에 기록
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let key = ContextStore.screenKey(for: Calendar.current.startOfDay(for: Date()))
        let d = UserDefaults.standard
        switch response.actionIdentifier {
        case Self.actionAdd5: d.set(d.integer(forKey: key) + 5, forKey: key)
        case Self.actionAdd10: d.set(d.integer(forKey: key) + 10, forKey: key)
        case Self.actionStop: d.set(true, forKey: key + "-stopped")
        default: break
        }
    }
}
