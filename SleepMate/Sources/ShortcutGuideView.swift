import SwiftUI

/// 앱 안에서 보는 단축어 설정 요약 (자세한 버전은 저장소의 docs/shortcut-guide.md)
struct ShortcutGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(title: "새 단축어 만들기",
             detail: "단축어 앱 → 오른쪽 위 + → 이름을 정확히 「\(SleepStore.shortcutName)」으로 지정"),
        Step(title: "건강 샘플 찾기",
             detail: "동작 검색에 '건강 샘플 찾기' → 유형: 수면 분석 → 필터 추가: 시작 날짜 · 지난 · 14일 → 정렬: 시작 날짜, 오래된 항목부터 → 제한: 끔"),
        Step(title: "각 항목을 반복",
             detail: "'각 항목을 반복' 추가 (입력: 건강 샘플)"),
        Step(title: "반복 안에 '텍스트'",
             detail: "반복 항목의 시작 날짜 | 종료 날짜 | 값 | 소스  를 순서대로 넣기. 날짜는 탭해서 형식을 ISO 8601로 (시간 포함 켬). 구분자는 세로 막대 |"),
        Step(title: "텍스트 결합",
             detail: "반복 끝 아래에 '텍스트 결합' → 입력: 반복 결과, 구분자: 새로운 줄"),
        Step(title: "클립보드에 복사",
             detail: "'클립보드에 복사' → 입력: 결합된 텍스트"),
        Step(title: "SleepMate 열기",
             detail: "'URL 열기' → URL에 sleepmate://import 입력"),
        Step(title: "처음 실행",
             detail: "▶︎ 실행 → 건강 데이터 접근 '허용' → SleepMate 열기 '열기' → 붙여넣기 '허용'"),
        Step(title: "(선택) 매일 자동 실행",
             detail: "단축어 앱 → 자동화 → + → '알람' 또는 '특정 시간' → 즉시 실행 → 「\(SleepStore.shortcutName)」 선택"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("무료 Apple ID로 설치한 앱은 HealthKit에 직접 접근할 수 없어서, Apple의 '단축어' 앱이 수면 기록을 읽어 이 앱으로 넘겨주도록 설정합니다. 한 번만 만들면 됩니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("만드는 순서") {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.callout.bold().monospacedDigit())
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.body.weight(.semibold))
                                Text(step.detail).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("한 줄 예시 (단축어가 만드는 텍스트)") {
                    Text("2026-11-13T00:12:00+09:00|2026-11-13T00:47:00+09:00|코어|Apple Watch")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    Button {
                        UIPasteboard.general.string = "sleepmate://import"
                    } label: {
                        Label("URL 복사: sleepmate://import", systemImage: "doc.on.doc")
                    }
                    Button {
                        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                    } label: {
                        Label("단축어 앱 열기", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .navigationTitle("단축어 설정 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
