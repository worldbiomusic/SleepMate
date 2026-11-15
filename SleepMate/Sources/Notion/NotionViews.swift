import SwiftUI

/// 오늘 탭: 노션 할 일 + 추천 시간대
struct NotionTasksSection: View {
    let items: [PlanItem]          // 오늘 일정 (빈 시간 계산용)
    let curve: [EnergyModel.Point]
    @State private var notion = NotionStore.shared

    var body: some View {
        Section {
            if !notion.isConfigured && !TestLab.shared.isOn {
                NavigationLink {
                    NotionSettingsView()
                } label: {
                    Label("노션 할 일 연결하기", systemImage: "link.badge.plus")
                }
                Text("노션 ‘할 일’ 페이지를 연결하면 오늘 할 일을 컨디션에 맞는 시간대에 배치해 드려요.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let list = notion.tasks(on: AppClock.now)
                if list.isEmpty {
                    Text(notion.syncing ? "불러오는 중…" : "오늘 할 일이 없어요.").foregroundStyle(.secondary)
                }
                ForEach(list) { t in
                    NotionTaskRow(task: t, slot: slot(for: t))
                }
                if let e = notion.error {
                    Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            }
        } header: {
            HStack {
                Text("노션 할 일")
                Spacer()
                if notion.isConfigured {
                    Button {
                        Task { await notion.sync() }
                    } label: {
                        Label(notion.lastSync.map { "동기화 \(Fmt.time.string(from: $0))" } ?? "동기화",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .disabled(notion.syncing)
                }
            }
        } footer: {
            if notion.isConfigured || TestLab.shared.isOn {
                Text("집중이 필요한 일은 컨디션이 높은 때, 가벼운 일·볼일은 낮은 때로 추천해요. 분류는 Jev(연결 시) 또는 키워드 규칙으로 해요.")
            }
        }
        .task {
            if notion.isConfigured, notion.lastSync.map({ Date().timeIntervalSince($0) > 600 }) ?? true {
                await notion.sync()
            }
        }
    }

    private func slot(for t: NotionTask) -> Date? {
        guard !t.done, t.time == nil, let c = t.cls else { return nil }
        return NotionParse.suggestedSlot(for: c, items: items, curve: curve, day: AppClock.now, now: AppClock.now)
    }
}

struct NotionTaskRow: View {
    let task: NotionTask
    let slot: Date?

    var body: some View {
        let c = task.cls ?? JevDecisions.classifyRuleNonisolated(task.title)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.done ? "checkmark.square.fill" : "square")
                .foregroundStyle(task.done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label(c.kind.label, systemImage: c.kind.symbol)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                    FocusDots(level: c.focus)
                    if c.path == .light {
                        Text("Jev").font(.system(size: 9, weight: .bold)).foregroundStyle(.teal)
                    }
                }
                if let time = task.time {
                    Label(Fmt.time.string(from: time), systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                } else if let s = slot {
                    Label("추천 \(Fmt.time.string(from: s)) · \(c.focus >= 2 ? "컨디션 높을 때" : (c.focus == 0 ? "가볍게 처리" : "빈 시간"))",
                          systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 집중 필요도 ●●○
struct FocusDots: View {
    let level: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(i <= level ? Color.orange : Color.gray.opacity(0.25)).frame(width: 6, height: 6)
            }
            Text(["집중 낮음", "집중 보통", "집중 높음"][min(2, max(0, level))]).font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

/// 설정 → 노션 연결
struct NotionSettingsView: View {
    @State private var notion = NotionStore.shared
    @State private var tokenInput = ""
    @State private var linkInput = NotionStore.shared.link

    var body: some View {
        Form {
            Section {
                NotionStepRow(n: 1, title: "통합 만들기",
                              detail: "notion.so/profile/integrations → ‘새 API 통합’ → 이름 SleepMate, 유형 ‘내부’ → 저장 → ‘내부 통합 시크릿’ 복사")
                NotionStepRow(n: 2, title: "할 일 페이지에 연결",
                              detail: "노션 ‘할 일’ 페이지 오른쪽 위 ⋯ → 연결(Connections) → SleepMate 추가")
                NotionStepRow(n: 3, title: "페이지 링크 복사",
                              detail: "같은 메뉴에서 ‘링크 복사’ → 아래 칸에 붙여넣기")
                NotionStepRow(n: 4, title: "시크릿 붙여넣기 → 동기화",
                              detail: "시크릿은 이 아이폰 키체인에만 저장돼요")
            } header: {
                Text("연결 방법 (한 번만)")
            }

            Section {
                TextField("https://www.notion.so/…", text: $linkInput, axis: .vertical)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { notion.setLink(linkInput) }
                if !linkInput.isEmpty && NotionParse.id(fromLink: linkInput) == nil {
                    Text("링크에서 페이지 ID를 찾지 못했어요.").font(.caption).foregroundStyle(.orange)
                }
                if notion.hasToken {
                    Label("시크릿 저장됨", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Button("시크릿 삭제", role: .destructive) { notion.clearToken() }
                } else {
                    SecureField("ntn_… 시크릿", text: $tokenInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button {
                    notion.setLink(linkInput)
                    if !tokenInput.isEmpty {
                        notion.setToken(tokenInput)
                        tokenInput = ""
                    }
                    Task { await notion.sync() }
                } label: {
                    HStack {
                        Label("저장하고 동기화", systemImage: "arrow.triangle.2.circlepath")
                        if notion.syncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(NotionParse.id(fromLink: linkInput) == nil || (!notion.hasToken && tokenInput.isEmpty))
                if let e = notion.error {
                    Text(e).font(.footnote).foregroundStyle(.orange)
                } else if let t = notion.lastSync {
                    Text("\(notion.mode ?? "") 방식 · \(Fmt.time.string(from: t)) 동기화 · 오늘·내일 할 일 \(notion.tasks.count)개")
                        .font(.footnote).foregroundStyle(.green)
                }
            } header: {
                Text("연결")
            }

            Section {
                Label("‘11/16 월’ 같은 날짜 제목 아래 체크박스", systemImage: "checklist")
                Label("체크박스 안 날짜 멘션(@11월 26일 오후 1:20)은 그 시각으로", systemImage: "clock")
                Label("취소선 항목은 제외 · 체크된 항목은 완료로 표시", systemImage: "strikethrough")
                Label("날짜 속성이 있는 데이터베이스도 지원", systemImage: "tablecells")
            } header: {
                Text("읽는 방식")
            } footer: {
                Text("오늘·내일 할 일만 읽고 노션에 쓰지는 않아요. 시각이 있는 할 일은 타임라인과 기상 알람 계산에도 들어가요.")
            }
        }
        .font(.callout)
        .navigationTitle("노션 연결")
    }
}

private struct NotionStepRow: View {
    let n: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
