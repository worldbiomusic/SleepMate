import Charts
import SwiftUI

// 수면 관련 시각화 (홈·리포트·밤 상세에서 사용)

extension SleepStage {
    /// 차트 축 이름 (짧게)
    var shortLabel: String {
        switch self {
        case .inBed: return "침대"
        case .asleepUnspecified: return "수면"
        case .awake: return "깸"
        case .core: return "코어"
        case .deep: return "깊은"
        case .rem: return "REM"
        }
    }
}

enum StagePalette {
    /// 차트 범례·색 순서 (누적 막대·도넛 공통)
    static let order: [SleepStage] = [.deep, .core, .rem, .asleepUnspecified, .awake]
    static var names: [String] { order.map(\.shortLabel) }
    static var colors: [Color] { order.map(\.color) }
}

// MARK: - 하이프노그램: 밤새 수면 단계가 어떻게 바뀌었는지

struct HypnogramChart: View {
    let night: SleepNight

    private struct Seg: Identifiable {
        let id: UUID
        let stage: SleepStage
        let start: Date
        let end: Date
    }

    private var segs: [Seg] {
        night.segments
            .filter { $0.stage != .inBed }
            .map { Seg(id: $0.id, stage: $0.stage, start: $0.start, end: $0.end) }
    }

    /// 위에서 아래로: 깸 → REM → 코어 → 깊은 (+ 단계 미상)
    private var lanes: [String] {
        var l = ["깸", "REM", "코어", "깊은"]
        if segs.contains(where: { $0.stage == .asleepUnspecified }) { l.append("수면") }
        return l
    }

    var body: some View {
        if segs.isEmpty {
            Text("단계 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Chart(segs) { s in
                RectangleMark(
                    xStart: .value("시작", s.start),
                    xEnd: .value("끝", s.end),
                    y: .value("단계", s.stage.shortLabel),
                    height: .ratio(0.85)
                )
                .foregroundStyle(s.stage.color)
                .cornerRadius(3)
            }
            .chartYScale(domain: lanes)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 150)
        }
    }
}

// MARK: - 단계 비율 도넛

struct StageDonut: View {
    let night: SleepNight
    var size: CGFloat = 140

    private struct Part: Identifiable {
        let name: String
        let minutes: Double
        var id: String { name }
    }

    private var parts: [Part] {
        StagePalette.order.compactMap { st in
            guard let t = night.stageTotals[st], t > 0 else { return nil }
            return Part(name: st.shortLabel, minutes: t / 60)
        }
    }

