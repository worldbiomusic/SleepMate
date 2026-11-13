import Charts
import SwiftUI

// 시나리오 05: AI가 읽어주는 수면 요약 + 홈 대시보드
// (요약·추천·음성 로직은 CoachStore / RuleReporter / ClaudeClient)

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 92

    private var color: Color {
        switch score {
        case 85...: return .green
        case 70..<85: return .blue
        default: return .orange
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                Text("/ 100").font(.system(size: size * 0.12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 홈 맨 위: GOOD MORNING 카드 (점수 · 평균 대비 · 오늘의 추천 · 요약 듣기)
struct DashboardHeader: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CoachStore.self) private var coach
    @Environment(CalendarService.self) private var calendar
    var openToday: () -> Void

    var body: some View {
        let stats = SleepStats(nights: store.nights)
        VStack(alignment: .leading, spacing: 14) {
            Text(greeting).font(.caption.weight(.bold)).foregroundStyle(.orange)
            if let s = stats {
                let sc = SleepScore.compute(s, goalMinutes: ctx.profile.goalSleepMinutes)
                HStack(spacing: 18) {
                    ScoreRing(score: sc.total)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("수면 점수 · \(sc.label)").font(.subheadline.weight(.semibold))
                        Text(Clock.durationText(s.asleepMin))
                            .font(.title2.weight(.bold))
                        if let avg = s.avg7AsleepMin, s.nightsIn7 >= 3 {
                            let diff = s.asleepMin - avg
                            Text(diff >= 0 ? "최근 평균보다 +\(Clock.durationText(diff))"
                                           : "최근 평균보다 \(Clock.durationText(-diff)) 짧아요")
                                .font(.footnote).foregroundStyle(diff >= 0 ? .green : .orange)
                        }
                    }
                }
                ScoreBreakdownRow(sc: sc)

                if let top = topRecommendation(stats: s, score: sc.total) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("오늘의 추천").font(.caption).foregroundStyle(.secondary)
                        Label(top.title, systemImage: top.icon).font(.callout.weight(.semibold))
                    }
                }
            } else {
                Text("아직 수면 기록이 없어요").font(.headline)
                Text("오른쪽 위 ↻ 버튼으로 단축어를 실행해 기록을 가져와 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    if coach.speech.isSpeaking {
                        coach.stopSpeaking()
                    } else {
                        coach.speak()
                        ctx.record(scenario: "05", key: "listen", title: "수면 요약 듣기", response: .helpful)
                    }
                } label: {
                    Label(coach.speech.isSpeaking ? "정지" : "수면 요약 듣기",
                          systemImage: coach.speech.isSpeaking ? "stop.fill" : "play.fill")
                        .labelStyle(.titleAndIcon).lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coach.report == nil)

                Button {
                    openToday()
                } label: {
                    Label("오늘의 추천", systemImage: "list.bullet.rectangle")
                        .labelStyle(.titleAndIcon).lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 4..<11: return "GOOD MORNING"
        case 11..<18: return "GOOD AFTERNOON"
        default: return "GOOD NIGHT"
        }
    }

    private func topRecommendation(stats: SleepStats, score: Int) -> DayRecommendation? {
        let items = calendar.items(on: Date(), fixedKeywords: ctx.profile.fixedKeywords)
        let input = DayPlanner.Input(stats: stats, score: score, daily: ctx.today, profile: ctx.profile,
                                     items: items, skipped: { ctx.isOftenSkipped($0) })
        return DayPlanner.recommendations(input).first { $0.key != "stale" && $0.key != "nodata" }
    }
}

struct ScoreBreakdownRow: View {
    let sc: SleepScore.Breakdown

    var body: some View {
        HStack(spacing: 6) {
            part("시간", sc.duration, 50)
            part("효율", sc.efficiency, 20)
            part("단계", sc.stages, 15)
            part("규칙성", sc.regularity, 15)
        }
    }

    private func part(_ name: String, _ v: Int, _ max: Int) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text("\(v)/\(max)").font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
    }
}

/// 최근 7일 수면 시간 막대 + 목표선
struct WeekChart: View {
    let nights: [SleepNight]
    let goalMinutes: Int

    private struct Bar: Identifiable {
        let id: Date
        let label: String
        let hours: Double
    }

    private var bars: [Bar] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return nights.prefix(7).reversed().map {
            Bar(id: $0.day, label: f.string(from: $0.day) + "\n" + Self.md($0.day), hours: $0.asleep / 3600)
        }
    }

    private static func md(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: d)
    }

    var body: some View {
        if bars.isEmpty {
            Text("기록이 쌓이면 추세가 보여요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("날짜", b.label), y: .value("시간", b.hours))
                        .foregroundStyle(b.hours * 60 >= Double(goalMinutes) - 30 ? Color.indigo : Color.orange)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("목표", Double(goalMinutes) / 60))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("목표 \(Clock.durationText(goalMinutes))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, 2, 4, 6, 8, 10]) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let h = v.as(Double.self) { Text("\(Int(h))h") }
                    }
                }
            }
            .frame(height: 180)
        }
    }
}
