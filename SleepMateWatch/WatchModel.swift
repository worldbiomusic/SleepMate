import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// 워치 쪽: 아이폰이 보낸 요약을 받아 보여 주고, 버튼 입력을 아이폰으로 보낸다
@MainActor
@Observable
final class WatchModel: NSObject {
    static let shared = WatchModel()

    var payload: WatchPayload?
    var reachable = false
    var sent: String?                       // 방금 보낸 명령 안내

    /// 스크린샷·시뮬레이터용 예시 (-demoData YES)
    var isDemo: Bool { UserDefaults.standard.bool(forKey: "demoData") }

    override init() {
        super.init()
        if isDemo { payload = .sample; return }
        if let d = UserDefaults.standard.data(forKey: "lastPayload"),
           let p = try? JSONDecoder().decode(WatchPayload.self, from: d) { payload = p }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func receive(_ p: WatchPayload) {
        payload = p
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "lastPayload") }
    }

    func send(_ cmd: WatchCommand, value: String? = nil) {
        var msg: [String: Any] = [WatchCommand.key: cmd.rawValue]
        if let value { msg[WatchCommand.valueKey] = value }
        WKInterfaceDevice.current().play(.click)
        // 화면에 바로 반영 (아이폰이 확인하면 최신 요약으로 덮어씀)
        switch cmd {
        case .stop: payload?.stopped = true; sent = "아이폰에 기록했어요"
        case .add5: payload?.eveningAppMinutes += 5; sent = "+5분 기록"
        case .mood: payload?.mood = value; sent = "기분을 보냈어요"
        case .refresh: sent = nil
        }
        guard !isDemo, WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { reply in
                let box = ReplyBox(reply)
                Task { @MainActor in
                    if let p = WatchPayload.decode(box.value) { WatchModel.shared.receive(p) }
                }
            }, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)        // 아이폰이 깨어나면 전달됨
        }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let box = ReplyBox(session.receivedApplicationContext)
        let r = session.isReachable
        Task { @MainActor in
            WatchModel.shared.reachable = r
            if let p = WatchPayload.decode(box.value) { WatchModel.shared.receive(p) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let box = ReplyBox(applicationContext)
        Task { @MainActor in
            if let p = WatchPayload.decode(box.value) { WatchModel.shared.receive(p) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in WatchModel.shared.reachable = r }
    }
}

private struct ReplyBox: @unchecked Sendable {
    let value: [String: Any]
    init(_ v: [String: Any]) { value = v }
}
