import AVFoundation
import Foundation
import Observation

// MARK: - 음성 (iPhone 내장 한국어 TTS)

@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, rate: Double) {
        stop()
        // 무음 스위치가 켜져 있어도 들리도록 .playback, 다른 소리는 잠시 줄임
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = Float(min(max(rate, 0.3), 0.65))
        u.pitchMultiplier = 1.0
        u.postUtteranceDelay = 0.1
        isSpeaking = true
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    private func finished() {
        DispatchQueue.main.async {
            self.isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { finished() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { finished() }
}

// MARK: - 수면 코치 (요약·추천·음성)

@MainActor
@Observable
final class CoachStore {
    private let log = AppLog.shared
    private static let cacheKey = "lastSleepReport"

    var report: SleepReport?
    var isGenerating = false
    var errorMessage: String?
    var settings = CoachSettings.load()   // 변경 후 저장은 설정 화면에서 settings.save()
    var hasKey: Bool = KeyStore.load() != nil
    let speech = SpeechService()

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.cacheKey),
           let r = try? JSONDecoder().decode(SleepReport.self, from: d) {
            report = r
        }
    }

    /// 수면 기록이 바뀌었을 때 호출. fromImport=true면 설정에 따라 Claude 요약·자동 읽기까지.
    func update(nights: [SleepNight], fromImport: Bool, persist: Bool = true) async {
        guard let stats = SleepStats(nights: nights) else {
            report = nil
            return
        }
        // 같은 밤의 Claude 요약이 이미 있고 새로 가져온 게 아니면 그대로 둔다.
        if !fromImport, let r = report, r.day == stats.day { return }

        setReport(RuleReporter.make(stats), persist: persist)
        log.add("기본 요약 생성: \(Fmt.day.string(from: stats.day))")

        guard fromImport else { return }
        if settings.autoClaude && hasKey {
            await generateWithClaude(nights: nights)
        }
        if settings.autoSpeak {
            speak()
        }
    }

    func generateWithClaude(nights: [SleepNight]) async {
        guard let stats = SleepStats(nights: nights) else {
            errorMessage = "요약할 수면 기록이 없습니다."
            return
        }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        log.add("Claude 요약 요청 (\(settings.model))")
        do {
            let r = try await ClaudeClient.report(for: stats, model: settings.model)
            setReport(r)
            log.add("Claude 요약 완료")
        } catch {
            errorMessage = error.localizedDescription
            log.add("Claude 요약 실패: \(error)")
        }
    }

    /// 기본 분석으로 되돌리기
    func regenerateRules(nights: [SleepNight]) {
        guard let stats = SleepStats(nights: nights) else { return }
        setReport(RuleReporter.make(stats))
    }

    func speak() {
        guard let r = report else { return }
        log.add("음성 읽기 시작")
        speech.speak(r.speech, rate: settings.speechRate)
    }

    func stopSpeaking() { speech.stop() }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeyStore.delete()
        } else {
            let ok = KeyStore.save(trimmed)
            log.add(ok ? "API 키 저장 (키체인)" : "API 키 저장 (키체인 실패 → 앱 설정에 저장)")
        }
        hasKey = KeyStore.load() != nil
    }

    func deleteKey() {
        KeyStore.delete()
        hasKey = false
        log.add("API 키 삭제")
    }

    func clear() {
        report = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    private func setReport(_ r: SleepReport, persist: Bool = true) {
        report = r
        guard persist else { return }
        if let d = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(d, forKey: Self.cacheKey)
        }
    }
}
