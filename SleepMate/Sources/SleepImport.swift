import Foundation

/// HealthKit 권한 없이 수면 데이터를 들여오는 경로들.
///  1) 단축어: "건강 샘플 찾기(수면 분석)" 결과를 줄 단위 텍스트로 넘겨줌
///     한 줄 형식:  시작날짜|종료날짜|값|소스   (소스는 생략 가능)
///  2) 건강 앱 "모든 건강 데이터 내보내기"의 export.xml
enum SleepImport {

    // MARK: - 단축어 텍스트

    struct TextResult {
        var segments: [SleepSegment] = []
        var skipped: [String] = []      // 해석하지 못한 줄 (디버깅용)
    }

    static func parseShortcutText(_ text: String) -> TextResult {
        var result = TextResult()
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3,
                  let start = parseDate(parts[0]),
                  let end = parseDate(parts[1]),
                  let stage = parseStage(parts[2]),
                  end > start
            else {
                result.skipped.append(line)
                continue
            }
            let source = parts.count >= 4 && !parts[3].isEmpty ? parts[3] : "단축어"
            result.segments.append(SleepSegment(
                id: UUID(), stage: stage, start: start, end: end,
                sourceName: source, sourceID: source
            ))
        }
        return result
    }

    /// 단축어가 내보내는 수면 값은 iOS 언어에 따라 영어/한국어로 다르게 나온다.
    static func parseStage(_ s: String) -> SleepStage? {
        let v = s.lowercased().replacingOccurrences(of: " ", with: "")
        if let n = Int(v), let stage = SleepStage(rawValue: n) { return stage }
        if v.hasPrefix("hkcategoryvaluesleepanalysis") {
            return parseStage(String(v.dropFirst("hkcategoryvaluesleepanalysis".count)))
        }
        if v.contains("core") || v.contains("코어") { return .core }
        if v.contains("deep") || v.contains("깊") { return .deep }
        if v.contains("rem") || v.contains("렘") { return .rem }
        if v.contains("awake") || v.contains("깨") || v.contains("깸") { return .awake }
        if v.contains("inbed") || v.contains("침대") || v.contains("누워") { return .inBed }
        if v.contains("unspecified") || v.contains("asleep") || v.contains("sleep")
            || v.contains("수면") || v.contains("잠") || v.contains("미지정") {
            return .asleepUnspecified
        }
        return nil
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime]
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [a, b]
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd HH:mm:ss Z",          // export.xml
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy. M. d. a h:mm:ss",          // 한국어 기본 날짜 형식
            "yyyy. M. d. a h:mm",
            "yyyy. M. d. HH:mm",
            "yyyy년 M월 d일 a h:mm",
            "MMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm a",
        ]
        return patterns.flatMap { p -> [DateFormatter] in
            ["ko_KR", "en_US_POSIX"].map { loc in
                let f = DateFormatter()
                f.locale = Locale(identifier: loc)
                f.timeZone = .current
                f.dateFormat = p
                return f
            }
        }
    }()

    static func parseDate(_ s: String) -> Date? {
        let t = s.replacingOccurrences(of: "\u{202F}", with: " ")   // 좁은 공백
                 .replacingOccurrences(of: "\u{00A0}", with: " ")
                 .trimmingCharacters(in: .whitespaces)
        for f in isoFormatters { if let d = f.date(from: t) { return d } }
        for f in fallbackFormatters { if let d = f.date(from: t) { return d } }
        return nil
    }

    // MARK: - 건강 앱 export.xml

    /// 수십~수백 MB 파일이므로 스트리밍으로 수면 레코드만 뽑는다.
    static func parseHealthExport(at url: URL, sinceDays: Int = 60) throws -> [SleepSegment] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "SleepImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "파일을 열 수 없습니다."])
        }
        let delegate = ExportDelegate(since: Date().addingTimeInterval(-Double(sinceDays) * 86400))
        parser.delegate = delegate
        if !parser.parse(), let err = parser.parserError {
            throw err
        }
        return delegate.segments
    }

    private final class ExportDelegate: NSObject, XMLParserDelegate {
        let since: Date
        var segments: [SleepSegment] = []
        init(since: Date) { self.since = since }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attr: [String: String] = [:]) {
            guard elementName == "Record",
                  attr["type"] == "HKCategoryTypeIdentifierSleepAnalysis",
                  let s = attr["startDate"], let e = attr["endDate"], let v = attr["value"],
                  let start = SleepImport.parseDate(s), let end = SleepImport.parseDate(e),
                  end > start, end >= since,
                  let stage = SleepImport.parseStage(v)
            else { return }
            let source = attr["sourceName"] ?? "건강 앱"
            segments.append(SleepSegment(
                id: UUID(), stage: stage, start: start, end: end,
                sourceName: source, sourceID: source
            ))
        }
    }
}
