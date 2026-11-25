import AVKit
import Charts
import SwiftUI
import UIKit

// '소개' 탭: 프로젝트 설명 · 구조 · 동작 방식 (이미지 + 시각화)
// 발표나 시연 때 앱 하나로 설명할 수 있도록 만든 화면.

struct GuideView: View {
    @State private var zoom: GuideShot?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    GuideContent(zoom: $zoom)
                }
                .task {
                    // CI 스크린샷: -guideSection N 이면 N번째 구역으로 스크롤
                    let n = UserDefaults.standard.integer(forKey: "guideSection")
                    if n > 0 {
                        try? await Task.sleep(for: .milliseconds(600))
                        proxy.scrollTo(n, anchor: .top)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("소개")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $zoom) { shot in ShotZoomView(shot: shot) }
        }
    }
}

struct GuideContent: View {
    @Binding var zoom: GuideShot?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            GuideHero().id(0)
            GuideVideoSection().id(10)
            ProblemSection().id(1)
            ScenarioSection(zoom: $zoom).id(2)
            ArchitectureSection().id(3)
            DecisionFlowSection().id(4)
            HybridAISection().id(5)
            DayRhythmSection().id(6)
            PrivacySection().id(7)
            PipelineSection().id(8)
            WatchSection(zoom: $zoom).id(11)
            GuideFooter().id(9)
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
    }
}

// MARK: - 공통 조각

struct GuideShot: Identifiable {
    let id: String          // 번들 이미지 이름 (guide-*.jpg)
    let caption: String
    var image: UIImage? { UIImage(named: id + ".jpg") }
}

private struct GuideSectionTitle: View {
    let number: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number).font(.caption.weight(.heavy)).foregroundStyle(.indigo)
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct Chip: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

private struct DownArrow: View {
    var label: String = ""
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down").font(.caption.bold())
            if !label.isEmpty { Text(label).font(.caption2) }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct ShotThumb: View {
    let shot: GuideShot
    var body: some View {
        Group {
            if let img = shot.image {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct ShotZoomView: View {
    let shot: GuideShot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                if let img = shot.image {
                    Image(uiImage: img).resizable().scaledToFit().padding(.horizontal)
                }
                Text(shot.caption).font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
        .onTapGesture { dismiss() }
    }
}

// MARK: - 1. 표지

private struct GuideHero: View {
    @State private var glow = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.30), Color(red: 0.32, green: 0.20, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // 별
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<40 {
                    let x = rng.next() * size.width, y = rng.next() * size.height * 0.7
                    let r = 0.6 + rng.next() * 1.6
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.4 + rng.next() * 0.5)))
                }
            }
            // 달
            ZStack {
                Circle().fill(Color(red: 1, green: 0.93, blue: 0.70)).frame(width: 74, height: 74)
                Circle().fill(Color(red: 0.16, green: 0.13, blue: 0.38)).frame(width: 64, height: 64).offset(x: 20, y: -12)
            }
            .shadow(color: .yellow.opacity(glow ? 0.55 : 0.2), radius: glow ? 26 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(22)

            VStack(alignment: .leading, spacing: 6) {
                Text("SleepMate AI").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.7))
                Text("이젠 잘 때도 됐잖아").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("수면 데이터와 오늘의 일정을 함께 보고\n어젯밤 → 오늘 → 오늘 밤을 이어 주는 수면 AI 에이전트")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 6) {
                    ForEach(["평택대 AI융합대학원", "AI응용융합연구", "iPhone 12 Pro"], id: \.self) { t in
                        Text(t).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.15)))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.top, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

/// 별 위치를 매번 같게 그리기 위한 간단한 난수
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

// MARK: - 사용 예시 영상

private struct GuideVideoSection: View {
    @State private var player: AVPlayer? = Bundle.main.url(forResource: "demo-tour", withExtension: "mp4").map { AVPlayer(url: $0) }

