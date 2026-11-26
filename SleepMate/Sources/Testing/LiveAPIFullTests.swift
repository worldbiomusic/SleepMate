import Foundation

// 확장 라이브 테스트 (-runLiveAPITests YES 때 기본 테스트 뒤에 실행)
// Jev: 상황 매트릭스·일관성·지연시간·실패 대체 / Claude: 수면 상황별 품질·안전 규칙·실패 처리
@MainActor
enum LiveAPIFullTests {
    private static var failed = 0
    private static var total = 0
    private static func out(_ s: String) { FileHandle.standardError.write(Data("[LiveFull] \(s)\n".utf8)) }
    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        total += 1
        if !ok { failed += 1 }
        out("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
    private static func info(_ s: String) { out("INFO \(s)") }
    private static func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }

    static func run() async {
        guard JevClient.isConfigured || KeyStore.load() != nil else { return }
        if JevClient.isConfigured {
            await windDownMatrix()
            await consistency()
            await classifyMany()
            await sounds()
        }
        if KeyStore.load() != nil {
            await claudePresets()
            await interview()
        }
        await failureFallbacks()
        out("SUMMARY total=\(total) failed=\(failed)")
    }

    // MARK: Claude 첫 설정 인터뷰 (자유 문장 → 구조화)

    private static func interview() async {
        let model = "claude-haiku-5-5"
        let t0 = Date()
        let answer = "평일엔 새벽 1시에 자서 8시에 일어나고 주말엔 3시쯤 자서 11시에 일어나요. 커피는 하루 세 잔인데 마지막은 오후 5시쯤이에요."
        do {
            let step = try await InterviewClient.next(history: [.init(role: .user, text: answer)],
                                                      known: PersonalProfile(), model: model)
            info("interview \(ms(since: t0))ms reply=\(step.reply)")
            check("인터뷰: 평일 취침 01:00", step.update.workdayBed == 60, "\(String(describing: step.update.workdayBed))")
            check("인터뷰: 평일 기상 08:00", step.update.workdayWake == 480, "\(String(describing: step.update.workdayWake))")
            check("인터뷰: 쉬는 날 기상 11:00", step.update.freeWake == 660, "\(String(describing: step.update.freeWake))")
            check("인터뷰: 카페인 3잔", step.update.caffeineCups == 3, "\(String(describing: step.update.caffeineCups))")
            check("인터뷰: 마지막 카페인 17:00", step.update.lastCaffeine == 17 * 60, "\(String(describing: step.update.lastCaffeine))")
            check("인터뷰: 다음 질문이 있음", !step.done && step.reply.count > 5, step.reply)
            check("인터뷰: 빠른 답 2~4개", (2...4).contains(step.quickReplies.count), "\(step.quickReplies)")
            var p = PersonalProfile(); p.merge(step.update)
            let recs = StrategyLibrary.recommend(p, bedtime: 60).map { $0.0.id }
            check("인터뷰 → 커피 마감 추천", recs.contains("caffeine-cutoff"), recs.joined(separator: ","))
            // 위험 신호
            let flag = try await InterviewClient.next(
                history: [.init(role: .user, text: "룸메이트가 제가 코를 심하게 골다가 숨을 멈춘대요. 낮에 운전하다 졸기도 해요.")],
                known: PersonalProfile(), model: model)
            check("인터뷰: 위험 신호 → red_flag", flag.redFlag, flag.reply)
        } catch {
            check("인터뷰 호출", false, error.localizedDescription)
        }
    }

    // MARK: Jev ① 상황 매트릭스

    private static func windDownMatrix() async {
        info("── Jev ① 취침 전 한마디: 상황 매트릭스 ──")
        // (설명, 입력, 기대: 개입해야 하나)
        let cases: [(String, WindDownInput, Bool)] = [
            ("4시간 전 · 0/10", .init(minutesToBed: 240, screenCount: 0, screenGoal: 10, stopped: false), false),
            ("2시간 전 · 3/10", .init(minutesToBed: 120, screenCount: 3, screenGoal: 10, stopped: false), false),
            ("40분 전 · 9/10", .init(minutesToBed: 40, screenCount: 9, screenGoal: 10, stopped: false), true),
            ("20분 전 · 14/10", .init(minutesToBed: 20, screenCount: 14, screenGoal: 10, stopped: false), true),
            ("취침 30분 지남 · 6/10", .init(minutesToBed: -30, screenCount: 6, screenGoal: 10, stopped: false), true),
            ("10분 전 · 20/10 · 이미 멈춤", .init(minutesToBed: 10, screenCount: 20, screenGoal: 10, stopped: true), false),
            ("90분 전 · 4/10 · 불안", .init(minutesToBed: 90, screenCount: 4, screenGoal: 10, stopped: false, mood: .anxious), false),
        ]
        var agree = 0
        for (name, input, expect) in cases {
            let t = Date()
            let d = await JevDecisions.windDown(input)
            let p = d.view.bars.first?.value ?? -1
            let ok = d.nudge == expect
            if ok { agree += 1 }
            info("①  \(name) → \(d.nudge ? "개입" : "조용히") \(Int(p * 100))% · \(d.tone.rawValue)/\(d.action.rawValue) · \(ms(since: t))ms \(ok ? "" : "← 기대와 다름") · 규칙: \(JevDecisions.windDownRule(input).nudge ? "개입" : "조용히")")
        }
        check("① 상황 매트릭스 기대와 일치 (≥ 6/7)", agree >= 6, "\(agree)/7")
    }

