import Foundation

/// 개인 특성 저장소 (이 기기에만 저장)
@MainActor
@Observable
final class PersonalStore {
    static let shared = PersonalStore()
    private static let key = "personalProfile"

    private(set) var profile: PersonalProfile

    /// 바꾸고 바로 저장
    func update(_ change: (inout PersonalProfile) -> Void) {
        change(&profile)
        save()
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(PersonalProfile.self, from: d) {
            profile = p
        } else {
            profile = PersonalProfile()
        }
    }

    private func save() {
        guard !DemoMode.isOn, !TestLab.shared.isOn, !DemoTour.shared.isOn else { return }
        if let d = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func toggle(_ id: String) {
        update { p in
            if let i = p.chosen.firstIndex(of: id) { p.chosen.remove(at: i) } else { p.chosen.append(id) }
        }
        AgentLog.shared.add(.planToday, path: .rule, action: "전략 선택: \(profile.chosen.joined(separator: ", "))")
    }

    /// 인터뷰 결과를 앱 설정(장기 Context)에 반영: 평일 취침·기상
    func applyToContext(_ ctx: ContextStore) {
        if let b = profile.workdayBed { ctx.profile.bedtimeMinutes = b }
        if let w = profile.workdayWake { ctx.profile.defaultWakeMinutes = w }
        ctx.save()
        UserDefaults.standard.set(true, forKey: "onboardBedtimeSet")
    }

    /// 데모·테스트용 예시 (대학원생, 저녁형, 늦은 커피)
    func loadExample() {
        var p = PersonalProfile()
        p.workdayBed = 60; p.workdayWake = 8 * 60
        p.freeBed = 3 * 60; p.freeWake = 11 * 60
        p.problems = [.lateBed, .wakeTired]
        p.caffeineCups = 3; p.lastCaffeine = 17 * 60
        p.exercise = .evening; p.naps = false; p.alcoholPerWeek = 1
        p.lifestyle = "수업·연구"
        p.chosen = ["caffeine-cutoff", "screen-off", "todo-offload"]
        p.interviewDone = true
        profile = p
    }

    /// 테스트·데모가 끝나면 저장된 값으로 되돌리기
    func reload() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(PersonalProfile.self, from: d) { profile = p } else { profile = PersonalProfile() }
    }
}

/// 인터뷰 한 턴의 결과 (Claude 도구 입력 → 구조화)
struct InterviewStep: Equatable {
    var reply: String
    var quickReplies: [String]
    var update: PersonalProfile.Update
    var redFlag: Bool
    var done: Bool
}

extension PersonalProfile {
    /// 이번 턴에 새로 알게 된 것 (없는 값은 nil)
    struct Update: Equatable {
        var workdayBed: Int?, workdayWake: Int?, freeBed: Int?, freeWake: Int?
        var problems: [SleepProblem] = []
        var caffeineCups: Int?, lastCaffeine: Int?, caffeineSensitive: Bool?
        var exercise: ExerciseTime?
        var naps: Bool?
        var alcoholPerWeek: Int?
        var lifestyle: String?
        var note: String?
    }

    mutating func merge(_ u: Update) {
        if let v = u.workdayBed { workdayBed = v }
        if let v = u.workdayWake { workdayWake = v }
        if let v = u.freeBed { freeBed = v }
        if let v = u.freeWake { freeWake = v }
        for p in u.problems where !problems.contains(p) { problems.append(p) }
        if let v = u.caffeineCups { caffeineCups = v }
        if let v = u.lastCaffeine { lastCaffeine = v }
        if let v = u.caffeineSensitive { caffeineSensitive = v }
        if let v = u.exercise { exercise = v }
        if let v = u.naps { naps = v }
        if let v = u.alcoholPerWeek { alcoholPerWeek = v }
        if let v = u.lifestyle, !v.isEmpty { lifestyle = v }
        if let v = u.note, !v.isEmpty { notes.append(v) }
    }

