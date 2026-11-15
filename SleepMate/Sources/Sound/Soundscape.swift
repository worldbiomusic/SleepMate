import SwiftUI
import UIKit

// 02 수면 사운드: 오늘 상태에 맞는 소리를 고르고(Jev 또는 규칙) 유튜브 앱에서 재생
// 저작권 있는 곡을 앱에 넣지 않고, 유튜브 검색 결과로 연결한다.

extension SoundType {
    var title: String {
        switch self {
        case .rain: return "빗소리"
        case .whiteNoise: return "화이트노이즈"
        case .piano: return "잔잔한 피아노"
        case .lofi: return "로파이"
        case .nature: return "숲·파도 소리"
        case .meditation: return "수면 명상"
        }
    }

    var subtitle: String {
        switch self {
        case .rain: return "생각이 많을 때 마음을 가라앉혀요"
        case .whiteNoise: return "주변 소음을 덮고 빨리 잠들어요"
        case .piano: return "느린 선율로 긴장을 풀어요"
        case .lofi: return "가볍게 하루를 마무리해요"
        case .nature: return "자연의 리듬으로 호흡이 느려져요"
        case .meditation: return "안내 음성을 따라 몸을 이완해요"
        }
    }

    var query: String {
        switch self {
        case .rain: return "빗소리 수면 8시간"
        case .whiteNoise: return "화이트노이즈 수면 10시간"
        case .piano: return "잔잔한 수면 피아노 음악"
        case .lofi: return "lofi sleep music 3 hours"
        case .nature: return "파도 소리 숲 소리 수면"
        case .meditation: return "수면 명상 가이드 한국어"
        }
    }

    var symbol: String {
        switch self {
        case .rain: return "cloud.rain.fill"
        case .whiteNoise: return "waveform"
        case .piano: return "pianokeys"
        case .lofi: return "headphones"
        case .nature: return "leaf.fill"
        case .meditation: return "figure.mind.and.body"
        }
    }

    var colors: [Color] {
        switch self {
        case .rain: return [Color(red: 0.20, green: 0.32, blue: 0.55), Color(red: 0.42, green: 0.55, blue: 0.75)]
        case .whiteNoise: return [Color(red: 0.30, green: 0.30, blue: 0.38), Color(red: 0.55, green: 0.56, blue: 0.64)]
        case .piano: return [Color(red: 0.25, green: 0.18, blue: 0.45), Color(red: 0.55, green: 0.42, blue: 0.75)]
        case .lofi: return [Color(red: 0.55, green: 0.30, blue: 0.40), Color(red: 0.85, green: 0.55, blue: 0.50)]
        case .nature: return [Color(red: 0.12, green: 0.38, blue: 0.35), Color(red: 0.35, green: 0.62, blue: 0.50)]
        case .meditation: return [Color(red: 0.35, green: 0.22, blue: 0.50), Color(red: 0.75, green: 0.55, blue: 0.70)]
        }
    }

    /// Jev에게 주는 영어 설명
    var englishHint: String {
        switch self {
        case .rain: return "Steady rain sounds; calming for stress and racing thoughts."
        case .whiteNoise: return "White noise; masks noise, good when exhausted or in a noisy room."
        case .piano: return "Slow soft piano music; relaxing for a calm mood."
        case .lofi: return "Low-tempo lo-fi beats; light and familiar, good for a good mood."
        case .nature: return "Ocean waves and forest ambience; slows breathing."
        case .meditation: return "Guided sleep meditation in Korean; good for anxiety or trouble falling asleep."
        }
    }

    /// 유튜브 앱(설치돼 있으면)으로 검색 결과 열기
    var youtubeURLs: [URL] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return [URL(string: "youtube://www.youtube.com/results?search_query=\(q)"),
                URL(string: "https://www.youtube.com/results?search_query=\(q)")].compactMap { $0 }
    }

    @MainActor
    func openYouTube() {
        let urls = youtubeURLs
        if let app = urls.first, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = urls.last {
            UIApplication.shared.open(web)
        }
    }
}

/// 소리마다 움직이는 막대 (재생 느낌의 시각화)
struct SoundBars: View {
    var animate: Bool
    var count = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !animate)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let h = animate ? (0.35 + 0.65 * abs(sin(t * 2.2 + Double(i) * 0.9))) : 0.3
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: 4, height: 22 * h)
                }
            }
            .frame(height: 22, alignment: .bottom)
        }
    }
}