    var body: some View {
        if let player {
            VStack(alignment: .leading, spacing: 12) {
                GuideSectionTitle(number: "00  영상으로 보기", title: "30초 사용 예시",
                                  subtitle: "아침 요약 → 오늘 추천 → 기상 알람 → 취침 준비 → 기억 → 애플워치")
                HStack {
                    Spacer()
                    VideoPlayer(player: player)
                        .aspectRatio(540.0 / 1170.0, contentMode: .fit)
                        .frame(height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.gray.opacity(0.3)))
                        .onDisappear { player.pause() }
                    Spacer()
                }
                Text("테스트 모드의 4주 가상 기록으로 시뮬레이터에서 녹화했어요.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 애플워치

private struct WatchSection: View {
    @Binding var zoom: GuideShot?
    private let shots = [GuideShot(id: "guide-watch-1", caption: "워치 · 오늘 밤 (남은 시간 · 앱 사용 · 오늘은 여기까지)"),
                         GuideShot(id: "guide-watch-2", caption: "워치 · 어젯밤 점수와 오늘의 추천"),
                         GuideShot(id: "guide-watch-3", caption: "워치 · 4-7-8 호흡 (손목 진동 안내)")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "09  손목에서", title: "애플워치 앱",
                              subtitle: "판단은 아이폰이 하고, 워치는 보여 주고 입력받아요 (Companion Relay)")
            Card {
                HStack(spacing: 8) {
                    ForEach(shots) { s in
                        Button { zoom = s } label: { ShotThumb(shot: s) }.buttonStyle(.plain)
                    }
                }
                ForEach(["오늘 밤: 취침까지 남은 시간 링, 오늘 밤 앱 사용, 지금 한마디, ‘오늘은 여기까지’",
                         "어젯밤: 수면 점수와 오늘의 추천 한 가지",
                         "호흡: 4-7-8 호흡을 손목 진동으로 안내",
                         "기분: 한 번 눌러 아이폰으로 전송 → 한마디·사운드에 반영",
                         "알람: 내일 기상 시각과 이유"], id: \.self) { t in
                    Label(t, systemImage: "applewatch").font(.footnote)
                }
                Text("한도 알림·취침 알림은 아이폰이 잠겨 있으면 워치로 자동 전달돼 손목에서 진동해요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 2. 문제와 해결

private struct ProblemSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "01  왜 만들었나", title: "기록만 하는 수면 앱의 한계",
                              subtitle: "수면 점수를 봐도 ‘그래서 오늘 뭘 해야 하지?’가 남는다")
            HStack(alignment: .top, spacing: 10) {
                problemCard("chart.bar.xaxis", "기록에서 끝남", "점수·그래프만 보여 주고\n행동으로 이어지지 않음", .gray)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 34)
                problemCard("brain.head.profile", "맥락을 보고 판단", "수면 + 일정 + 할 일 +\n지금 시각을 함께 봄", .indigo)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 34)
                problemCard("hand.tap", "행동까지", "추천 · 일정 조정 ·\n취침 개입 · 알람", .green)
            }
        }
    }

    private func problemCard(_ symbol: String, _ title: String, _ text: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
                .frame(width: 46, height: 46).background(Circle().fill(color.opacity(0.13)))
            Text(title).font(.caption.bold())
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3. 시나리오

private struct ScenarioSection: View {
    @Binding var zoom: GuideShot?

    private struct Scenario: Identifiable {
        let id: String
        let title: String
        let tab: String
        let color: Color
        let symbol: String
        let points: [String]
        let shots: [GuideShot]
    }

    private let list: [Scenario] = [
        Scenario(id: "01", title: "다음 날 행동·일정 추천", tab: "오늘 탭", color: .orange, symbol: "sun.max.fill",
                 points: ["수면으로 추정한 오늘 컨디션 곡선", "연속 일정 사이 쉬는 시간 제안 (승인 후 이동)",
                          "노션 할 일을 집중도에 맞는 시간대에 배치"],
                 shots: [GuideShot(id: "guide-today", caption: "오늘 탭 — 컨디션 곡선과 일정 타임라인"),
                         GuideShot(id: "guide-notion", caption: "노션 할 일 연결")]),
        Scenario(id: "02", title: "취침 전 화면 관리", tab: "취침 준비 탭", color: .purple, symbol: "bed.double.fill",
                 points: ["취침까지 남은 시간 · 화면 사용 목표", "Jev가 지금 말을 걸지, 어떤 말투로 할지 판단",
                          "YouTube 수면 사운드 · 4-7-8 호흡"],
                 shots: [GuideShot(id: "guide-winddown", caption: "취침 준비 탭"),
                         GuideShot(id: "guide-sound", caption: "기분에 맞춘 수면 사운드")]),
        Scenario(id: "04", title: "상황 기반 기상 알람", tab: "알람 탭", color: .blue, symbol: "alarm.fill",
                 points: ["내일 첫 일정에서 거꾸로 계산", "수면 주기(90분)에 맞춘 기상 후보",
                          "단축어로 시계 앱 알람까지 설정"],
                 shots: [GuideShot(id: "guide-alarm", caption: "알람 탭 — 일정 기준 추천 기상 시각")]),
        Scenario(id: "05", title: "AI 음성 수면 요약", tab: "홈 탭", color: .teal, symbol: "waveform",
                 points: ["어젯밤 단계·점수·주간 추세 시각화", "Claude가 요약과 추천 3개 작성",
                          "아침에 30초 음성으로 읽어 줌"],
                 shots: [GuideShot(id: "guide-home", caption: "홈 — 수면 점수와 어젯밤 요약"),
                         GuideShot(id: "guide-report", caption: "주간 리포트"),
                         GuideShot(id: "guide-coach", caption: "AI 수면 코치")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "02  무엇을 하나", title: "계획서의 4가지 시나리오",
                              subtitle: "사진을 누르면 크게 볼 수 있어요")
            ForEach(list) { s in
                Card {
                    HStack(spacing: 10) {
                        Text(s.id).font(.headline.monospacedDigit()).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 9).fill(s.color))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.headline)
                            Label(s.tab, systemImage: s.symbol).font(.caption).foregroundStyle(s.color)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(s.points, id: \.self) { p in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(s.color).frame(width: 5, height: 5).padding(.top, 6)
                                    Text(p).font(.footnote)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            ForEach(s.shots.prefix(2)) { shot in
                                Button { zoom = shot } label: { ShotThumb(shot: shot) }
                                    .buttonStyle(.plain)
                                    .frame(width: 62)
                            }
                        }
                    }
                    if s.shots.count > 2 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(s.shots.dropFirst(2)) { shot in
                                    Button { zoom = shot } label: {
                                        Label(shot.caption, systemImage: "photo").font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 4. 구조

private struct ArchitectureSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "03  어떻게 생겼나", title: "전체 구조",
                              subtitle: "데이터 → Context → 판단 → 행동, 그리고 피드백으로 다시 학습")
            Card {
                layer("입력", [("수면 (단축어)", "heart.text.square", .pink), ("캘린더", "calendar", .red),
                                ("노션 할 일", "checklist", .gray), ("사용자 설정", "person.fill", .brown)])
                DownArrow(label: "모아서 정리")
                layer("Context", [("장기\n습관·목표", "clock.arrow.circlepath", .indigo),
                                  ("일일\n기분·피로", "calendar.day.timeline.left", .indigo),
                                  ("실시간\n지금 시각·화면", "bolt.fill", .indigo)])
                DownArrow(label: "이벤트가 생기면")
                layer("판단 (REASON)", [("규칙\n즉시·무료", "list.bullet.rectangle", .green),
                                         ("Jev\n빠른 판단", "bolt.horizontal.circle", .teal),
                                         ("Claude\n자세한 글", "sparkles", .purple)])
                DownArrow(label: "안전장치 (GUARD)")
                layer("행동 (ACT)", [("추천", "lightbulb.fill", .orange), ("알림", "bell.fill", .orange),
                                     ("알람", "alarm.fill", .orange), ("음성", "speaker.wave.2.fill", .orange)])
                HStack {
                    Image(systemName: "arrow.uturn.up").foregroundStyle(.pink)
                    Text("피드백 (좋아요·별로예요, 실제로 잔 시간) → 다음 판단에 반영")
                        .font(.caption).foregroundStyle(.pink)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    private func layer(_ name: String, _ items: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 3) {
                        Image(systemName: item.1).font(.body)
                        Text(item.0).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(item.2)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 10).fill(item.2.opacity(0.12)))
                }
            }
        }
    }
}

// MARK: - 5. 동작 방식 (예시로 따라가기)

private struct DecisionFlowSection: View {
    private struct Example: Identifiable {
        let id: String
        let symbol: String
        let steps: [(String, String)]     // (단계, 설명)
        let path: ReasonPath
    }

    private let examples: [Example] = [
        Example(id: "밤 11시 10분, 휴대폰 18번째", symbol: "iphone", steps: [
            ("EVENT", "취침 20분 전인데 오늘 화면 켬이 18번 (목표 10번)"),
            ("REASON", "Jev: 지금 말을 걸까? → 예 92% · 말투: 단호하게 · 권할 것: 취침 모드"),
            ("GUARD", "오늘 이미 2번 알렸나? 방해 금지 시간인가? → 통과"),
            ("ACT", "“목표를 넘었어요. 취침 모드를 켜고 휴대폰을 내려놓아 볼까요?”"),
        ], path: .light),
        Example(id: "아침 7시, 수면 기록 도착", symbol: "sunrise.fill", steps: [
            ("EVENT", "단축어로 어젯밤 기록을 가져옴: 4시간 35분, 평소보다 2시간 17분 적음"),
            ("REASON", "규칙: 수면 부족 → Claude 요약 필요 · Claude가 요약과 추천 3개 작성"),
            ("GUARD", "숫자만 보내고 개인 정보는 보내지 않음 · 진단 표현 금지"),
            ("ACT", "홈에 요약 카드 + 30초 음성 브리핑"),
        ], path: .llm),
        Example(id: "오후, 연속 회의 3개", symbol: "calendar", steps: [
            ("EVENT", "오늘 1시~4시 회의가 쉬는 시간 없이 이어짐 + 어젯밤 수면 부족"),
            ("REASON", "규칙: 컨디션 곡선이 가장 낮은 시간과 겹침 → 사이에 15분 휴식 제안"),
            ("GUARD", "회사·수업 같은 고정 일정은 옮기지 않음 · 사용자 승인 전에는 바꾸지 않음"),
            ("ACT", "오늘 탭에 ‘이 일정 30분 미루기’ 제안 카드 → 승인하면 캘린더 수정"),
        ], path: .rule),
    ]

    @State private var selected = 0
    @State private var step = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "04  어떻게 움직이나", title: "EVENT → REASON → GUARD → ACT",
                              subtitle: "모든 기능은 이 네 단계를 거쳐요. 예시를 골라 따라가 보세요")
            Picker("예시", selection: $selected) {
                ForEach(examples.indices, id: \.self) { i in Text(shortName(i)).tag(i) }
            }
            .pickerStyle(.segmented)
            .onChange(of: selected) { _, _ in play() }

            let ex = examples[selected]
            Card {
                Label(ex.id, systemImage: ex.symbol).font(.subheadline.bold())
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Text(s.0).font(.system(size: 9, weight: .heavy))
                                .frame(width: 58, height: 24)
                                .background(Capsule().fill(color(i).opacity(i <= step ? 1 : 0.18)))
                                .foregroundStyle(i <= step ? .white : .secondary)
                            if i < ex.steps.count - 1 {
                                Rectangle().fill(color(i).opacity(i < step ? 0.6 : 0.15)).frame(width: 2, height: 22)
                            }
                        }
                        Text(s.1).font(.footnote)
                            .foregroundStyle(i <= step ? .primary : .tertiary)
                            .padding(.top, 4)
                    }
                    .animation(.easeOut(duration: 0.3), value: step)
                }
                HStack {
                    Text("판단 경로: \(ex.path.rawValue)").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.indigo.opacity(0.12)))
                    Spacer()
                    Button { play() } label: { Label("다시 보기", systemImage: "play.fill").font(.caption) }
                }
            }
        }
    }

    private func shortName(_ i: Int) -> String { ["취침 전", "아침 요약", "낮 일정"][i] }

    private func color(_ i: Int) -> Color { [Color.orange, .indigo, .pink, .green][i] }

    private func play() {
        step = -1
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 * Double(i + 1)) { step = i }
        }
    }
}

