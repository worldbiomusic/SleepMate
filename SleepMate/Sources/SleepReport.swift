import Foundation

/// 요약에 쓰는 수치 (Claude에 보내는 것도 이 수치뿐 — 원시 구간은 보내지 않음)
struct SleepStats: Codable, Equatable {
    let day: Date                    // 기상일
    let asleepMin: Int
    let deepMin: Int
    let coreMin: Int
    let remMin: Int
    let unspecifiedMin: Int
    let awakeMin: Int
    let hasStages: Bool
    let bedtime: Date?
    let wakeTime: Date?
    let avg7AsleepMin: Int?          // 최근 7밤(지난밤 포함) 평균
    let nightsIn7: Int
    let avgBedtimeMin: Int?          // 18:00 기준 분 (예: 330 = 23:30)
    let bedtimeSpreadMin: Int?       // 취침 시각 표준편차(분)
    let daysSinceLastNight: Int

    init?(nights: [SleepNight], now: Date = Date(), calendar: Calendar = .current) {
        guard let last = nights.first, last.asleep > 0 else { return nil }
        func m(_ t: TimeInterval?) -> Int { Int(((t ?? 0) / 60).rounded()) }

        day = last.day
        asleepMin = m(last.asleep)
        deepMin = m(last.stageTotals[.deep])
        coreMin = m(last.stageTotals[.core])
        remMin = m(last.stageTotals[.rem])
        unspecifiedMin = m(last.stageTotals[.asleepUnspecified])
        awakeMin = m(last.stageTotals[.awake])
        hasStages = last.hasDetailedStages
        bedtime = last.bedtime
        wakeTime = last.wakeTime

        let window = nights.filter {
            $0.asleep > 0 && $0.day > last.day.addingTimeInterval(-7 * 86400)
        }
        nightsIn7 = window.count
        avg7AsleepMin = window.isEmpty ? nil : window.map { m($0.asleep) }.reduce(0, +) / window.count

        let beds = window.compactMap { $0.bedtime }.map { Self.minutesFrom18($0, calendar) }
        if beds.isEmpty {
            avgBedtimeMin = nil
            bedtimeSpreadMin = nil
        } else {
            let mean = Double(beds.reduce(0, +)) / Double(beds.count)
            avgBedtimeMin = Int(mean.rounded())
            let variance = beds.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(beds.count)
            bedtimeSpreadMin = beds.count >= 3 ? Int(variance.squareRoot().rounded()) : nil
        }
        daysSinceLastNight = calendar.dateComponents([.day],
                                                     from: last.day,
                                                     to: calendar.startOfDay(for: now)).day ?? 0
    }

    static func minutesFrom18(_ d: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return ((c.hour ?? 0) * 60 + (c.minute ?? 0) - 18 * 60 + 1440) % 1440
    }

    static func clock(fromMinutesAfter18 v: Int) -> String {
        let total = (v + 18 * 60) % 1440
        let h = total / 60, mm = total % 60
        let ampm = h < 12 ? "오전" : "오후"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return mm == 0 ? "\(ampm) \(h12)시" : "\(ampm) \(h12)시 \(mm)분"
    }

    var deepPct: Int { asleepMin > 0 ? deepMin * 100 / asleepMin : 0 }
    var remPct: Int { asleepMin > 0 ? remMin * 100 / asleepMin : 0 }
}

enum ReportSource: String, Codable {
    case rules
    case claude
}

struct SleepReport: Codable, Equatable {
    var day: Date
    var source: ReportSource
    var model: String?
    var summary: String
    var recommendations: [String]
    var speech: String
    var createdAt: Date = Date()
}