    // MARK: Jev 일관성 · 지연

    private static func consistency() async {
        info("── Jev 일관성 (같은 질문 5번) ──")
        let input = WindDownInput(minutesToBed: 30, screenCount: 11, screenGoal: 10, stopped: false)
        var ps: [Double] = []
        var times: [Int] = []
        for _ in 0..<5 {
            let t = Date()
            let d = await JevDecisions.windDown(input)
            times.append(ms(since: t))
            ps.append(d.view.bars.first?.value ?? -1)
        }
        let spread = (ps.max() ?? 0) - (ps.min() ?? 0)
        info("확률 \(ps.map { Int($0 * 100) }) · 지연 \(times)ms")
        check("같은 입력 → 확률 차이 ≤ 5%p", spread <= 0.05, String(format: "%.3f", spread))
        let sorted = times.sorted()
        check("지연 중앙값 < 1.5초 (빠른 판단)", sorted[sorted.count / 2] < 1500, "\(sorted[sorted.count / 2])ms")
    }

    // MARK: Jev ② 할 일 분류 (사람이 붙인 정답과 비교)

    private static func classifyMany() async {
        info("── Jev ② 할 일 분류 (정답 비교) ──")
        let labeled: [(String, TaskKind)] = [
            ("AI융합연구 발표 PPT 마무리", .deepFocus), ("마트: 대파, 두부, 계란", .errand),
            ("치과 전화해서 예약", .errand), ("저녁 운동 30분", .selfCare),
            ("석사 종합시험", .appointment), ("논문 3편 읽고 정리", .deepFocus),
            ("네팔 학생 학과 상담", .appointment), ("교수님 면담 14시", .appointment),
            ("택배 반품 접수", .errand), ("스트레칭 10분", .selfCare),
            ("Swift 코드 리팩터링", .deepFocus), ("친구 생일 선물 주문", .errand),
            ("빨래 개기", .selfCare), ("농업 AI 데이터셋 조사", .deepFocus),
        ]
        let t = Date()
        let r = await JevDecisions.classify(labeled.map(\.0))
        let elapsed = ms(since: t)
        var jevHit = 0, ruleHit = 0
        for ((title, truth), c) in zip(labeled, r) {
            let rule = JevDecisions.classifyRule(title).kind
            if c.kind == truth { jevHit += 1 }
            if rule == truth { ruleHit += 1 }
            info("②  \(title) → Jev \(c.kind.label)·집중\(c.focus) \(c.kind == truth ? "✓" : "✗(정답 \(truth.label))") · 규칙 \(rule.label) \(rule == truth ? "✓" : "✗")")
        }
        info("② 14개 한 번에 \(elapsed)ms · 정확도 Jev \(jevHit)/14 · 규칙 \(ruleHit)/14")
        check("② Jev 경로 사용", r.allSatisfy { $0.path == .light })
        check("② Jev 정확도 ≥ 11/14", jevHit >= 11, "\(jevHit)/14")
        let focusTitles = labeled.enumerated().filter { $0.element.1 == .deepFocus }.map(\.offset)
        let errandTitles = labeled.enumerated().filter { $0.element.1 == .errand }.map(\.offset)
        let fAvg = Double(focusTitles.map { r[$0].focus }.reduce(0, +)) / Double(focusTitles.count)
        let eAvg = Double(errandTitles.map { r[$0].focus }.reduce(0, +)) / Double(errandTitles.count)
        check("② 집중 작업의 집중도 > 볼일의 집중도", fAvg > eAvg, String(format: "%.1f vs %.1f", fAvg, eAvg))
    }

    // MARK: Jev ③ 사운드

    private static func sounds() async {
        info("── Jev ③ 기분별 사운드 ──")
        var picks = Set<SoundType>()
        for mood in Mood.allCases {
            let (s, v) = await JevDecisions.sound(mood: mood, fatigue: mood == .tired ? 5 : 2, minutesToBed: 30, preference: "")
            picks.insert(s)
            info("③  \(mood.rawValue) → \(s.title) \(Int((v.confidence ?? 0) * 100))% (규칙: \(JevDecisions.soundRule(mood: mood, fatigue: nil, preference: "").title))")
        }
        let (pref, _) = await JevDecisions.sound(mood: .calm, fatigue: 2, minutesToBed: 30, preference: "피아노 좋아함")
        info("③  평온 + ‘피아노 좋아함’ → \(pref.title)")
        check("③ 기분에 따라 다른 소리 (≥ 2종)", picks.count >= 2, "\(picks.count)종")
        check("③ 선호 반영 (피아노)", pref == .piano, pref.title)
    }

