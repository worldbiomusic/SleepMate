import Charts
import SwiftUI

// 시나리오 01 시각화: 하루 타임라인 · 추정 컨디션 곡선 · 일정 조정 전/후

/// 타임라인에 찍을 추천 시각
struct DayMarker: Identifiable {
    let id = UUID()
    let time: Date
    let label: String
    let color: Color
}

extension DayPlanner {
    /// 오늘 하루 중 '언제' 하면 좋은지 (타임라인 표시용)
    static func markers(_ i: Input) -> [DayMarker] {
        let base = Calendar.current.startOfDay(for: i.now)
        func at(_ m: Int) -> Date { base.addingTimeInterval(TimeInterval(m * 60)) }
        let timed = i.items.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let low = lowSleepSignal(i)
        var out: [DayMarker] = []

        if let first = timed.first(where: { Calendar.current.component(.hour, from: $0.start) < 13 }) {
            out.append(DayMarker(time: first.start.addingTimeInterval(-40 * 60), label: "☀️산책", color: .yellow))
        } else {
            out.append(DayMarker(time: at(9 * 60), label: "☀️산책", color: .yellow))
        }
        out.append(DayMarker(time: at(12 * 60 + 30), label: "🍚점심", color: .green))
        if low {
            out.append(DayMarker(time: at(14 * 60), label: "☕︎컷", color: .brown))
            if let nap = freeSlot(in: timed, from: 13 * 60, to: 15 * 60, minutes: 30, day: i.now) {
                out.append(DayMarker(time: nap, label: "😴낮잠", color: .purple))
            }
        }
        out.append(DayMarker(time: at(i.profile.bedtimeMinutes - 180), label: "🍽저녁", color: .green))
        out.append(DayMarker(time: at(i.profile.bedtimeMinutes - i.profile.windDownLeadMinutes),
                             label: "📵준비", color: .indigo))
        let bed = low ? i.profile.bedtimeMinutes - 30 : i.profile.bedtimeMinutes
        out.append(DayMarker(time: at(bed), label: "🌙취침", color: .indigo))
        return out
    }
}

/// 오늘 일정 + 추천 시각 + 지금 위치
struct DayTimelineChart: View {
    let items: [PlanItem]
    let markers: [DayMarker]
    var now = Date()

    private var range: ClosedRange<Date> {
        let base = Calendar.current.startOfDay(for: now)
        let start = base.addingTimeInterval(7 * 3600)
        let lastMarker = markers.map(\.time).max() ?? base.addingTimeInterval(23 * 3600)
        let end = max(lastMarker.addingTimeInterval(30 * 60), base.addingTimeInterval(22 * 3600))
        return start...end
    }

