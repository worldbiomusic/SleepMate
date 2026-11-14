import SwiftUI

/// 설정 → 테스트 · 더미 데이터
struct TestLabView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx
    @Environment(CalendarService.self) private var calendar
    @State private var lab = TestLab.shared

    var body: some View {
        Form {
            Section {
                if lab.isOn {
                    Label("테스트 모드 켜짐 — 실제 기록은 그대로 보관 중", systemImage: "testtube.2")
                        .foregroundStyle(.orange)
                } else {
                    Text("시나리오별 더미 데이터를 넣어 기능을 확인해요. 실제 수면 기록·캘린더·설정은 바뀌지 않고, 테스트 중 ‘적용’한 일정 변경도 가짜로만 처리돼요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("수면 기록", selection: $lab.sleep) {
                    ForEach(SleepPreset.allCases) { Text($0.rawValue).tag($0) }
                }
            } header: {
                Text("홈 · 05 수면 요약")
            } footer: {
                Text(sleepHint(lab.sleep))
            }

            Section {
                Picker("오늘 일정", selection: $lab.today) {
                    ForEach(DayPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("피로도", selection: $lab.fatigue) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("기분", selection: $lab.mood) {
                    Text("없음").tag(Mood?.none)
                    ForEach(Mood.allCases) { Text("\($0.emoji) \($0.rawValue)").tag(Mood?.some($0)) }
                }
            } header: {
                Text("오늘 · 01 행동·일정 추천")
            } footer: {
                Text("수면 부족이나 피로도 4 이상이면 ‘일정 조정안’이 나와요. ‘오전 집중 작업 + 수업’에서 집중 작업만 오후로 옮겨지는지 확인해 보세요.")
            }

            Section {
                Stepper("화면 기록 \(lab.screenCount)개", value: $lab.screenCount, in: 0...150, step: 5)
                Picker("시각", selection: $lab.clock) {
                    ForEach(TestLab.ClockMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("취침 준비 · 02  /  공통 시각")
            } footer: {
                Text("‘밤 22:40’으로 두면 취침 준비 단계(목표 확인~준비 시작 사이)를 낮에도 확인할 수 있어요. ‘아침 07:30’은 오늘 일정 추천용입니다.")
            }

            Section {
                Picker("내일 일정", selection: $lab.tomorrow) {
                    ForEach(DayPreset.allCases) { Text($0.rawValue).tag($0) }
                }
            } header: {
                Text("알람 · 04 기상 알람")
            } footer: {
                Text("‘아침 7시 일정’이면 최소 기상 시각(설정)에 맞춰 조정되는지, ‘일정 없음’이면 평소 기상 시각이 쓰이는지 확인해 보세요.")
            }

            Section {
                Button {
                    lab.apply(store: store, ctx: ctx, calendar: calendar)
                } label: {
                    Label(lab.isOn ? "바꾼 설정으로 다시 적용" : "테스트 모드 시작", systemImage: "play.circle.fill")
                        .font(.body.weight(.semibold))
                }
                if lab.isOn {
                    Button(role: .destructive) {
                        lab.exit(store: store, ctx: ctx, calendar: calendar)
                    } label: {
                        Label("테스트 모드 끝내기 (실제 기록으로)", systemImage: "stop.circle")
                    }
                }
            }

            Section {
                NavigationLink {
                    SelfTestView()
                } label: {
                    Label("셀프 테스트 실행", systemImage: "checklist")
                }
            } footer: {
                Text("더미 데이터로 가져오기·점수·추천·일정 조정·알람·알림 규칙 등 핵심 기능을 자동으로 검사해요. 실제 데이터는 건드리지 않아요.")
            }
        }
        .navigationTitle("테스트 · 더미 데이터")
    }

    private func sleepHint(_ p: SleepPreset) -> String {
        switch p {
        case .good: return "점수 80점 이상, ‘지금 리듬 유지’ 추천이 나와야 해요."
        case .short: return "점수 70점 미만(부족), 카페인·낮잠·일찍 자기 추천과 일정 조정안이 나와야 해요."
        case .fragmented: return "‘깨어 있던 시간이 길었어요’와 화면 멀리하기 추천이 나와야 해요."
        case .irregular: return "규칙성 점수가 낮고 ‘매일 비슷한 시각에 잠들기’ 추천이 나와야 해요."
        case .withNap: return "낮잠이 밤잠과 따로 계산돼야 해요 (취침→기상 시각이 밤잠 기준)."
        case .noStages: return "단계 차트 대신 ‘단계 데이터 없음’ 안내가 나와야 해요."
        case .duplicated: return "워치 기록만 써서 시간이 두 번 더해지지 않아야 해요."
        case .stale: return "‘최근 기록이 5일 전’이라는 안내가 먼저 나와야 해요."
        case .empty: return "‘판단하기 어려워요’ 안내가 나오고 추측하지 않아야 해요."
        }
    }
}

/// 모든 탭 위에 표시되는 테스트 모드 띠
struct TestModeBanner: View {
    @State private var lab = TestLab.shared

    var body: some View {
        if lab.isOn {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2")
                Text("테스트 모드 · \(lab.sleep.rawValue)")
                    .lineLimit(1)
                if let t = lab.simulatedNow {
                    Text("· \(Fmt.time.string(from: t))")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.orange))
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }
}
