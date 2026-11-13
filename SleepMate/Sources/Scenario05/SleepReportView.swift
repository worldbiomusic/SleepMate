import SwiftUI

/// 시나리오 05 확장: 수면 리포트 (추세 시각화 모음)
struct SleepReportView: View {
    @Environment(SleepStore.self) private var store
    @Environment(ContextStore.self) private var ctx

    var body: some View {
        List {
            if let s = SleepStats(nights: store.nights) {
                let sc = SleepScore.compute(s, goalMinutes: ctx.profile.goalSleepMinutes)
                Section {
                    HStack(spacing: 16) {
                        ScoreRing(score: sc.total, size: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("지난밤 \(sc.label)").font(.headline)
                            Text("점수는 시간 50 · 효율 20 · 단계 15 · 규칙성 15점으로 계산해요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ScoreComponentsChart(sc: sc)
                } header: {
                    Text("수면 점수 구성")
                }
            }

            Section {
                ScoreTrendChart(nights: store.nights, goalMinutes: ctx.profile.goalSleepMinutes)
                    .padding(.vertical, 4)
            } header: {
                Text("수면 점수 추세")
            }

            Section {
                WeekStageChart(nights: store.nights, goalMinutes: ctx.profile.goalSleepMinutes)
                    .padding(.vertical, 4)
            } header: {
                Text("단계별 수면 시간")
            }

            Section {
                BedWakeRangeChart(nights: store.nights, targetBedMinutes: ctx.profile.bedtimeMinutes)
                    .padding(.vertical, 4)
            } header: {
                Text("잠든 시각 → 깬 시각")
            } footer: {
                Text("막대 위쪽이 잠든 시각, 아래쪽이 깬 시각이에요. 막대 높이가 고를수록 리듬이 규칙적이에요.")
            }

            if let latest = store.nights.first {
                Section {
                    HypnogramChart(night: latest)
                    StageBreakdownView(night: latest)
                } header: {
                    Text("지난밤 단계 흐름 (\(Fmt.day.string(from: latest.day)))")
                }
            }
        }
        .navigationTitle("수면 리포트")
    }
}