    var body: some View {
        Chart {
            ForEach(items.filter { !$0.isAllDay }) { it in
                BarMark(xStart: .value("시작", it.start), xEnd: .value("끝", it.end),
                        y: .value("구분", "일정"), height: .ratio(0.7))
                    .foregroundStyle(it.isFixed ? Color.gray.opacity(0.55) : Color.green.opacity(0.7))
                    .cornerRadius(4)
                    .annotation(position: .overlay, alignment: .center) {
                        if it.durationMin >= 90 {
                            Text(String(it.title.prefix(2))).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            // 가까운 표시끼리 겹치지 않게 위/아래 번갈아 이름 표시
            ForEach(Array(markers.sorted { $0.time < $1.time }.enumerated()), id: \.element.id) { idx, m in
                PointMark(x: .value("시각", m.time), y: .value("구분", "추천"))
                    .foregroundStyle(m.color)
                    .symbolSize(80)
                    .annotation(position: idx % 2 == 0 ? .top : .bottom, spacing: 2) {
                        Text(m.label).font(.system(size: 9))
                    }
            }
            if range.contains(now) {
                RuleMark(x: .value("지금", now))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .bottom) {
                        Text("지금").font(.caption2.weight(.bold)).foregroundStyle(.red)
                    }
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: ["일정", "추천"])
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 170)
    }
}

/// 추정 컨디션(각성도) 곡선 — 생체 리듬 + 수면 점수로 만든 단순 모델 (참고용)
enum EnergyModel {
    struct Point: Identifiable {
        let id = UUID()
        let time: Date
        let level: Double     // 0~100
    }

    static func curve(wakeMinutes: Int, bedMinutes: Int, score: Int?, day: Date = Date()) -> [Point] {
        let base = Calendar.current.startOfDay(for: day)
        let factor = 0.55 + 0.45 * Double(score ?? 75) / 100
        // (시각(분), 상대 각성도) 기준점: 기상 직후 낮음 → 오전 상승 → 점심 뒤 하락 → 저녁 회복 → 취침 전 하락
        var bed = bedMinutes
        if bed < wakeMinutes { bed += 1440 }
        let anchors: [(Int, Double)] = [
            (wakeMinutes, 0.40),
            (wakeMinutes + 120, 0.72),
            (11 * 60, 0.88),
            (12 * 60 + 30, 0.80),
            (14 * 60 + 30, 0.55),
            (16 * 60 + 30, 0.74),
            (18 * 60, 0.82),
            (bed - 120, 0.60),
            (bed, 0.30),
        ].filter { $0.0 >= wakeMinutes && $0.0 <= bed }.sorted { $0.0 < $1.0 }

        return anchors.map { m, v in
            Point(time: base.addingTimeInterval(TimeInterval(m * 60)), level: (v * factor * 100).rounded())
        }
    }
}

struct EnergyCurveChart: View {
    let points: [EnergyModel.Point]
    var now = Date()

    private var peak: EnergyModel.Point? { points.max { $0.level < $1.level } }
    private var dip: EnergyModel.Point? {
        // 오후 낮은 지점 (12~16시)
        points.filter {
            let h = Calendar.current.component(.hour, from: $0.time)
            return h >= 12 && h <= 16
        }.min { $0.level < $1.level }
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("시각", p.time), y: .value("컨디션", p.level))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.35), .orange.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("시각", p.time), y: .value("컨디션", p.level))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
            }
            if let pk = peak {
                PointMark(x: .value("시각", pk.time), y: .value("컨디션", pk.level))
                    .foregroundStyle(.orange)
                    .annotation(position: .top) {
                        Text("집중하기 좋은 때").font(.caption2.weight(.semibold))
                    }
            }
            if let d = dip {
                PointMark(x: .value("시각", d.time), y: .value("컨디션", d.level))
                    .foregroundStyle(.purple)
                    .annotation(position: .bottom) {
                        Text("가벼운 일·휴식").font(.caption2)
                    }
            }
            if let f = points.first?.time, let l = points.last?.time, (f...l).contains(now) {
                RuleMark(x: .value("지금", now)).foregroundStyle(.red.opacity(0.7))
            }
        }
        .chartYScale(domain: 0...110)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 140)
    }
}

/// 일정 조정 전/후 비교
struct ProposalCompareChart: View {
    let items: [PlanItem]
    let proposals: [ScheduleChange]

    private struct Bar: Identifiable {
        let id = UUID()
        let lane: String
        let title: String
        let start: Date
        let end: Date
        let kind: Int   // 0 그대로, 1 이동됨, 2 추가됨
    }

    private var bars: [Bar] {
        let timed = items.filter { !$0.isAllDay }
        var out = timed.map { Bar(lane: "현재", title: $0.title, start: $0.start, end: $0.end, kind: 0) }
        for it in timed {
            if let p = proposals.first(where: { $0.kind == .move && $0.itemID == it.id }) {
                out.append(Bar(lane: "제안", title: it.title, start: p.toStart, end: p.toEnd, kind: 1))
            } else {
                out.append(Bar(lane: "제안", title: it.title, start: it.start, end: it.end, kind: 0))
            }
        }
        for p in proposals where p.kind == .addBreak {
            out.append(Bar(lane: "제안", title: "휴식", start: p.toStart, end: p.toEnd, kind: 2))
        }
        return out
    }

    var body: some View {
        Chart(bars) { b in
            BarMark(xStart: .value("시작", b.start), xEnd: .value("끝", b.end),
                    y: .value("구분", b.lane), height: .ratio(0.6))
                .foregroundStyle(b.kind == 1 ? Color.green : (b.kind == 2 ? Color.mint : Color.gray.opacity(0.45)))
                .cornerRadius(3)
                .annotation(position: .overlay, alignment: .leading) {
                    Text(b.title).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).padding(.leading, 2)
                }
        }
        .chartYScale(domain: ["현재", "제안"])
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 110)
    }
}
