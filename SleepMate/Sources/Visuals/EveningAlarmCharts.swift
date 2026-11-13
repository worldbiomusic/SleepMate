import Charts
import SwiftUI

// 시나리오 02 · 04 · 설정 시각화

// MARK: - 02 취침까지 카운트다운 링

struct BedtimeCountdown: View {
    let profile: UserProfile
    var now = Date()

    var body: some View {
        let rt = RealtimeContext(now: now, profile: profile, todayItems: [])
        let left = rt.minutesToBedtime
        let lead = profile.windDownLeadMinutes
        let inWindow = left <= lead && left >= 0
        let progress = inWindow ? 1 - Double(left) / Double(max(lead, 1)) : (left < 0 ? 1 : 0)

        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [.indigo, .purple, .orange], center: .center),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: left < 0 ? "moon.zzz.fill" : "moon.fill").foregroundStyle(.indigo)
                    Text(left < 0 ? "취침 시간" : Clock.durationText(left))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text(left < 0 ? "지났어요" : "남음").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                Text("취침 목표 \(Clock.text(profile.bedtimeMinutes))").font(.headline)
                Text(stateText(left: left, lead: lead)).font(.footnote).foregroundStyle(.secondary)
                Gauge(value: progress) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                } minimumValueLabel: {
                    Text("-\(lead)분").font(.caption2)
                } maximumValueLabel: {
                    Text("취침").font(.caption2)
                }
                .gaugeStyle(.accessoryLinear)
                .tint(Gradient(colors: [.indigo, .purple, .orange]))
            }
        }
        .padding(.vertical, 4)
    }

    private func stateText(left: Int, lead: Int) -> String {
        if left < 0 { return "목표 시각이 지났어요. 지금 바로 누워도 늦지 않아요." }
        if left <= 30 { return "준비 마무리 단계예요. 화면을 끄고 조명을 낮춰요." }
        if left <= lead { return "취침 준비 시간이에요. 화면 사용을 줄여 볼까요?" }
        return "취침 준비는 \(Clock.durationText(left - lead)) 뒤에 시작해요."
    }
}

/// 02 취침 준비 단계 타임라인 (가로)
struct WindDownTimelineChart: View {
    let profile: UserProfile
    var now = Date()

    private struct Step: Identifiable {
        let id = UUID()
        let minute: Int     // 취침 기준 상대 분 (음수)
        let label: String
        let color: Color
    }

    private var steps: [Step] {
        [Step(minute: -profile.windDownLeadMinutes, label: "패턴 안내", color: .blue),
         Step(minute: -60, label: "목표 확인", color: .purple),
         Step(minute: -30, label: "준비 시작", color: .orange),
         Step(minute: 0, label: "취침", color: .indigo)]
    }

    var body: some View {
        let lead = profile.windDownLeadMinutes
        let rel = -RealtimeContext(now: now, profile: profile, todayItems: []).minutesToBedtime
        Chart {
            BarMark(xStart: .value("시작", -lead), xEnd: .value("끝", 0), y: .value("", "흐름"),
                    height: .ratio(0.25))
                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.5), .indigo],
                                                startPoint: .leading, endPoint: .trailing))
                .cornerRadius(5)
            ForEach(steps) { s in
                PointMark(x: .value("시각", s.minute), y: .value("", "흐름"))
                    .foregroundStyle(s.color)
                    .symbolSize(140)
                    .annotation(position: .top, spacing: 4) {
                        VStack(spacing: 0) {
                            Text(s.label).font(.system(size: 10, weight: .semibold))
                            Text(Clock.hhmm(profile.bedtimeMinutes + s.minute)).font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            if rel >= -lead - 30 && rel <= 30 {
                RuleMark(x: .value("지금", rel))
                    .foregroundStyle(.red)
                    .annotation(position: .bottom) {
                        Text("지금").font(.caption2.weight(.bold)).foregroundStyle(.red)
                    }
            }
        }
        .chartXScale(domain: (-lead - 10)...20)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 80)
    }
}

/// 02 최근 7일 화면 기록 (목표선)
struct ScreenHistoryChart: View {
    let history: [DailyContext]     // 오늘 포함, 최신순
    let goal: Int

    private struct Row: Identifiable {
        let id = UUID()
        let day: String
        let count: Int
    }

