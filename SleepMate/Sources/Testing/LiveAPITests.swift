import Foundation

// 실제 API 라이브 테스트 (CI 전용: 실행 인자 -runLiveAPITests YES)
// 빌드에 들어간 기본 키로 Jev·Claude를 실제로 호출해 앱 코드 경로가 끝까지 동작하는지 확인한다.
// 키 값은 절대 출력하지 않는다. 결과는 stderr에 [LiveTest] 줄로 쓴다.
@MainActor
enum LiveAPITests {
    private static var failed = 0
    private static var total = 0

    private static func out(_ s: String) {
        FileHandle.standardError.write(Data("[LiveTest] \(s)\n".utf8))
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        total += 1
        if !ok { failed += 1 }
        out("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func info(_ s: String) { out("INFO \(s)") }

    private static func timed<T>(_ f: () async throws -> T) async rethrows -> (T, Int) {
        let t0 = Date()
        let r = try await f()
        return (r, Int(Date().timeIntervalSince(t0) * 1000))
    }

    static func runIfRequested() async {
        guard UserDefaults.standard.bool(forKey: "runLiveAPITests") else { return }
        let cfg = JevConfig.load()
        info("Jev 키: \(BuiltInKeys.jev != nil ? "있음" : "없음") · 제공처 \(cfg.provider.rawValue) · \(cfg.url) · 모델 \(cfg.model)")
        info("Claude 키: \(BuiltInKeys.claude != nil ? "있음" : "없음") · 모델 \(CoachSettings.load().model)")
        check("기본 Jev 키 포함", BuiltInKeys.jev != nil)
        check("기본 Claude 키 포함", BuiltInKeys.claude != nil)

        await jev()
        await claude()
        out("SUMMARY total=\(total) failed=\(failed)")
        await LiveAPIFullTests.run()
    }

    // MARK: Jev

    private static func jev() async {
        guard JevClient.isConfigured else { return }

        // 0. 원시 호출 (응답 형식 확인)
        do {
            let (a, ms) = try await timed {
                try await JevClient.decide(state: "The user slept 5 hours last night and feels tired.",
                                           questions: ["tired": .noul(instructions: "Is the user likely to feel sleepy this afternoon?",
                                                                      yes: "Likely sleepy.", no: "Likely fine.")],
                                           timeout: 20)
            }
            let p = a["tired"]?.noul
            check("Jev 연결 (noul)", p != nil, "응답 키 \(Array(a.keys))")
            info("Jev 응답 \(ms)ms · '5시간 자고 피곤 → 오후에 졸릴까?' = \(p.map { "\(Int($0 * 100))%" } ?? "-")")
            check("Jev 판단이 상식적 (졸림 ≥ 50%)", (p ?? 0) >= 0.5, "\(p ?? -1)")
        } catch {
            check("Jev 연결 (noul)", false, error.localizedDescription)
            return     // 연결이 안 되면 나머지는 의미 없음
        }

        // ① 취침 전 한마디
        let over = await JevDecisions.windDown(WindDownInput(minutesToBed: 10, screenCount: 18, screenGoal: 10, stopped: false))
        check("① 개입: Jev 경로 사용", over.view.path == .light, over.view.note ?? "")
        check("① 목표 초과·취침 10분 전 → 개입", over.nudge,
              "확률 \(over.view.bars.first?.value ?? -1)")
        info("① 개입 결과: \(over.tone.rawValue) · \(over.action.rawValue) · “\(over.message)”")
        let calm = await JevDecisions.windDown(WindDownInput(minutesToBed: 180, screenCount: 1, screenGoal: 10, stopped: false))
        info("① 여유(3시간 전, 1/10) → 개입 \(calm.nudge ? "함" : "안 함") (\(Int((calm.view.bars.first?.value ?? 0) * 100))%)")
        check("① 여유 있을 때 → 개입 안 함", !calm.nudge)

        // ② 할 일 분류
        let titles = ["AI융합연구 발표 PPT 마무리", "마트: 대파, 두부, 계란", "치과 전화해서 예약",
                      "저녁 운동 30분", "석사 종합시험 13:20", "논문 3편 읽고 정리"]
        let (cls, ms) = await timed { await JevDecisions.classify(titles) }
        check("② 분류: Jev 경로 사용", cls.allSatisfy { $0.path == .light }, "\(cls.map(\.path.rawValue))")
        info("② 분류 \(ms)ms")
        var agree = 0
        for (t, c) in zip(titles, cls) {
            let rule = JevDecisions.classifyRule(t)
            if rule.kind == c.kind { agree += 1 }
            info("②  \(t) → \(c.kind.label) · 집중 \(c.focus)  (규칙: \(rule.kind.label))")
        }
        check("② 규칙과 대체로 일치 (≥ 4/6)", agree >= 4, "\(agree)/6")

        // ③ 수면 사운드
        let (snd, view) = await JevDecisions.sound(mood: .anxious, fatigue: 3, minutesToBed: 20, preference: "")
        check("③ 사운드: Jev 경로 사용", view.path == .light, view.note ?? "")
        info("③ 불안·취침 20분 전 → \(snd.title) (확신 \(Int((view.confidence ?? 0) * 100))%) · 후보 \(view.bars.map { "\($0.label) \(Int($0.value * 100))%" })")

        // ④ Claude 게이트
        if let short = SleepStats(nights: SleepStore.groupIntoNights(TestData.sleep(.short))),
           let good = SleepStats(nights: SleepStore.groupIntoNights(TestData.sleep(.good))) {
            let s = await JevDecisions.shouldUseLLM(short)
            let g = await JevDecisions.shouldUseLLM(good)
            info("④ 부족한 밤 → Claude \(s ? "호출" : "생략") · 평범한 밤 → Claude \(g ? "호출" : "생략")")
            check("④ 부족한 밤 → Claude 호출", s)
            check("④ 평범한 밤 → Claude 생략 (비용 절감)", !g)
        }
    }

    // MARK: Claude

    private static func claude() async {
        guard KeyStore.load() != nil,
              let stats = SleepStats(nights: SleepStore.groupIntoNights(TestData.sleep(.short))) else { return }
        do {
            let model = CoachSettings.load().model
            let (r, ms) = try await timed { try await ClaudeClient.report(for: stats, model: model) }
            check("Claude 요약 생성", !r.summary.isEmpty)
            check("Claude 추천 1개 이상", !r.recommendations.isEmpty, "\(r.recommendations.count)개")
            check("Claude 음성 원고", !r.speech.isEmpty)
            info("Claude \(ms)ms · 모델 \(r.model ?? model)")
            info("Claude 요약: \(r.summary.prefix(160))")
            for (i, rec) in r.recommendations.prefix(4).enumerated() { info("Claude 추천 \(i + 1): \(rec.prefix(80))") }
        } catch {
            check("Claude 요약 생성", false, error.localizedDescription)
        }
    }
}