    /// Claude에게 '지금까지 알게 된 것'으로 넘기는 요약 (이름·병명 없음)
    var knownSummary: String {
        var parts: [String] = []
        if let b = workdayBed, let w = workdayWake { parts.append("평일 \(Clock.hhmm(b))~\(Clock.hhmm(w))") }
        if let b = freeBed, let w = freeWake { parts.append("쉬는 날 \(Clock.hhmm(b))~\(Clock.hhmm(w))") }
        if !problems.isEmpty { parts.append("고민: " + problems.map(\.label).joined(separator: ", ")) }
        if let c = caffeineCups { parts.append("카페인 하루 \(c)잔" + (lastCaffeine.map { ", 마지막 \(Clock.hhmm($0))" } ?? "")) }
        if let s = caffeineSensitive { parts.append(s ? "카페인에 예민" : "카페인에 둔감") }
        if let e = exercise { parts.append("운동: \(e.label)") }
        if let n = naps { parts.append(n ? "낮잠 잠" : "낮잠 거의 안 잠") }
        if let a = alcoholPerWeek { parts.append("음주 주 \(a)회") }
        if let l = lifestyle { parts.append("생활: \(l)") }
        return parts.isEmpty ? "아직 없음" : parts.joined(separator: " / ")
    }

    /// 아직 묻지 않은 주제
    var missingTopics: [String] {
        var m: [String] = []
        if workdayBed == nil || workdayWake == nil { m.append("평일 취침·기상 시각") }
        if freeBed == nil || freeWake == nil { m.append("쉬는 날 취침·기상 시각") }
        if problems.isEmpty { m.append("가장 큰 수면 고민") }
        if caffeineCups == nil { m.append("카페인(하루 잔 수, 마지막 시각)") }
        if exercise == nil { m.append("운동 시간대") }
        if naps == nil { m.append("낮잠") }
        if alcoholPerWeek == nil { m.append("음주 빈도") }
        if lifestyle == nil { m.append("생활 형태(수업·출근·교대 등)") }
        return m
    }
}

/// AI 인터뷰 (Claude 도구 사용 강제 → 구조화된 값만 받는다)
enum InterviewClient {
    static let systemPrompt = """
    너는 수면 관리 앱 SleepMate의 첫 설정 도우미다. 한국어로, 친구처럼 따뜻하고 짧게 말한다.
    목표: 2~3분 안에 사용자의 생활 패턴을 알아내 맞춤 전략을 고를 수 있게 한다.
    규칙:
    - 한 번에 질문 하나만, 2문장 이내. 답하기 쉬운 빠른 답(quick_replies) 2~4개를 함께 준다.
    - 사용자가 실제로 말한 것만 extracted에 넣는다. 추측하지 않는다. 시각은 24시간제 "HH:mm".
    - 이름, 나이, 병명, 복용 약은 묻지 않는다.
    - 진단하지 않는다. 다만 '심한 코골이와 숨이 멈춘다는 말', '3개월 넘게 주 3번 이상 잠들기 어려움', '운전 중 졸음' 같은 말이 나오면 red_flag=true로 하고, 수면 전문의 상담을 부드럽게 권한다.
    - 남은 주제가 없거나 사용자가 그만하고 싶어 하면 done=true로 하고 고맙다고 짧게 마무리한다.
    """

    static let tool: [String: Any] = [
        "name": "interview_step",
        "description": "다음에 사용자에게 할 말과, 이번 답에서 새로 알게 된 사실",
        "input_schema": [
            "type": "object",
            "properties": [
                "reply": ["type": "string", "description": "사용자에게 보여 줄 말 (다음 질문 포함, 2문장 이내)"],
                "quick_replies": ["type": "array", "items": ["type": "string"], "description": "빠른 답 2~4개"],
                "extracted": [
                    "type": "object",
                    "properties": [
                        "workday_bed": ["type": "string", "description": "평일 취침 HH:mm"],
                        "workday_wake": ["type": "string", "description": "평일 기상 HH:mm"],
                        "free_bed": ["type": "string", "description": "쉬는 날 취침 HH:mm"],
                        "free_wake": ["type": "string", "description": "쉬는 날 기상 HH:mm"],
                        "problems": ["type": "array", "items": ["type": "string", "enum": SleepProblem.allCases.map(\.rawValue)]],
                        "caffeine_cups_per_day": ["type": "integer"],
                        "last_caffeine": ["type": "string", "description": "마지막 카페인 HH:mm"],
                        "caffeine_sensitive": ["type": "boolean"],
                        "exercise_time": ["type": "string", "enum": PersonalProfile.ExerciseTime.allCases.map(\.rawValue)],
                        "naps": ["type": "boolean"],
                        "alcohol_per_week": ["type": "integer"],
                        "lifestyle": ["type": "string", "description": "수업·연구 / 출근 / 교대 근무 / 자유 등"],
                        "note": ["type": "string", "description": "그 밖에 수면에 중요한 생활 특징 한 줄"],
                    ],
                ],
                "red_flag": ["type": "boolean"],
                "done": ["type": "boolean"],
            ],
            "required": ["reply", "quick_replies", "extracted", "done"],
        ] as [String: Any],
    ]