    private var rows: [Row] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return history.prefix(7).reversed().map { Row(day: f.string(from: $0.date), count: $0.screenCount) }
    }

    var body: some View {
        Chart {
            ForEach(rows) { r in
                BarMark(x: .value("요일", r.day), y: .value("기록", r.count))
                    .foregroundStyle(r.count > goal ? Color.orange : Color.teal)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(r.count)").font(.caption2)
                    }
            }
            RuleMark(y: .value("목표", goal))
                .foregroundStyle(.gray)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("목표 \(goal)").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .frame(height: 150)
    }
}

/// 02 화면 목표 원형 게이지
struct ScreenGauge: View {
    let count: Int
    let goal: Int
    let unit: String

    var body: some View {
        Gauge(value: Double(min(count, goal * 2)), in: 0...Double(max(goal, 1) * 2)) {
            Text("화면")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text("\(count)").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("/\(goal)\(unit)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(count > goal ? .orange : .teal)
        .scaleEffect(1.5)
        .frame(width: 100, height: 100)
    }
}

// MARK: - 04 내일 계획 간트 (취침 → 수면 → 준비 → 이동 → 첫 일정)

struct TomorrowPlanChart: View {
    let bedMinutes: Int       // 자정 기준
    let wakeMinutes: Int
    let prep: Int
    let commute: Int
    let firstEvent: PlanItem?

    private struct Seg: Identifiable {
        let id = UUID()
        let lane: String
        let start: Int    // 18:00 기준 분
        let end: Int
        let name: String
        let color: Color
    }

    private static func from18(_ m: Int) -> Int { (m - 18 * 60 + 1440) % 1440 }

    private var segs: [Seg] {
        let bed = Self.from18(bedMinutes)
        var wake = Self.from18(wakeMinutes)
        if wake <= bed { wake += 1440 }
        var out = [
            Seg(lane: "계획", start: bed, end: bed + 15, name: "잠들기", color: .purple.opacity(0.6)),
            Seg(lane: "계획", start: bed + 15, end: wake, name: "수면", color: .indigo),
            Seg(lane: "계획", start: wake, end: wake + prep, name: "준비", color: .orange),
            Seg(lane: "계획", start: wake + prep, end: wake + prep + commute, name: "이동", color: .yellow),
        ]
        if let f = firstEvent {
            let s = wake + prep + commute
            out.append(Seg(lane: "계획", start: s, end: s + max(30, min(f.durationMin, 120)),
                           name: f.title, color: .gray))
        }
        // 90분 수면 주기
        var c = bed + 15
        var i = 1
        while c + 90 <= wake + 10 && i <= 7 {
            out.append(Seg(lane: "수면 주기", start: c, end: c + 90, name: "\(i)",
                           color: i % 2 == 0 ? .indigo.opacity(0.35) : .indigo.opacity(0.6)))
            c += 90
            i += 1
        }
        return out
    }

    var body: some View {
        let bed = Self.from18(bedMinutes)
        let last = segs.map(\.end).max() ?? bed + 600
        let w0 = Self.from18(wakeMinutes)
        let wakeX = w0 <= bed ? w0 + 1440 : w0
        Chart {
            ForEach(segs) { s in
                BarMark(xStart: .value("시작", s.start), xEnd: .value("끝", s.end),
                        y: .value("구분", s.lane), height: .ratio(0.65))
                    .foregroundStyle(s.color)
                    .cornerRadius(3)
                    .annotation(position: .overlay) {
                        if s.end - s.start >= 40 {
                            Text(s.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
            }
            RuleMark(x: .value("기상", wakeX))
            .foregroundStyle(.orange)
            .annotation(position: .top) {
                Text("⏰ \(Clock.hhmm(wakeMinutes))").font(.caption2.weight(.bold)).foregroundStyle(.orange)
            }
        }
        .chartXScale(domain: (bed - 15)...(last + 15))
        .chartYScale(domain: ["계획", "수면 주기"])
        .chartXAxis {
            AxisMarks(values: .stride(by: 120)) { v in
                AxisGridLine()
                AxisValueLabel { if let m = v.as(Int.self) { Text(Clock.hhmm(m + 18 * 60)) } }
            }
        }
        .frame(height: 130)
    }
}

/// 04 최근 기상 시각 추세 vs 내일 추천
struct WakeHistoryChart: View {
    let nights: [SleepNight]
    let plannedWake: Int

    private struct P: Identifiable {
        let id = UUID()
        let day: Date
        let minutes: Int
    }

    private var points: [P] {
        let list = nights.prefix(7).compactMap { n in
            n.wakeTime.map { P(day: n.day, minutes: Clock.minutes(of: $0)) }
        }
        return Array(list.reversed())
    }

    var body: some View {
        if points.isEmpty {
            Text("기상 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            let lo = ((min(points.map(\.minutes).min() ?? plannedWake, plannedWake) / 60) - 1) * 60
            let hi = ((max(points.map(\.minutes).max() ?? plannedWake, plannedWake) / 60) + 1) * 60
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("날짜", p.day, unit: .day), y: .value("기상", -p.minutes))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("날짜", p.day, unit: .day), y: .value("기상", -p.minutes))
                        .foregroundStyle(.orange)
                }
                RuleMark(y: .value("내일 추천", -plannedWake))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("내일 추천 \(Clock.hhmm(plannedWake))").font(.caption2).foregroundStyle(.green)
                    }
            }
            .chartYScale(domain: -hi...(-lo))
            .chartYAxis {
                AxisMarks(values: .stride(by: 60)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Clock.hhmm(-m)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 150)
        }
    }
}

// MARK: - 설정: 평가 지표 시각화

struct FeedbackDonut: View {
    let feedback: [FeedbackEntry]

    private struct Part: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private static let names = ["도움·적용", "나중에", "건너뛰기·거절"]
    private static let colors: [Color] = [.green, .yellow, .gray]

    private var parts: [Part] {
        [Part(name: Self.names[0], count: feedback.filter { $0.response.isPositive }.count),
         Part(name: Self.names[1], count: feedback.filter { $0.response == .later }.count),
         Part(name: Self.names[2], count: feedback.filter { $0.response == .skip || $0.response == .rejected }.count)]
            .filter { $0.count > 0 }
    }

    var body: some View {
        let total = feedback.count
        let pos = feedback.filter { $0.response.isPositive }.count
        HStack(spacing: 16) {
            Chart(parts) { p in
                SectorMark(angle: .value("횟수", p.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("반응", p.name))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: Self.names, range: Self.colors)
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(total == 0 ? "-" : "\(pos * 100 / max(total, 1))%").font(.headline)
                    Text("수락률").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<Self.names.count, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle().fill(Self.colors[i]).frame(width: 9, height: 9)
                        Text(Self.names[i]).font(.caption)
                        Spacer()
                        Text("\(parts.first { $0.name == Self.names[i] }?.count ?? 0)회")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                }
            }
        }
    }
}

/// 시나리오별 수락률
struct ScenarioAcceptChart: View {
    let feedback: [FeedbackEntry]