    var body: some View {
        Chart(parts) { p in
            SectorMark(angle: .value("분", p.minutes), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(by: .value("단계", p.name))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: StagePalette.names, range: StagePalette.colors)
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(Fmt.duration(night.asleep)).font(.caption.weight(.bold))
                Text("수면").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 도넛 + 단계별 비율 표
struct StageBreakdownView: View {
    let night: SleepNight

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            StageDonut(night: night, size: 130)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(StagePalette.order, id: \.self) { st in
                    if let t = night.stageTotals[st], t > 0 {
                        let pct = night.asleep + (night.stageTotals[.awake] ?? 0) > 0
                            ? Int((t / (night.asleep + (night.stageTotals[.awake] ?? 0)) * 100).rounded()) : 0
                        HStack(spacing: 6) {
                            Circle().fill(st.color).frame(width: 9, height: 9)
                            Text(st.shortLabel).font(.caption)
                            Spacer()
                            Text("\(pct)%").font(.caption.monospacedDigit().weight(.semibold))
                            Text(Fmt.duration(t)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 최근 7일 단계별 누적 막대

struct WeekStageChart: View {
    let nights: [SleepNight]
    let goalMinutes: Int

    private struct Row: Identifiable {
        let id = UUID()
        let day: String
        let stage: String
        let hours: Double
    }

    private var days: [SleepNight] { Array(nights.prefix(7).reversed()) }

    private var rows: [Row] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d(E)"
        return days.flatMap { n in
            StagePalette.order.compactMap { st -> Row? in
                guard let t = n.stageTotals[st], t > 0 else { return nil }
                return Row(day: f.string(from: n.day), stage: st.shortLabel, hours: t / 3600)
            }
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("기록이 쌓이면 추세가 보여요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(rows) { r in
                    BarMark(x: .value("날짜", r.day), y: .value("시간", r.hours))
                        .foregroundStyle(by: .value("단계", r.stage))
                }
                RuleMark(y: .value("목표", Double(goalMinutes) / 60))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("목표 \(Clock.durationText(goalMinutes))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartForegroundStyleScale(domain: StagePalette.names, range: StagePalette.colors)
            .chartLegend(position: .bottom, spacing: 8)
            .chartYAxis {
                AxisMarks(values: [0.0, 2, 4, 6, 8, 10]) { v in
                    AxisGridLine()
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h") } }
                }
            }
            .frame(height: 220)
        }
    }
}

// MARK: - 취침·기상 시각 일관성 (막대 = 잠든 시각 ~ 깬 시각)

struct BedWakeRangeChart: View {
    let nights: [SleepNight]
    let targetBedMinutes: Int

    private struct Row: Identifiable {
        let id = UUID()
        let day: String
        let bed: Int      // 18:00 기준 분
        let wake: Int
    }

    private static func from18(_ d: Date) -> Int {
        (Clock.minutes(of: d) - 18 * 60 + 1440) % 1440
    }

    private var rows: [Row] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return nights.prefix(7).reversed().compactMap { n in
            guard let b = n.bedtime, let w = n.wakeTime else { return nil }
            var wake = Self.from18(w)
            let bed = Self.from18(b)
            if wake < bed { wake += 1440 }
            return Row(day: f.string(from: n.day), bed: bed, wake: min(wake, bed + 16 * 60))
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("취침·기상 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            let target = (targetBedMinutes - 18 * 60 + 1440) % 1440
            let lo = max(0, (min(rows.map(\.bed).min() ?? 240, target) / 60 - 1) * 60)
            let hi = ((rows.map(\.wake).max() ?? 840) / 60 + 1) * 60
            // 위쪽이 취침, 아래쪽이 기상이 되도록 음수 값으로 그린다
            Chart {
                ForEach(rows) { r in
                    BarMark(x: .value("요일", r.day),
                            yStart: .value("취침", -r.bed),
                            yEnd: .value("기상", -r.wake),
                            width: .ratio(0.45))
                        .foregroundStyle(LinearGradient(colors: [.indigo, .orange],
                                                        startPoint: .top, endPoint: .bottom))
                        .cornerRadius(5)
                }
                RuleMark(y: .value("취침 목표", -target))
                    .foregroundStyle(.indigo.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("취침 목표 \(Clock.hhmm(targetBedMinutes))").font(.caption2).foregroundStyle(.indigo)
                    }
            }
            .chartYScale(domain: -hi...(-lo))
            .chartYAxis {
                AxisMarks(values: .stride(by: 120)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Clock.hhmm(-m + 18 * 60)) } }
                }
            }
            .frame(height: 220)
        }
    }
}

// MARK: - 수면 점수 추세

struct ScoreTrendChart: View {
    let nights: [SleepNight]
    let goalMinutes: Int

    private struct Point: Identifiable {
        let id = UUID()
        let day: Date
        let score: Int
    }

    private var points: [Point] {
        let n = min(7, nights.count)
        let list = (0..<n).compactMap { i -> Point? in
            guard let s = SleepStats(nights: Array(nights[i...])) else { return nil }
            return Point(day: nights[i].day, score: SleepScore.compute(s, goalMinutes: goalMinutes).total)
        }
        return Array(list.reversed())
    }

    var body: some View {
        if points.count < 2 {
            Text("이틀 이상 기록이 있으면 점수 변화가 보여요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Chart {
                RuleMark(y: .value("좋음", 85))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("좋음 85").font(.caption2).foregroundStyle(.green)
                    }
                RuleMark(y: .value("부족", 70))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("부족 70 미만").font(.caption2).foregroundStyle(.orange)
                    }
                ForEach(points) { p in
                    AreaMark(x: .value("날짜", p.day, unit: .day), y: .value("점수", p.score))
                        .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("날짜", p.day, unit: .day), y: .value("점수", p.score))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.blue)
                    PointMark(x: .value("날짜", p.day, unit: .day), y: .value("점수", p.score))
                        .foregroundStyle(.blue)
                        .annotation(position: .top) {
                            Text("\(p.score)").font(.caption2.weight(.semibold))
                        }
                }
            }
            .chartYScale(domain: 0...105)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 170)
        }
    }
}

/// 점수 구성 막대 (시간 · 효율 · 단계 · 규칙성)
struct ScoreComponentsChart: View {
    let sc: SleepScore.Breakdown

    private struct Part: Identifiable {
        let name: String
        let value: Int
        let max: Int
        var id: String { name }
        var ratio: Double { Double(value) / Double(max) }
    }

    private var parts: [Part] {
        [Part(name: "시간", value: sc.duration, max: 50),
         Part(name: "효율", value: sc.efficiency, max: 20),
         Part(name: "단계", value: sc.stages, max: 15),
         Part(name: "규칙성", value: sc.regularity, max: 15)]
    }

    var body: some View {
        Chart(parts) { p in
            BarMark(x: .value("만점", 100), y: .value("항목", p.name), stacking: .unstacked)
                .foregroundStyle(Color.gray.opacity(0.15))
            BarMark(x: .value("달성", p.ratio * 100), y: .value("항목", p.name), stacking: .unstacked)
                .foregroundStyle(p.ratio >= 0.8 ? Color.green : (p.ratio >= 0.6 ? Color.blue : Color.orange))
                .annotation(position: .trailing) {
                    Text("\(p.value)/\(p.max)").font(.caption2.monospacedDigit())
                }
        }
        .chartXScale(domain: 0...120)
        .chartXAxis(.hidden)
        .frame(height: 130)
    }
}