    static let opening = InterviewStep(
        reply: "안녕하세요! 몇 가지만 물어보고 나에게 맞는 수면 전략을 골라 드릴게요. 평일에는 보통 몇 시에 자고 몇 시에 일어나요?",
        quickReplies: ["12시에 자서 7시에 일어나요", "1시쯤 자서 8시쯤 일어나요", "그때그때 달라요"],
        update: .init(), redFlag: false, done: false)

    struct Turn: Equatable {
        enum Role: String { case user, assistant }
        let role: Role
        let text: String
    }

    /// 한 턴 진행. history는 opening 다음부터 (assistant 말은 글로만 넘긴다)
    static func next(history: [Turn], known: PersonalProfile, model: String) async throws -> InterviewStep {
        guard let key = KeyStore.load(), !key.isEmpty else { throw ClaudeError.noKey }
        var req = URLRequest(url: ClaudeClient.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let system = systemPrompt + "\n\n지금까지 알게 된 것: \(known.knownSummary)\n아직 모르는 주제: \(known.missingTopics.joined(separator: ", "))"
        var msgs: [[String: Any]] = [["role": "assistant", "content": opening.reply]]
        msgs = [["role": "user", "content": "(설정을 시작했어요)"]] + msgs
        msgs += history.map { ["role": $0.role.rawValue, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 700,
            "system": system,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "interview_step"],
            "messages": msgs,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw ClaudeError.http(code, msg)
        }
        guard let content = obj?["content"] as? [[String: Any]],
              let input = content.first(where: { $0["type"] as? String == "tool_use" })?["input"] as? [String: Any]
        else { throw ClaudeError.badResponse(String(data: data, encoding: .utf8) ?? "") }
        return parse(input)
    }

    /// "01:30", "1:30", "25:00" → 자정 기준 분
    static func minutes(_ s: Any?) -> Int? {
        guard let s = s as? String else { return nil }
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...47).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0] * 60 + parts[1]) % 1440
    }

    static func parse(_ input: [String: Any]) -> InterviewStep {
        let e = input["extracted"] as? [String: Any] ?? [:]
        var u = PersonalProfile.Update()
        u.workdayBed = minutes(e["workday_bed"])
        u.workdayWake = minutes(e["workday_wake"])
        u.freeBed = minutes(e["free_bed"])
        u.freeWake = minutes(e["free_wake"])
        u.problems = (e["problems"] as? [String] ?? []).compactMap(SleepProblem.init(rawValue:))
        u.caffeineCups = e["caffeine_cups_per_day"] as? Int
        u.lastCaffeine = minutes(e["last_caffeine"])
        u.caffeineSensitive = e["caffeine_sensitive"] as? Bool
        u.exercise = (e["exercise_time"] as? String).flatMap(PersonalProfile.ExerciseTime.init(rawValue:))
        u.naps = e["naps"] as? Bool
        u.alcoholPerWeek = e["alcohol_per_week"] as? Int
        u.lifestyle = e["lifestyle"] as? String
        u.note = e["note"] as? String
        let replies = (input["quick_replies"] as? [String] ?? []).prefix(4).map { String($0.prefix(30)) }
        return InterviewStep(reply: ClaudeClient.trimSpeech(input["reply"] as? String ?? "", limit: 160),
                             quickReplies: Array(replies),
                             update: u,
                             redFlag: input["red_flag"] as? Bool ?? false,
                             done: input["done"] as? Bool ?? false)
    }
}
