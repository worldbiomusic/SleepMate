import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model
    @State private var page = UserDefaults.standard.integer(forKey: "watchPage")

    var body: some View {
        TabView(selection: $page) {
            TonightPage().tag(0)
            LastNightPage().tag(1)
            BreathePage().tag(2)
            MoodPage().tag(3)
            AlarmPage().tag(4)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - 1. 오늘 밤

private struct TonightPage: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            ScrollView {
                if let p = model.payload {
                    let toBed = p.minutesToBed(now: tl.date)
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(Color.purple.opacity(0.2), lineWidth: 7)
                            let lead = Double(max(p.windDownLeadMinutes, 1))
                            Circle().trim(from: 0, to: toBed > 0 ? min(1, Double(toBed) / lead) : 0)
                                .stroke(Color.purple, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Image(systemName: "moon.zzz.fill").font(.caption).foregroundStyle(.purple)
                                Text(toBed > 0 ? durationText(toBed) : "취침 시간").font(.system(.title3, design: .rounded).bold())
                                    .minimumScaleFactor(0.6)
                                Text(toBed > 0 ? "남음" : "지났어요").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 104, height: 104)

                        // 오늘 밤 앱 사용
                        let r = Double(p.eveningAppMinutes) / Double(max(p.eveningLimitMinutes, 1))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("오늘 밤 앱").font(.caption2)
                                Spacer()
                                Text("\(p.eveningAppMinutes)/\(p.eveningLimitMinutes)분").font(.caption2.monospacedDigit())
                                    .foregroundStyle(r >= 1 ? .red : .secondary)
                            }
                            ProgressView(value: min(1, r)).tint(r >= 1 ? .red : (r >= 0.8 ? .orange : .teal))
                            if let app = p.openApp {
                                Text("\(app) 사용 중").font(.system(size: 11)).foregroundStyle(.orange)
                            }
                        }

                        if p.stopped {
                            Label("오늘은 여기까지", systemImage: "checkmark.seal.fill")
                                .font(.footnote).foregroundStyle(.green)
                        } else {
                            if let n = p.nudge {
                                Text(n).font(.footnote).multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let l = p.learnedNote {
                                Text(l).font(.system(size: 11)).foregroundStyle(.purple)
                                    .multilineTextAlignment(.center)
                            }
                            Button {
                                model.send(.stop)
                            } label: {
                                Label("오늘은 여기까지", systemImage: "hand.raised.fill")
                            }
                            .tint(.purple)
                        }
                        if let s = model.sent { Text(s).font(.caption2).foregroundStyle(.secondary) }
                    }
                } else {
                    NoDataView()
                }
            }
        }
        .navigationTitle("오늘 밤")
    }
}

// MARK: - 2. 어젯밤

private struct LastNightPage: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            if let p = model.payload, let score = p.score {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.25), lineWidth: 8)
                        Circle().trim(from: 0, to: Double(score) / 100)
                            .stroke(color(score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(score)").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(p.scoreLabel ?? "").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 100, height: 100)
                    if let a = p.asleepText { Text(a).font(.headline) }
                    if let n = p.sleepNote { Text(n).font(.caption2).foregroundStyle(.secondary) }
                    if let r = p.recommendation {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("오늘의 추천", systemImage: "sun.max.fill").font(.caption2.bold()).foregroundStyle(.orange)
                            Text(r).font(.footnote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
                    }
                }
            } else {
                NoDataView()
            }
        }
        .navigationTitle("어젯밤")
    }

    private func color(_ s: Int) -> Color { s >= 80 ? .green : (s >= 60 ? .yellow : .orange) }
}

// MARK: - 3. 4-7-8 호흡 (손목 진동으로 안내)

private struct BreathePage: View {
    @State private var running = false
    @State private var phase = 0          // 0 들숨 4초, 1 참기 7초, 2 날숨 8초
    @State private var round = 0
    @State private var scale: CGFloat = 0.5
    private let durations: [Double] = [4, 7, 8]
    private let labels = ["들이쉬기", "참기", "내쉬기"]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.teal.opacity(0.25)).scaleEffect(scale)
                Circle().stroke(Color.teal, lineWidth: 2).scaleEffect(scale)
                Text(running ? labels[phase] : "4-7-8").font(.headline)
            }
            .frame(width: 110, height: 110)
            Text(running ? "\(round + 1) / 4회" : "손목 진동에 맞춰 숨 쉬어요").font(.caption2).foregroundStyle(.secondary)
            Button(running ? "멈추기" : "시작") {
                running.toggle()
                if running { round = 0; step(0) } else { withAnimation { scale = 0.5 } }
            }
            .tint(.teal)
        }
        .navigationTitle("호흡")
    }

    private func step(_ p: Int) {
        guard running else { return }
        phase = p
        WKInterfaceDevice.current().play(p == 0 ? .start : (p == 1 ? .click : .stop))
        withAnimation(.easeInOut(duration: durations[p])) { scale = p == 2 ? 0.5 : 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + durations[p]) {
            guard running else { return }
            if p < 2 { step(p + 1) }
            else if round < 3 { round += 1; step(0) }
            else { running = false; WKInterfaceDevice.current().play(.success) }
        }
    }
}

// MARK: - 4. 기분 체크

private struct MoodPage: View {
    @Environment(WatchModel.self) private var model
    private let moods: [(String, String)] = [("좋음", "😊"), ("평온", "😌"), ("피곤", "🥱"), ("스트레스", "😣"), ("불안", "😟")]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("지금 기분은?").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(moods, id: \.0) { m in
                        Button {
                            model.send(.mood, value: m.0)
                        } label: {
                            VStack(spacing: 0) {
                                Text(m.1).font(.title3)
                                Text(m.0).font(.system(size: 11))
                            }
                        }
                        .tint(model.payload?.mood == m.0 ? .purple : .gray)
                    }
                }
                Text("기분에 맞춰 취침 전 한마디와 수면 사운드가 바뀌어요").font(.system(size: 10))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .navigationTitle("기분")
    }
}

// MARK: - 5. 내일 알람

private struct AlarmPage: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            if let p = model.payload, let w = p.wakeText {
                VStack(spacing: 6) {
                    Image(systemName: "alarm.fill").font(.title3).foregroundStyle(.blue)
                    Text("내일 기상").font(.caption).foregroundStyle(.secondary)
                    Text(w).font(.system(size: 40, weight: .bold, design: .rounded))
                    if let r = p.wakeReason { Text(r).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    Text("목표 취침 \(clock(p.bedtimeMinutes))").font(.footnote).padding(.top, 2)
                    Text("업데이트 \(p.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                NoDataView()
            }
        }
        .navigationTitle("알람")
    }
}

private struct NoDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(.secondary)
            Text("아이폰에서 SleepMate를 한 번 열어 주세요").font(.footnote).multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
}

private func durationText(_ m: Int) -> String {
    let h = m / 60, mm = m % 60
    if h == 0 { return "\(mm)분" }
    return mm == 0 ? "\(h)시간" : "\(h)시간 \(mm)분"
}

private func clock(_ m: Int) -> String {
    String(format: "%02d:%02d", (m / 60) % 24, m % 60)
}