// MARK: - 6. 하이브리드 AI

private struct HybridAISection: View {
    private struct Tier: Identifiable {
        let id: String
        let ms: Double
        let color: Color
        let role: String
        let example: String
    }

    // 2026-11-15 라이브 테스트 실측값 (CI 시뮬레이터)
    private let tiers: [Tier] = [
        Tier(id: "규칙", ms: 1, color: .green, role: "확실한 경우 즉시 결정", example: "수면 5시간 미만 → 요약 필요"),
        Tier(id: "Jev", ms: 74, color: .teal, role: "애매한 짧은 판단 (예/아니오·선택·점수)", example: "지금 말을 걸까? 이 할 일은 집중 작업일까?"),
        Tier(id: "Claude", ms: 3500, color: .purple, role: "자연스러운 글이 필요할 때만", example: "아침 요약 · 추천 3개 · 음성 원고"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "05  AI를 어떻게 쓰나", title: "규칙 → Jev → Claude",
                              subtitle: "빠르고 싼 판단부터 먼저, 필요할 때만 큰 모델을 불러요")
            Card {
                Text("응답 시간 (밀리초, 로그 눈금)").font(.caption.bold()).foregroundStyle(.secondary)
                Chart(tiers) { t in
                    // 로그 눈금은 0에서 시작할 수 없으므로 0.5ms부터 그린다
                    BarMark(xStart: .value("시작", 0.5), xEnd: .value("응답 시간", max(t.ms, 2)),
                            y: .value("단계", t.id))
                        .foregroundStyle(t.color.gradient)
                        .annotation(position: .trailing) {
                            Text(t.ms < 10 ? "즉시" : t.ms < 1000 ? "\(Int(t.ms))ms" : String(format: "%.1f초", t.ms / 1000))
                                .font(.caption2.bold())
                        }
                }
                .chartXScale(domain: 0.5...20000, type: .log)
                .chartXAxis(.hidden)
                .frame(height: 130)
                ForEach(tiers) { t in
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(t.color).frame(width: 6, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(t.id) — \(t.role)").font(.footnote.bold())
                            Text(t.example).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                HStack(spacing: 14) {
                    stat("14/14", "Jev 할 일 분류 정확도")
                    stat("±2%p", "같은 질문 5번 반복 시 차이")
                    stat("86/86", "실제 API 라이브 테스트")
                }
                Text("Jev나 Claude에 연결이 안 되면 규칙으로 계속 동작해요.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.indigo)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 7. 하루의 흐름

private struct DayRhythmSection: View {
    private struct Span: Identifiable {
        let id: String
        let start: Double   // 시 (6 = 오전 6시, 30 = 다음 날 오전 6시)
        let end: Double
        let color: Color
    }

    private let spans: [Span] = [
        Span(id: "05 아침 요약·음성", start: 7, end: 8, color: .teal),
        Span(id: "01 오늘 추천·일정", start: 8, end: 21, color: .orange),
        Span(id: "02 취침 준비", start: 21.5, end: 23.5, color: .purple),
        Span(id: "04 내일 알람 계산", start: 22, end: 23, color: .blue),
        Span(id: "수면", start: 23.5, end: 31, color: .indigo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "06  하루 동안", title: "언제 무엇이 움직이나",
                              subtitle: "어젯밤의 수면이 오늘을, 오늘의 일정이 오늘 밤을 정해요")
            Card {
                Chart(spans) { s in
                    BarMark(xStart: .value("시작", s.start), xEnd: .value("끝", min(s.end, 30)),
                            y: .value("기능", s.id))
                        .foregroundStyle(s.color.gradient)
                        .cornerRadius(5)
                }
                .chartXScale(domain: 6...30)
                .chartXAxis {
                    AxisMarks(values: [6, 9, 12, 15, 18, 21, 24, 27, 30]) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let h = v.as(Double.self) { Text("\(Int(h) % 24)시").font(.system(size: 9)) }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 190)
                Text("수면 기록은 아침에 단축어로 가져오고, 저녁에는 지금 시각과 화면 사용을 실시간으로 봐요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 8. 데이터와 개인정보

private struct PrivacySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "07  데이터는 어디로", title: "개인정보를 지키는 방식",
                              subtitle: "원본 수면 기록은 아이폰 밖으로 나가지 않아요")
            Card {
                row("iphone", .green, "아이폰 안에만", "수면 원본 기록 · 캘린더 · 피드백 · API 키(키체인)")
                row("sparkles", .purple, "Claude로 보내는 것", "수면 시간·단계 비율 같은 집계 숫자만 (이름·일정 내용 없음)")
                row("bolt.horizontal.circle", .teal, "Jev로 보내는 것", "판단에 필요한 짧은 상태 · 할 일 제목은 설정에서 끌 수 있음")
                row("checklist", .gray, "노션", "오늘·내일 할 일만 읽기 전용 · 노션에 쓰지 않음")
                row("hand.raised.fill", .orange, "사용자 승인", "일정 이동·알람 설정은 승인해야만 실행")
            }
        }
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.bold())
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 9. 만드는 방법

private struct PipelineSection: View {
    private let steps: [(String, String, String)] = [
        ("Linux + Claude", "chevron.left.forwardslash.chevron.right", "코드 작성"),
        ("GitHub", "arrow.triangle.branch", "푸시"),
        ("Actions (macOS)", "hammer.fill", "빌드·테스트"),
        ("IPA (암호 zip)", "lock.doc.fill", "다운로드"),
        ("Sideloadly", "cable.connector", "설치"),
        ("iPhone 12 Pro", "iphone", "실행"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionTitle(number: "08  어떻게 만들었나", title: "Mac 없이 만드는 iOS 앱",
                              subtitle: "무료 Apple ID + GitHub Actions의 가상 Mac으로 빌드")
            Card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        VStack(spacing: 4) {
                            ZStack(alignment: .topLeading) {
                                Image(systemName: s.1).font(.title3).foregroundStyle(.indigo)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.indigo.opacity(0.12)))
                                Text("\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 15, height: 15).background(Circle().fill(.indigo)).offset(x: -5, y: -5)
                            }
                            Text(s.0).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                            Text(s.2).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                HStack(spacing: 14) {
                    stat("222", "셀프 테스트\n(더미 데이터)")
                    stat("86", "실제 API\n라이브 테스트")
                    stat("매 푸시", "자동 빌드\n+ 스크린샷")
                }
                Text("HealthKit은 유료 계정이 필요해서, 건강 앱의 수면 기록은 단축어로 가져와요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline).foregroundStyle(.indigo)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GuideFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.indigo)
            Text("잘 자는 것은 내일의 나를 아끼는 일").font(.footnote.weight(.semibold))
            Text("이정한 · 평택대학교 AI융합대학원 · 2026").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
