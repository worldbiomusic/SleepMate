import Foundation
import Observation

// 계획서 "작은 판단은 빠르게, 복합 판단은 깊게"
//   EVENT → REASON(규칙 / 경량 AI / LLM) → GUARD(권한·정책 검증) → ACT(허용된 실행)
// MVP에서는 REASON 대부분이 규칙이고, LLM은 수면 요약(시나리오 05)에서 사용.
// 경량 AI 자리는 비워 두고 경로만 표시한다 (나중에 Core ML 등으로 교체).

enum ReasonPath: String, Codable {
    case rule = "규칙"
    case light = "경량 AI"
    case llm = "LLM"
}

enum AgentEventKind: String, Codable {
    case sleepImported = "수면 기록 도착"
    case morning = "아침 브리핑"
    case planToday = "오늘 일정 분석"
    case windDown = "취침 준비 시간"
    case screenGoal = "화면 목표 접근"
    case planAlarm = "기상 알람 계획"
    case feedback = "피드백"
}

struct AgentAction: Identifiable, Equatable {
    enum Kind: String { case suggest = "추천", notify = "알림", calendarChange = "일정 변경", alarm = "알람" }
    let id = UUID()
    let kind: Kind
    let title: String
    var requiresApproval: Bool
    var touchesFixedEvent = false
}

/// GUARD: 실행 전에 정책을 확인한다.
enum AgentGuard {
    struct Result {
        let allowed: Bool
        let note: String?
    }

    static func check(_ a: AgentAction, profile: UserProfile, eveningNotificationsSent: Int = 0) -> Result {
        switch a.kind {
        case .calendarChange:
            if a.touchesFixedEvent {
                return Result(allowed: false, note: "수업·회의·약속 같은 고정 일정은 바꾸지 않음")
            }
            if !a.requiresApproval {
                return Result(allowed: false, note: "일정 변경은 반드시 사용자 승인 필요")
            }
            return Result(allowed: true, note: "사용자 승인 후 적용")
        case .notify:
            if !profile.notifyWindDown {
                return Result(allowed: false, note: "사용자가 취침 준비 알림을 꺼 둠")
            }
            if eveningNotificationsSent >= profile.maxEveningNotifications {
                return Result(allowed: false, note: "저녁 알림 최대 \(profile.maxEveningNotifications)회 초과")
            }
            return Result(allowed: true, note: nil)
        case .alarm:
            return Result(allowed: true, note: "사용자가 정한 알람이 우선, 네트워크 없이 동작")
        case .suggest:
            return Result(allowed: true, note: nil)
        }
    }
}

/// 에이전트가 무엇을 판단했는지 남기는 기록 (발표·디버깅용, 설정 탭에서 확인)
@MainActor
@Observable
final class AgentLog {
    static let shared = AgentLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let event: String
        let path: ReasonPath
        let action: String
        let guardNote: String?
    }

    private(set) var entries: [Entry] = []

    func add(event: String, path: ReasonPath, action: String, guardNote: String?) {
        entries.insert(Entry(event: event, path: path, action: action, guardNote: guardNote), at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
    }

    func add(_ kind: AgentEventKind, path: ReasonPath, action: String, guardNote: String? = nil) {
        add(event: kind.rawValue, path: path, action: action, guardNote: guardNote)
    }
}

// MARK: - 수면 점수 (0~100)

enum SleepScore {
    struct Breakdown {
        let total: Int
        let duration: Int      // /50
        let efficiency: Int    // /20
        let stages: Int        // /15
        let regularity: Int    // /15

        var label: String {
            switch total {
            case 85...: return "좋음"
            case 70..<85: return "보통"
            default: return "부족"
            }
        }
    }

    static func compute(_ s: SleepStats, goalMinutes: Int) -> Breakdown {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

        // 1) 수면 시간: 목표 대비 (목표보다 2시간 이상 많으면 살짝 감점)
        var d = clamp(Double(s.asleepMin) / Double(max(goalMinutes, 1)))
        if s.asleepMin > goalMinutes + 120 { d -= 0.1 }
        let duration = Int((50 * clamp(d)).rounded())

        // 2) 효율: 잠든 시간 / (잠든 시간 + 깬 시간)
        let eff = Double(s.asleepMin) / Double(max(s.asleepMin + s.awakeMin, 1))
        let efficiency = Int((20 * clamp((eff - 0.75) / 0.2)).rounded())

        // 3) 단계 구성: 깊은 13~23%, REM 18~25%를 기준으로 (단계 데이터 없으면 중간값)
        let stages: Int
        if s.hasStages {
            func band(_ v: Int, _ lo: Int, _ hi: Int) -> Double {
                if v >= lo && v <= hi { return 1 }
                let gap = v < lo ? lo - v : v - hi
                return clamp(1 - Double(gap) / 10)
            }
            stages = Int((15 * (band(s.deepPct, 13, 23) + band(s.remPct, 18, 25)) / 2).rounded())
        } else {
            stages = 9
        }

        // 4) 규칙성: 취침 시각 표준편차 (0분=만점, 90분 이상=0)
        let regularity: Int
        if let spread = s.bedtimeSpreadMin {
            regularity = Int((15 * clamp(1 - Double(spread) / 90)).rounded())
        } else {
            regularity = 10
        }

        let total = min(100, duration + efficiency + stages + regularity)
        return Breakdown(total: total, duration: duration, efficiency: efficiency,
                         stages: stages, regularity: regularity)
    }
}
