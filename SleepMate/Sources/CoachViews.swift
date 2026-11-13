import SwiftUI

// MARK: - 홈 화면 요약 카드

struct CoachCard: View {
    @Environment(SleepStore.self) private var store
    @Environment(CoachStore.self) private var coach
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("오늘의 수면 코치", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if let r = coach.report {
                    Text(r.source == .claude ? "Claude" : "기본 분석")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(r.source == .claude
                                                   ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2)))
                }
            }

            if coach.isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Claude가 요약하는 중…").font(.callout).foregroundStyle(.secondary)
                }
            }

            if let r = coach.report {
                Text(r.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("오늘 이렇게 해 보세요")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(r.recommendations.enumerated()), id: \.offset) { i, rec in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                            Text(rec)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if !coach.isGenerating {
                Text("수면 기록을 가져오면 요약과 추천이 나타납니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if let err = coach.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    if coach.speech.isSpeaking { coach.stopSpeaking() } else { coach.speak() }
                } label: {
                    Label(coach.speech.isSpeaking ? "정지" : "읽어주기",
                          systemImage: coach.speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coach.report == nil)

                Button {
                    if coach.hasKey {
                        Task { await coach.generateWithClaude(nights: store.nights) }
                    } else {
                        showSettings = true
                    }
                } label: {
                    Label("Claude 요약", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(coach.isGenerating || store.nights.isEmpty)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            Text("의료 진단이 아닌 생활 습관 참고용입니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
        }
    }
}

// MARK: - AI 요약 설정

struct CoachSettingsView: View {
    @Environment(CoachStore.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var customModel = ""

    var body: some View {
        @Bindable var coach = coach
        NavigationStack {
            Form {
                Section {
                    if coach.hasKey {
                        Label("API 키 저장됨", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("키 삭제", role: .destructive) { coach.deleteKey() }
                    } else {
                        SecureField("sk-ant-api03-…", text: $keyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button("저장") {
                            coach.saveKey(keyInput)
                            keyInput = ""
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Claude API 키")
                } footer: {
                    Text("console.anthropic.com → API Keys에서 발급합니다. Claude 구독(Pro/Max)과는 별개인 사용량 기반 결제이며, 요약 1회에 드는 비용은 매우 적습니다. 키는 이 아이폰의 키체인에만 저장됩니다.")
                }

                Section {
                    Picker("모델", selection: $coach.settings.model) {
                        ForEach(CoachSettings.presets, id: \.id) { p in
                            Text(p.label).tag(p.id)
                        }
                        if !CoachSettings.presets.contains(where: { $0.id == coach.settings.model }) {
                            Text(coach.settings.model).tag(coach.settings.model)
                        }
                    }
                    HStack {
                        TextField("직접 입력 (예: claude-haiku-5-5)", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button("적용") {
                            let m = customModel.trimmingCharacters(in: .whitespaces)
                            if !m.isEmpty { coach.settings.model = m }
                            customModel = ""
                        }
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("모델")
                }

                Section {
                    Toggle("가져온 뒤 Claude로 자동 요약", isOn: $coach.settings.autoClaude)
                    Toggle("가져온 뒤 자동으로 읽어주기", isOn: $coach.settings.autoSpeak)
                    VStack(alignment: .leading) {
                        Text("읽기 속도")
                        Slider(value: $coach.settings.speechRate, in: 0.35...0.6) {
                            Text("읽기 속도")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    Button("음성 테스트") {
                        coach.speech.speak("안녕하세요. 슬립메이트입니다. 오늘도 좋은 하루 보내세요.",
                                           rate: coach.settings.speechRate)
                    }
                } header: {
                    Text("자동 실행")
                } footer: {
                    Text("단축어 자동화(예: 알람을 끌 때)와 함께 켜 두면, 아침에 앱이 열리면서 바로 요약을 읽어 줍니다. 무음 모드에서도 소리가 납니다.")
                }

                Section {
                    Text("Claude에는 지난밤·최근 7일의 요약 수치(총 수면, 단계별 분, 취침·기상 시각, 평균)만 보냅니다. 구간별 원본 기록이나 이름 같은 개인정보는 보내지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("개인정보")
                }
            }
            .navigationTitle("AI 요약 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .onChange(of: coach.settings) { _, new in new.save() }
        }
    }
}