struct SoundCard: View {
    let type: SoundType
    var recommended = false
    var played = false
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: type.symbol).font(.title2)
                    Spacer()
                    SoundBars(animate: recommended)
                }
                Spacer(minLength: 0)
                Text(type.title).font(.headline)
                Text(type.subtitle).font(.caption2).opacity(0.85).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                    Text(played ? "다시 열기" : "YouTube에서 재생")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.2)))
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(width: 168, height: 168)
            .background(LinearGradient(colors: type.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if recommended {
                    Text("오늘 추천")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                        .offset(x: -8, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: played)
    }
}

/// AI 판단을 '얼마나 확신하는지' 막대로 보여준다
struct DecisionBars: View {
    let decision: DecisionView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(decision.path == .light ? "Jev" : "규칙")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(decision.path == .light ? Color.teal.opacity(0.25) : Color.gray.opacity(0.2)))
                Text("\(decision.question) → \(decision.answer)").font(.caption.weight(.semibold))
                Spacer()
                if let c = decision.confidence {
                    Text("확신 \(Int(c * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ForEach(decision.bars) { b in
                HStack(spacing: 6) {
                    Text(b.label).font(.caption2).frame(width: 74, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                            Capsule().fill(b.label == decision.answer ? Color.teal : Color.teal.opacity(0.35))
                                .frame(width: max(4, geo.size.width * b.value))
                        }
                    }
                    .frame(height: 7)
                    Text("\(Int(b.value * 100))%").font(.caption2.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
            if let n = decision.note {
                Text(n).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// 4-7-8 호흡 가이드 (원이 커졌다 작아지는 애니메이션)
struct BreathingGuide: View {
    @State private var running = false
    @State private var start = Date()

    private let phases: [(String, Double, CGFloat)] = [("들이쉬기", 4, 1.0), ("멈추기", 7, 1.0), ("내쉬기", 8, 0.45)]

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 0.05, paused: !running)) { ctx in
                let (label, remain, scale) = phase(at: ctx.date)
                ZStack {
                    Circle().fill(RadialGradient(colors: [.indigo.opacity(0.55), .purple.opacity(0.15)],
                                                 center: .center, startRadius: 5, endRadius: 90))
                        .scaleEffect(running ? scale : 0.6)
                        .animation(.easeInOut(duration: label == "들이쉬기" ? 4 : (label == "내쉬기" ? 8 : 0.3)),
                                   value: label)
                    VStack(spacing: 2) {
                        Text(running ? label : "4-7-8 호흡").font(.headline)
                        if running { Text("\(Int(ceil(remain)))").font(.title.monospacedDigit().bold()) }
                    }
                }
                .frame(width: 170, height: 170)
            }
            Button(running ? "그만하기" : "1분 호흡 시작") {
                start = Date()
                running.toggle()
            }
            .buttonStyle(.bordered)
            .sensoryFeedback(.selection, trigger: running)
            Text("4초 들이쉬고 · 7초 멈추고 · 8초 내쉬기를 3번 반복해요.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func phase(at now: Date) -> (String, Double, CGFloat) {
        guard running else { return ("", 0, 0.6) }
        var t = now.timeIntervalSince(start).truncatingRemainder(dividingBy: 19)
        for (label, len, scale) in phases {
            if t < len { return (label, len - t, scale) }
            t -= len
        }
        return ("들이쉬기", 4, 1)
    }
}

/// 취침 준비 탭의 '오늘 밤 소리' 섹션
struct SoundscapeSection: View {
    @Environment(ContextStore.self) private var ctx
    @State private var pick: SoundType?
    @State private var decision: DecisionView?
    @State private var played: Set<SoundType> = []
    @State private var loading = false

    private var ordered: [SoundType] {
        guard let p = pick else { return SoundType.allCases }
        return [p] + SoundType.allCases.filter { $0 != p }
    }

    var body: some View {
        Section {
            if loading {
                HStack { ProgressView(); Text("오늘 밤 소리를 고르는 중…").font(.caption) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ordered) { t in
                        SoundCard(type: t, recommended: t == pick, played: played.contains(t)) {
                            t.openYouTube()
                            played.insert(t)
                            ctx.record(scenario: "02", key: "music", title: t.title,
                                       response: t == pick ? .accepted : .helpful)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            if let d = decision {
                DecisionBars(decision: d)
            }
            Label("YouTube 앱의 ‘수면 타이머’(재생 화면 ⚙︎ → 수면 타이머)로 끝나는 시간을 정해 두세요.",
                  systemImage: "timer")
                .font(.caption2).foregroundStyle(.secondary)
        } header: {
            Text(ctx.today.mood.map { "오늘 밤 소리 · 기분 \($0.emoji)" } ?? "오늘 밤 소리")
        }
        .task(id: "\(ctx.today.mood?.rawValue ?? "-")-\(ctx.today.fatigue ?? 0)") { await choose() }
    }

    private func choose() async {
        loading = true
        defer { loading = false }
        let rt = RealtimeContext(now: AppClock.now, profile: ctx.profile, todayItems: [])
        let (t, d) = await JevDecisions.sound(mood: ctx.today.mood, fatigue: ctx.today.fatigue,
                                              minutesToBed: rt.minutesToBedtime,
                                              preference: ctx.profile.musicPreference)
        withAnimation(.snappy) {
            pick = t
            decision = d
        }
    }
}
