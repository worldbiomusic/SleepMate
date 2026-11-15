import SwiftUI

/// 설정 → Jev (빠른 판단 AI)
struct JevSettingsView: View {
    @State private var config = JevConfig.load()
    @State private var keyInput = ""
    @State private var hasKey = JevClient.isConfigured
    @State private var testResult: String?
    @State private var testing = false
    @State private var log = AgentLog.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Jev는 글을 쓰지 않고 ‘판단’만 하는 빠른 AI예요. 아이폰 12 Pro에서 못 쓰는 온디바이스 AI 대신, 작은 판단을 빠르게 맡깁니다.")
                        .font(.footnote)
                    JevFlowDiagram()
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("제공처", selection: $config.provider) {
                    ForEach(JevConfig.Provider.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: config.provider) { _, p in
                    if p != .custom {
                        config.url = p.defaultURL
                        config.model = p.defaultModel
                    }
                }
                LabeledContent("주소") {
                    TextField("https://…/v1/systemone", text: $config.url)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                LabeledContent("모델") {
                    TextField("jev-latest", text: $config.model)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if hasKey {
                    Label("API 키 저장됨 (이 아이폰 키체인)", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Button("키 삭제", role: .destructive) {
                        SecretStore.delete(JevClient.keyAccount)
                        hasKey = false
                    }
                } else {
                    SecureField("API 키 붙여넣기", text: $keyInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("저장") {
                        SecretStore.save(keyInput, JevClient.keyAccount)
                        keyInput = ""
                        hasKey = JevClient.isConfigured
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    testing = true
                    Task {
                        config.save()
                        testResult = await JevDecisions.ping()
                        testing = false
                    }
                } label: {
                    HStack {
                        Text("연결 테스트")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(!hasKey || testing)
                if let r = testResult {
                    Text(r).font(.footnote).foregroundStyle(r.hasPrefix("연결 성공") ? .green : .orange)
                }
            } header: {
                Text("연결")
            } footer: {
                Text("키 발급: \(config.provider.keyHint). 키는 GitHub나 채팅에 올리지 말고 여기에만 넣어 주세요.")
            }

            Section {
                Toggle(isOn: $config.useWindDown) {
                    labelRow("① 취침 전 한마디", "지금 말을 걸지 · 말투 · 권할 행동", "02")
                }
                Toggle(isOn: $config.useTasks) {
                    labelRow("② 노션 할 일 분류", "약속/집중/가벼운 일/볼일 · 집중 필요도", "01")
                }
                Toggle(isOn: $config.useSound) {
                    labelRow("③ 오늘 밤 소리", "기분·피로도에 맞는 수면 사운드", "02")
                }
                Toggle(isOn: $config.useLLMGate) {
                    labelRow("④ Claude 호출 여부", "평범한 날은 Claude 생략 (비용 절감)", "05")
                }
            } header: {
                Text("Jev가 맡는 판단")
            } footer: {
                Text("②를 켜면 오늘·내일 할 일 제목이 Jev로 전송돼요. 끄거나 키가 없으면 앱 안의 규칙으로 같은 판단을 해요.")
            }

            Section {
                let jev = log.entries.filter { $0.path == .light }.prefix(8)
                if jev.isEmpty {
                    Text("아직 Jev 판단 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(jev)) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.action).font(.footnote)
                        Text("\(e.event) · \(Fmt.time.string(from: e.date))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("최근 Jev 판단")
            }
        }
        .navigationTitle("Jev · 빠른 판단 AI")
        .onChange(of: config) { _, c in c.save() }
    }

    private func labelRow(_ title: String, _ sub: String, _ scenario: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                Text(scenario).font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.teal.opacity(0.2)))
            }
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 규칙 → Jev → Claude 판단 흐름 그림
struct JevFlowDiagram: View {
    var body: some View {
        HStack(spacing: 6) {
            node("규칙", "즉시 · 무료", .gray)
            arrow
            node("Jev", "빠른 판단", .teal)
            arrow
            node("Claude", "긴 요약", .orange)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
    }

    private func node(_ t: String, _ s: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.caption.weight(.bold))
            Text(s).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.18)))
    }
}