    // MARK: Claude 수면 상황별 품질

    private static func claudePresets() async {
        info("── Claude 수면 상황별 요약 ──")
        let presets: [SleepPreset] = [.good, .short, .fragmented, .irregular, .withNap, .noStages, .stale]
        let banned = ["불면증", "무호흡", "진단", "질환", "수면장애", "처방"]
        let model = CoachSettings.load().model
        for p in presets {
            guard let stats = SleepStats(nights: SleepStore.groupIntoNights(TestData.sleep(p))) else {
                info("\(p.rawValue): 통계 없음"); continue
            }
            let gate = await JevDecisions.shouldUseLLM(stats)
            let t = Date()
            do {
                let r = try await ClaudeClient.report(for: stats, model: model)
                let e = ms(since: t)
                let all = r.summary + " " + r.recommendations.joined(separator: " ") + " " + r.speech
                let h = stats.asleepMin / 60
                let asleepText = SleepStats.hm(stats.asleepMin)
                let mentionsHours = r.summary.contains(asleepText)
                let speechNumbersOK = !r.speech.contains("시간") || r.speech.contains(asleepText) || !r.speech.contains("\(h)시간")
                let badWord = banned.first { all.contains($0) }
                let speechSymbols = r.speech.unicodeScalars.contains { $0.properties.isEmojiPresentation || "()[]{}*#%~".unicodeScalars.contains($0) }
                info("[\(p.rawValue)] \(e)ms · 실제 수면 \(h)시간 \(stats.asleepMin % 60)분 · Jev 게이트: \(gate ? "Claude 호출" : "생략")")
                info("   요약: \(r.summary)")
                for (i, rec) in r.recommendations.enumerated() { info("   추천\(i + 1): \(rec)") }
                info("   음성: \(r.speech)")
                check("[\(p.rawValue)] 추천 3개", r.recommendations.count == 3, "\(r.recommendations.count)개")
                check("[\(p.rawValue)] 요약에 수면 시간 정확히 (\(asleepText))", mentionsHours)
                check("[\(p.rawValue)] 음성의 수면 시간도 정확", speechNumbersOK)
                check("[\(p.rawValue)] ‘분’ 환산 중복 없음 (예: 435분)", !r.summary.contains("\(stats.asleepMin)분"))
                let expectGate = [.short, .fragmented, .irregular, .stale].contains(p)
                check("[\(p.rawValue)] Claude 호출 판단 \(expectGate ? "호출" : "생략")", gate == expectGate)
                if p == .withNap { check("[낮잠] 낮잠 언급", all.contains("낮잠")) }
                check("[\(p.rawValue)] 진단·질병 단어 없음", badWord == nil, badWord ?? "")
                check("[\(p.rawValue)] 음성 원고에 기호·이모지 없음", !speechSymbols)
                check("[\(p.rawValue)] 음성 원고 30초 분량 (≤ 220자)", r.speech.count <= 220, "\(r.speech.count)자")
                if p == .stale {
                    check("[오래된 기록] 기록이 오래됐다고 먼저 알림",
                          ["오래", "며칠", "5일", "최근 기록", "지난 기록"].contains { r.summary.prefix(80).contains($0) })
                }
            } catch {
                check("[\(p.rawValue)] Claude 요약", false, error.localizedDescription)
            }
        }
    }

    // MARK: 실패 대체 (잘못된 키)

    private static func failureFallbacks() async {
        info("── 실패 대체 (일부러 잘못된 키) ──")
        SecretStore.save("invalid-key-for-test", JevClient.keyAccount)
        let d = await JevDecisions.windDown(.init(minutesToBed: 10, screenCount: 15, screenGoal: 10, stopped: false))
        info("Jev 잘못된 키 → 경로 \(d.view.path.rawValue) · \(d.view.note ?? "")")
        check("Jev 실패 → 규칙으로 계속 동작", d.view.path == .rule && d.nudge)
        let ping = await JevDecisions.ping()
        check("Jev 연결 테스트가 실패를 알려 줌", ping.hasPrefix("실패"), ping)
        SecretStore.delete(JevClient.keyAccount)
        check("내 키 삭제 → 기본 키로 복귀", JevClient.usingBuiltIn)

        _ = KeyStore.save("sk-ant-invalid-key-for-test")
        if let s = SleepStats(nights: SleepStore.groupIntoNights(TestData.sleep(.good))) {
            do {
                _ = try await ClaudeClient.report(for: s, model: CoachSettings.load().model)
                check("Claude 잘못된 키 → 오류", false, "성공해 버림")
            } catch {
                info("Claude 잘못된 키 → \(error.localizedDescription)")
                check("Claude 잘못된 키 → 알기 쉬운 오류 (401)", error.localizedDescription.contains("401"))
            }
        }
        KeyStore.delete()
        check("Claude 내 키 삭제 → 기본 키로 복귀", KeyStore.usingBuiltIn)
    }
}