/// 인터넷·API 키 없이 동작하는 기본 분석
enum RuleReporter {
    static func make(_ s: SleepStats) -> SleepReport {
        let dur = { (min: Int) in Fmt.duration(TimeInterval(min * 60)) }
        var summary: [String] = []

        // 1) 총 수면
        var first = "\(Fmt.day.string(from: s.day)) 기록으로 \(dur(s.asleepMin)) 주무셨어요"
        if let avg = s.avg7AsleepMin, s.nightsIn7 >= 3 {
            let diff = s.asleepMin - avg
            if abs(diff) >= 20 {
                first += ". 최근 \(s.nightsIn7)일 평균(\(dur(avg)))보다 \(dur(abs(diff))) \(diff > 0 ? "많아요" : "적어요")"
            } else {
                first += ". 최근 평균(\(dur(avg)))과 비슷해요"
            }
        }
        summary.append(first + ".")

        // 2) 단계
        if s.hasStages {
            var stage = "깊은 수면 \(dur(s.deepMin))(\(s.deepPct)%), REM \(dur(s.remMin))(\(s.remPct)%)"
            if s.deepPct < 10 {
                stage += "로 깊은 수면이 적은 편이에요"
            } else if s.remPct < 15 {
                stage += "로 REM 수면이 적은 편이에요"
            } else {
                stage += "로 단계 구성은 무난해요"
            }
            summary.append(stage + ".")
        }
        if s.awakeMin >= 30 {
            summary.append("중간에 깨어 있던 시간이 \(dur(s.awakeMin))로 길었어요.")
        }

        // 3) 규칙성
        if let spread = s.bedtimeSpreadMin, let avgBed = s.avgBedtimeMin {
            if spread >= 60 {
                summary.append("최근 잠드는 시각이 들쭉날쭉해요(평균 \(RuleReporter.clockShort(avgBed)), 편차 약 \(spread)분).")
            }
        }

        // 추천: ① 수면 시간 대응(핵심 2개) → ② 그날 문제에 맞춘 것 → ③ 남는 자리에 보조 추천
        //  (4개 제한에서 '자주 깸'·'불규칙' 같은 구체적 조언이 잘리지 않도록 순서를 정함)
        let irregular = (s.bedtimeSpreadMin ?? 0) >= 60 && s.avgBedtimeMin != nil
        var core: [String] = []
        var extra: [String] = []
        if s.asleepMin < 6 * 60 {
            core.append("오후 2시 이후에는 커피·에너지음료를 피하세요.")
            if let avgBed = s.avgBedtimeMin {
                core.append("오늘은 평소(\(clockShort(avgBed)))보다 30분 일찍 잠자리에 들어 보세요.")
            } else {
                core.append("오늘은 평소보다 30분 일찍 잠자리에 들어 보세요.")
            }
            extra.append("졸리면 오후 3시 전에 20분 이내로만 낮잠을 자세요.")
        } else if s.asleepMin > 9 * 60 {
            core.append("오래 잤는데도 피곤하다면 아침에 햇빛을 10분 이상 쬐어 보세요.")
        } else if !irregular {
            core.append("수면 시간은 충분해요. 지금 리듬을 유지하세요.")
        }
        var specific: [String] = []
        if s.awakeMin >= 30 {
            specific.append("자기 1시간 전부터는 휴대폰 화면을 멀리하고 방을 어둡고 서늘하게 해 보세요.")
        }
        if irregular, let avgBed = s.avgBedtimeMin {
            specific.append("이번 주는 매일 \(clockShort(avgBed)) 전후 30분 안에 잠드는 것을 목표로 해 보세요.")
        }
        if s.hasStages && s.deepPct < 10 {
            specific.append("낮에 30분 정도 걷거나 가볍게 운동하면 깊은 수면에 도움이 돼요. 단, 잠들기 3시간 전에는 피하세요.")
        }
        var recs = core + specific + extra
        if recs.count < 2 {
            recs.append("아침에 일어나면 바로 커튼을 열어 햇빛을 받으세요.")
        }

        var stale = ""
        if s.daysSinceLastNight >= 2 {
            stale = "참고로 가장 최근 수면 기록이 \(s.daysSinceLastNight)일 전 것이에요. 워치를 차고 주무셨는지 확인해 주세요. "
            summary.insert("가장 최근 기록은 \(s.daysSinceLastNight)일 전입니다.", at: 0)
        }

        let speech = "좋은 아침이에요. " + stale
            + summary.filter { !$0.hasPrefix("가장 최근 기록은") }.joined(separator: " ")
            + " 오늘은 이렇게 해 보세요. "
            + recs.prefix(3).enumerated().map { "\($0.offset + 1)번, \($0.element)" }.joined(separator: " ")

        return SleepReport(day: s.day, source: .rules, model: nil,
                           summary: summary.joined(separator: " "),
                           recommendations: Array(recs.prefix(4)),
                           speech: speech)
    }

    static func clockShort(_ minutesAfter18: Int) -> String {
        SleepStats.clock(fromMinutesAfter18: minutesAfter18)
    }
}