    private struct Row: Identifiable {
        let id = UUID()
        let scenario: String
        let rate: Int
        let total: Int
    }

    private var rows: [Row] {
        [("01", "01 하루 추천"), ("02", "02 취침 준비"), ("04", "04 알람"), ("05", "05 요약")].map { key, label in
            let list = feedback.filter { $0.scenario == key }
            let pos = list.filter { $0.response.isPositive }.count
            return Row(scenario: label, rate: list.isEmpty ? 0 : pos * 100 / list.count, total: list.count)
        }
    }

    var body: some View {
        Chart(rows) { r in
            BarMark(x: .value("수락률", r.rate), y: .value("시나리오", r.scenario))
                .foregroundStyle(r.rate >= 60 ? Color.green : (r.rate >= 30 ? Color.blue : Color.orange))
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(r.total == 0 ? "기록 없음" : "\(r.rate)% · \(r.total)회").font(.caption2)
                }
        }
        .chartXScale(domain: 0...130)
        .chartXAxis(.hidden)
        .frame(height: 140)
    }
}

/// 에이전트 판단 경로 비율 (규칙 / 경량 AI / LLM)
struct AgentPathChart: View {
    let entries: [AgentLog.Entry]

    private struct Row: Identifiable {
        let id = UUID()
        let path: String
        let count: Int
    }

    var body: some View {
        let rows = [ReasonPath.rule, .light, .llm].map { p in
            Row(path: p.rawValue, count: entries.filter { $0.path == p }.count)
        }
        Chart(rows) { r in
            BarMark(x: .value("횟수", r.count), y: .value("경로", r.path))
                .foregroundStyle(by: .value("경로", r.path))
                .annotation(position: .trailing) { Text("\(r.count)").font(.caption2) }
        }
        .chartForegroundStyleScale(domain: ["규칙", "경량 AI", "LLM"], range: [Color.blue, .teal, .orange])
        .chartLegend(.hidden)
        .frame(height: 100)
    }
}
