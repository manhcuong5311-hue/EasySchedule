//
//  QuickAddParser.swift
//  Easy Schedule
//
//  Natural-language quick add: turns a sentence such as
//  "Cà phê với Lan 3h chiều mai" or "Lunch with Minh tomorrow 12:30"
//  into a title + start date/time + optional duration.
//
//  Pure Foundation, no UI. Matching runs on a diacritic-folded, lowercased
//  copy of the text that maps 1:1 (per Character) back to the original, so
//  the title keeps the user's own spelling. The parser is deliberately
//  conservative: it only strips words that are part of a recognised
//  date / time / duration phrase (plus a dangling "lúc / vào / at / on").
//

import Foundation

nonisolated struct QuickAddResult: Equatable {
    var title: String
    var start: Date?
    var durationMinutes: Int?
    var matchedText: [String]
}

nonisolated enum QuickAddParser {

    /// Returns nil when no date or time could be found in `text`.
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> QuickAddResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300 else { return nil }
        let scan = QAScan(text: trimmed)
        scan.collect()
        return scan.resolve(now: now, calendar: calendar)
    }
}

// MARK: - Token model

nonisolated private enum QAPeriod {
    case morning, noon, afternoon, evening, night

    /// Start hour used when only a day + period is given ("tối mai").
    var defaultHour: Int {
        switch self {
        case .morning:   return 9
        case .noon:      return 12
        case .afternoon: return 15
        case .evening:   return 19
        case .night:     return 21
        }
    }

    func apply(to h: Int) -> Int {
        switch self {
        case .morning:             return h
        case .noon:                return h <= 3 ? h + 12 : h        // 12h trưa → 12, 1h trưa → 13
        case .afternoon, .evening: return h < 12 ? h + 12 : h
        case .night:
            if (6...11).contains(h) { return h + 12 }               // 11h đêm → 23
            return h == 12 ? 0 : h                                   // 2h đêm → 2
        }
    }
}

nonisolated private enum QAMeridiem { case am, pm }

nonisolated private struct QAClock {
    var hour: Int
    var minute: Int
    var meridiem: QAMeridiem?
    /// Single-digit hour 1…6 with no am/pm ("Họp 3h") → assume afternoon.
    var ambiguous: Bool
}

nonisolated private enum QAWeekdayMode { case upcoming, strictlyNext, nextWeek }

nonisolated private enum QADay {
    case offset(Int)
    case weekday(Int, QAWeekdayMode)                 // Calendar weekday 1 (Sun) … 7 (Sat)
    case date(day: Int, month: Int?, year: Int?)     // month nil → "ngày 14"

    var priority: Int {
        switch self {
        case .date:    return 0
        case .weekday: return 1
        case .offset:  return 2
        }
    }
}

nonisolated private enum QAKind {
    case duration(Int)
    case day(QADay, implied: QAPeriod?, weak: Bool)
    case time(QAClock)
    /// keep: meal word ("ăn tối") — used for the hour, never stripped.
    /// plain: typed without diacritics ("sang", "toi") — only trusted after a time/day.
    case period(QAPeriod, keep: Bool, plain: Bool)
}

nonisolated private struct QAToken {
    let range: Range<Int>
    let kind: QAKind

    var isTime: Bool { if case .time = kind { return true } else { return false } }
    var isDay: Bool { if case .day = kind { return true } else { return false } }
    var isPeriod: Bool { if case .period = kind { return true } else { return false } }
    var isDuration: Bool { if case .duration = kind { return true } else { return false } }
}

nonisolated private struct QAMatch {
    let range: Range<Int>
    let groups: [Range<Int>?]
    func g(_ i: Int) -> Range<Int>? { i < groups.count ? groups[i] : nil }
}

// MARK: - Text (original ↔ folded)

nonisolated private struct QAText {
    let original: [Character]
    let folded: [Character]
    let foldedString: String
    let utf16ToChar: [Int: Int]

    init(_ text: String) {
        let orig = Array(text)
        var fc = orig.map(QAText.fold)
        var fs = String(fc)
        if fs.count != orig.count {        // grapheme merge after folding — stay 1:1
            fc = orig
            fs = String(orig)
        }
        var map: [Int: Int] = [:]
        var u = 0
        for (i, ch) in fc.enumerated() {
            map[u] = i
            u += String(ch).utf16.count
        }
        map[u] = fc.count
        original = orig
        folded = fc
        foldedString = fs
        utf16ToChar = map
    }

    static func fold(_ ch: Character) -> Character {
        if ch == "đ" || ch == "Đ" { return "d" }
        let s = String(ch).folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                   locale: nil)
        if s.count == 1, let c = s.first { return c }
        let l = String(ch).lowercased()
        if l.count == 1, let c = l.first { return c }
        return ch
    }

    func chars(_ ns: NSRange) -> Range<Int>? {
        guard ns.location != NSNotFound,
              let a = utf16ToChar[ns.location],
              let b = utf16ToChar[ns.location + ns.length] else { return nil }
        return a..<b
    }

    func f(_ r: Range<Int>?) -> String {
        guard let r else { return "" }
        return String(folded[r])
    }

    func o(_ r: Range<Int>) -> String { String(original[r]) }

    /// Original spelling (lowercased) is one of `allowed`.
    func origIs(_ r: Range<Int>?, _ allowed: [String]) -> Bool {
        guard let r else { return false }
        return allowed.contains(String(original[r]).lowercased())
    }

    /// Range of the word (letters only) right before `index`, skipping spaces.
    func wordBefore(_ index: Int) -> Range<Int>? {
        var e = index
        while e > 0, original[e - 1].isWhitespace { e -= 1 }
        var s = e
        while s > 0, original[s - 1].isLetter { s -= 1 }
        return s < e ? s..<e : nil
    }

    func foldedWordBefore(_ index: Int) -> String? {
        wordBefore(index).map { f($0) }
    }

    /// Folded text between two offsets with spaces/commas trimmed.
    func gap(_ a: Int, _ b: Int) -> String {
        guard a <= b else { return "" }
        return String(folded[a..<b]).trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n"))
    }
}

// MARK: - Scanner

nonisolated private final class QAScan {

    let t: QAText
    var tokens: [QAToken] = []

    init(text: String) { t = QAText(text) }

    // Word-boundary helpers (ICU, folded text).
    private let nb = #"(?<![\p{L}\p{N}])"#
    private let na = #"(?![\p{L}\p{N}])"#
    /// Minutes after an hour that must not be the start of another time/date.
    private let minuteGuard = #"(?![\d/.:])(?!\s*(?:h|gio|g\d)(?!\p{L}))"#

    private func scan(_ pattern: String, _ make: (QAMatch) -> QAKind?) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            assertionFailure("QuickAddParser bad pattern: \(pattern)")
            return
        }
        let ns = t.foldedString as NSString
        for r in re.matches(in: t.foldedString, range: NSRange(location: 0, length: ns.length)) {
            guard let whole = t.chars(r.range), !whole.isEmpty,
                  !tokens.contains(where: { $0.range.overlaps(whole) }) else { continue }
            var groups: [Range<Int>?] = []
            for i in 0..<r.numberOfRanges { groups.append(t.chars(r.range(at: i))) }
            if let kind = make(QAMatch(range: whole, groups: groups)) {
                tokens.append(QAToken(range: whole, kind: kind))
            }
        }
    }

    func collect() {
        collectDurations()
        collectDates()
        collectWeekdays()
        collectRelativeDays()
        collectTimes()
        collectBareMinutes()
        collectPeriods()
    }

    // MARK: Numbers

    private func number(_ s: String) -> Double? {
        switch s {
        case "mot", "one", "a", "an":  return 1
        case "hai", "two":             return 2
        case "ba", "three":            return 3
        case "bon", "four":            return 4
        case "nam", "five":            return 5
        case "nua":                    return 0.5
        default:
            if s.hasPrefix("half") { return 0.5 }
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
    }

    private func int(_ m: QAMatch, _ i: Int) -> Int? {
        guard m.g(i) != nil else { return nil }
        return Int(t.f(m.g(i)))
    }

    private func duration(_ minutes: Double) -> QAKind? {
        let v = Int(minutes.rounded())
        return (1...1440).contains(v) ? .duration(v) : nil
    }

    // MARK: Durations

    private func collectDurations() {
        let qty = #"(\d+(?:[.,]\d+)?|mot|hai|ba|bon|nam|an?|one|two|three|four|five|nua|half\s+an?)"#
        let hourUnits: Set<String> = ["tieng", "gio", "h", "hour", "hours", "hr", "hrs"]

        // "trong 1 giờ", "trong 30 phút", "for 2 hours", "kéo dài 1 tiếng rưỡi", "for an hour"
        scan(nb + #"(?:trong(?:\s+vong)?|for|keo\s+dai)\s+(?:khoang\s+|about\s+|around\s+)?"# + qty
             + #"\s*(tieng|gio|h|hours?|hrs?|phut|p|minutes?|mins?|m)"# + na
             + #"(?:\s*(ruoi)"# + na + #"|\s*(?:and\s+)?(\d{1,2})"# + minuteGuard
             + #"\s*(?:phut|p|minutes?|mins?|m)?"# + na + ")?") { m in
            guard let n = number(t.f(m.g(1))) else { return nil }
            let unit = t.f(m.g(2))
            if unit == "gio", !t.origIs(m.g(2), ["giờ", "gio"]) { return nil }
            let isHour = hourUnits.contains(unit)
            var mins = isHour ? n * 60 : n
            if isHour, m.g(3) != nil { mins += 30 }
            if isHour, let extra = int(m, 4) { mins += Double(extra) }
            return duration(mins)
        }

        // "1 tiếng", "1 tiếng rưỡi", "2 tiếng 30", "nửa tiếng", "1,5 tiếng"
        scan(nb + #"(\d+(?:[.,]\d+)?|mot|hai|ba|bon|nam|nua)\s*tieng"# + na
             + #"(?:\s*(ruoi)"# + na + #"|\s*(\d{1,2})"# + minuteGuard + #"\s*(?:phut|p)?"# + na + ")?") { m in
            guard let n = number(t.f(m.g(1))) else { return nil }
            var mins = n * 60
            if m.g(2) != nil { mins += 30 }
            if let extra = int(m, 3) { mins += Double(extra) }
            return duration(mins)
        }

        // "tiếng rưỡi"
        scan(nb + #"tieng\s+ruoi"# + na) { _ in .duration(90) }

        // "2 hours", "1.5 hrs", "1 hour 30 min" (not "in 2 hours")
        scan(nb + #"(\d+(?:[.,]\d+)?)\s*(?:hours?|hrs?)"# + na
             + #"(?:\s*(?:and\s+)?(\d{1,2})\s*(?:minutes?|mins?|m)"# + na + ")?") { m in
            if t.foldedWordBefore(m.range.lowerBound) == "in" { return nil }
            guard let n = number(t.f(m.g(1))) else { return nil }
            return duration(n * 60 + Double(int(m, 2) ?? 0))
        }
    }

    /// "90 phút", "30p", "45 min" — after times so "15h30p" stays a time.
    private func collectBareMinutes() {
        scan(#"(?<![\p{L}\p{N}/:.,])(\d{1,3})\s*(?:phut|p|minutes?|mins?)"# + na) { m in
            if t.foldedWordBefore(m.range.lowerBound) == "in" { return nil }
            guard let n = int(m, 1) else { return nil }
            return duration(Double(n))
        }
    }

    // MARK: Dates

    private func dateKind(day: Int?, month: Int?, year: Int?) -> QAKind? {
        guard var d = day else { return nil }
        var mo = month
        if let m0 = mo, m0 > 12, d <= 12 { mo = d; d = m0 }             // 10/14 → 14/10
        guard (1...31).contains(d) else { return nil }
        if let m1 = mo, !(1...12).contains(m1) { return nil }
        var y = year
        if let y0 = y, y0 < 100 { y = 2000 + y0 }
        return .day(.date(day: d, month: mo, year: y), implied: nil, weak: false)
    }

    private func collectDates() {
        // "14/10", "14/10/2026", "ngày 14/10/26"
        scan(nb + #"(?:ngay\s+|mung\s+|mong\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\p{N}/])"#) { m in
            dateKind(day: int(m, 1), month: int(m, 2), year: int(m, 3))
        }
        // "14-10-2026", "14.10.2026"
        scan(nb + #"(?:ngay\s+)?(\d{1,2})[.\-](\d{1,2})[.\-](\d{4})"# + na) { m in
            dateKind(day: int(m, 1), month: int(m, 2), year: int(m, 3))
        }
        // "14 tháng 10", "ngày 14 tháng 10 năm 2026"
        scan(nb + #"(?:ngay\s+|mung\s+|mong\s+)?(\d{1,2})\s+(thang)\s+(\d{1,2})"# + na
             + #"(?:\s*,?\s*(?:nam\s+)?(\d{4})"# + na + ")?") { m in
            guard t.origIs(m.g(2), ["tháng", "thang"]) else { return nil }
            return dateKind(day: int(m, 1), month: int(m, 3), year: int(m, 4))
        }
        // "ngày 14" (day of month)
        scan(nb + #"(ngay|mung|mong)\s+(\d{1,2})(?![\p{L}\p{N}/.:])(?!\s*(?:tieng|gio|h|phut|p|thang)(?!\p{L}))"#) { m in
            guard t.origIs(m.g(1), ["ngày", "mùng", "mung", "mồng"]) else { return nil }
            return dateKind(day: int(m, 2), month: nil, year: nil)
        }

        // English: "Oct 14", "October 14th, 2026", "14 Oct", "the 14th of October"
        let months = #"(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)"#
        scan(nb + months + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?"# + na + #"(?:,?\s+(\d{4})"# + na + ")?") { m in
            dateKind(day: int(m, 2), month: monthNumber(t.f(m.g(1))), year: int(m, 3))
        }
        scan(nb + #"(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + months + #"\.?"# + na
             + #"(?:,?\s+(\d{4})"# + na + ")?") { m in
            dateKind(day: int(m, 1), month: monthNumber(t.f(m.g(2))), year: int(m, 3))
        }
        // "on the 14th"
        scan(nb + #"the\s+(\d{1,2})(?:st|nd|rd|th)"# + na) { m in
            dateKind(day: int(m, 1), month: nil, year: nil)
        }
    }

    private func monthNumber(_ s: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let i = names.firstIndex(where: { s.hasPrefix($0) }) else { return nil }
        return i + 1
    }

    // MARK: Weekdays

    private func collectWeekdays() {
        // Words that turn "thứ 2" into an ordinal ("lần thứ 2", "người thứ ba").
        let ordinalContext: Set<String> = ["lan", "nguoi", "cai", "tap", "bai", "phan", "hang", "vong",
                                           "chuong", "ky", "lop", "con", "dua", "so", "muc", "buoc", "dot"]
        scan(nb + #"(?:(thu)\s*([2-7])|(thu)\s+(hai|ba|tu|nam|sau|bay)|t([2-7])|(chu)\s*nhat|cn)"# + na
             + #"(?:\s+(tuan\s+(?:sau|toi|nay)|nay)"# + na + ")?") { m in
            if let w = t.foldedWordBefore(m.range.lowerBound), ordinalContext.contains(w) { return nil }
            var weekday: Int?
            if m.g(1) != nil {
                guard t.origIs(m.g(1), ["thứ", "thu"]) else { return nil }
                weekday = int(m, 2)
            } else if m.g(3) != nil {
                guard t.origIs(m.g(3), ["thứ", "thu"]) else { return nil }
                let word = t.f(m.g(4))
                let allowed: [String: (Int, [String])] = [
                    "hai": (2, ["hai"]), "ba": (3, ["ba"]), "tu": (4, ["tư", "tu"]),
                    "nam": (5, ["năm", "nam"]), "sau": (6, ["sáu", "sau"]), "bay": (7, ["bảy", "bẩy", "bay"])
                ]
                guard let entry = allowed[word], t.origIs(m.g(4), entry.1) else { return nil }
                weekday = entry.0
            } else if m.g(5) != nil {
                weekday = int(m, 5)
            } else {
                if m.g(6) != nil, !t.origIs(m.g(6), ["chủ", "chu"]) { return nil }
                weekday = 1
            }
            guard let w = weekday else { return nil }
            let modifier = t.f(m.g(7))
            let mode: QAWeekdayMode = modifier.hasPrefix("tuan s") || modifier.hasPrefix("tuan t") ? .nextWeek : .upcoming
            return .day(.weekday(w, mode), implied: nil, weak: false)
        }

        scan(nb + #"(?:(next|this|coming)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)"# + na) { m in
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            guard let i = names.firstIndex(of: t.f(m.g(2))) else { return nil }
            let mode: QAWeekdayMode = t.f(m.g(1)) == "next" ? .strictlyNext : .upcoming
            return .day(.weekday(i + 1, mode), implied: nil, weak: false)
        }
    }

    // MARK: Relative days

    private func collectRelativeDays() {
        scan(nb + #"hom\s+nay"# + na) { _ in .day(.offset(0), implied: nil, weak: false) }
        scan(nb + #"ngay\s+mai"# + na) { _ in .day(.offset(1), implied: nil, weak: false) }
        scan(nb + #"ngay\s+(mot|kia)"# + na) { m in
            if t.f(m.g(1)) == "mot", !t.origIs(m.g(1), ["mốt", "mot"]) { return nil }
            return .day(.offset(2), implied: nil, weak: false)
        }
        scan(nb + #"(?:the\s+)?day\s+after\s+tomorrow"# + na) { _ in .day(.offset(2), implied: nil, weak: false) }
        scan(nb + #"(?:tomorrow|tmrw|tmr)"# + na) { _ in .day(.offset(1), implied: nil, weak: false) }
        scan(nb + #"today"# + na) { _ in .day(.offset(0), implied: nil, weak: false) }
        scan(nb + #"tonight"# + na) { _ in .day(.offset(0), implied: .evening, weak: false) }
        scan(nb + #"this\s+(morning|afternoon|evening)"# + na) { m in
            let p: QAPeriod
            switch t.f(m.g(1)) {
            case "morning":   p = .morning
            case "afternoon": p = .afternoon
            default:          p = .evening
            }
            return .day(.offset(0), implied: p, weak: false)
        }

        // Standalone "mai" — but "Mai" is also a common name.
        let personWords: Set<String> = ["voi", "gap", "goi", "cho", "cung", "chi", "anh", "em", "ban", "co", "chu",
                                        "be", "va", "ong", "ba", "nhan", "hoi", "don", "thay", "bac", "cau", "nang",
                                        "ten", "and", "with", "meet", "call"]
        scan(nb + #"mai"# + na) { m in
            let raw = t.o(m.range)
            if let w = t.foldedWordBefore(m.range.lowerBound), personWords.contains(w) { return nil }
            if raw == "mai" { return .day(.offset(1), implied: nil, weak: false) }
            if raw == "Mai" || raw == "MAI", m.range.lowerBound == 0 {
                return .day(.offset(1), implied: nil, weak: true)
            }
            return nil
        }
        // Standalone "nay" (not "này" / "nãy"), "mốt" (not "một").
        scan(nb + #"nay"# + na) { m in
            t.origIs(m.range, ["nay"]) ? .day(.offset(0), implied: nil, weak: true) : nil
        }
        scan(nb + #"mot"# + na) { m in
            t.origIs(m.range, ["mốt"]) ? .day(.offset(2), implied: nil, weak: true) : nil
        }
    }

    // MARK: Times

    private func meridiem(_ s: String) -> QAMeridiem? {
        if s.hasPrefix("a") { return .am }
        if s.hasPrefix("p") { return .pm }
        return nil
    }

    private func clock(hourText: String, minute: Int, meridiem mer: QAMeridiem?) -> QAKind? {
        guard let h = Int(hourText), (0...59).contains(minute) else { return nil }
        if mer != nil {
            guard (1...12).contains(h) else { return nil }
        } else {
            guard (0...23).contains(h) else { return nil }
        }
        let ambiguous = mer == nil && hourText.count == 1 && (1...6).contains(h)
        return .time(QAClock(hour: h, minute: minute, meridiem: mer, ambiguous: ambiguous))
    }

    private func collectTimes() {
        let lb = #"(?<![\p{L}\p{N}/:.])"#
        let ampm = #"(am|pm|a\.m\.?|p\.m\.?)(?!\p{L})"#

        // "15:30", "3:30 pm"
        scan(lb + #"(\d{1,2}):([0-5]\d)(?!\d)(?:\s*"# + ampm + ")?") { m in
            clock(hourText: t.f(m.g(1)), minute: int(m, 2) ?? 0, meridiem: meridiem(t.f(m.g(3))))
        }
        // "3pm", "9 am"
        scan(lb + #"(\d{1,2})\s*"# + ampm) { m in
            clock(hourText: t.f(m.g(1)), minute: 0, meridiem: meridiem(t.f(m.g(2))))
        }
        // "15h", "15h30", "3 giờ 30 phút", "3 giờ rưỡi", "8 giờ kém 15", "9g30"
        scan(lb + #"(\d{1,2})\s*(h|gio|g(?=\d{2}))(?!\p{L})"#
             + #"(?:\s*(?:(\d{2})"# + minuteGuard + #"(?!\s*tieng)\s*(?:phut|p)?(?!\p{L})"#
             + #"|(ruoi)(?!\p{L})|kem\s*(\d{1,2})(?!\d)\s*(?:phut|p)?(?!\p{L})))?"#) { m in
            if t.f(m.g(2)) == "gio", !t.origIs(m.g(2), ["giờ", "gio"]) { return nil }
            let hourText = t.f(m.g(1))
            guard var h = Int(hourText) else { return nil }
            var minute = int(m, 3) ?? 0
            if m.g(4) != nil { minute = 30 }
            if let k = int(m, 5) {
                guard (1...59).contains(k), h > 0 else { return nil }
                h -= 1
                minute = 60 - k
                return clock(hourText: String(h), minute: minute, meridiem: nil)
            }
            return clock(hourText: hourText, minute: minute, meridiem: nil)
        }
        // "noon"
        scan(nb + #"(?:at\s+)?noon"# + na) { _ in
            .time(QAClock(hour: 12, minute: 0, meridiem: nil, ambiguous: false))
        }
        // "lúc 9", "at 5"
        scan(nb + #"(luc|at)\s+(\d{1,2})(?![\p{L}\p{N}/:.,])"#) { m in
            if t.f(m.g(1)) == "luc", !t.origIs(m.g(1), ["lúc", "luc"]) { return nil }
            return clock(hourText: t.f(m.g(2)), minute: 0, meridiem: nil)
        }
    }

    // MARK: Periods (buổi)

    private func collectPeriods() {
        scan(nb + #"(?:(buoi)\s+)?(sang|trua|chieu|toi|dem|khuya)"# + na) { m in
            let table: [String: (QAPeriod, [String])] = [
                "sang": (.morning, ["sáng", "sang"]), "trua": (.noon, ["trưa", "trua"]),
                "chieu": (.afternoon, ["chiều", "chieu"]), "toi": (.evening, ["tối", "toi"]),
                "dem": (.night, ["đêm", "dem"]), "khuya": (.night, ["khuya"])
            ]
            guard let word = m.g(2), let entry = table[t.f(word)], t.origIs(word, entry.1) else { return nil }
            if m.g(1) != nil, !t.origIs(m.g(1), ["buổi", "buoi"]) { return nil }
            let plain = m.g(1) == nil && t.o(word).lowercased() == t.f(word) && t.f(word) != "khuya"
            var keep = false
            if let before = t.wordBefore(m.range.lowerBound),
               t.origIs(before, ["ăn", "an", "bữa", "bua"]) {
                keep = true                                      // "ăn tối", "bữa trưa"
            }
            return .period(entry.0, keep: keep, plain: plain)
        }
        scan(nb + #"(?:in\s+the\s+|at\s+)?(morning|afternoon|evening|night)"# + na) { m in
            let p: QAPeriod
            switch t.f(m.g(1)) {
            case "morning":   p = .morning
            case "afternoon": p = .afternoon
            case "evening":   p = .evening
            default:          p = .night
            }
            return .period(p, keep: false, plain: false)
        }
    }

    // MARK: - Resolve

    /// A period sits right next to `anchor` (only spaces/commas or "lúc/vào/at/on" between).
    private func isAdjacent(_ period: QAToken, _ anchor: QAToken) -> Bool {
        guard case let .period(_, _, plain) = period.kind else { return false }
        let glue: Set<String> = ["", "luc", "vao", "vao luc", "at", "on"]
        if anchor.range.upperBound <= period.range.lowerBound {
            return glue.contains(t.gap(anchor.range.upperBound, period.range.lowerBound))
        }
        if period.range.upperBound <= anchor.range.lowerBound, !plain {
            return glue.contains(t.gap(period.range.upperBound, anchor.range.lowerBound))
        }
        return false
    }

    private func isRangeGap(_ a: QAToken, _ b: QAToken) -> Bool {
        guard a.range.upperBound <= b.range.lowerBound else { return false }
        let g = t.gap(a.range.upperBound, b.range.lowerBound)
        let pattern = #"^(?:(?:buoi\s+)?(?:sang|trua|chieu|toi|dem)\s*)?(?:-|–|—|den|toi|to|until|till)$"#
        guard g.range(of: pattern, options: .regularExpression) != nil else { return false }
        if g.hasSuffix("toi") {
            let raw = String(t.original[a.range.upperBound..<b.range.lowerBound]).lowercased()
            return raw.contains("tới")
        }
        return true
    }

    func resolve(now: Date, calendar cal: Calendar) -> QuickAddResult? {
        let sorted = tokens.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let times = sorted.filter(\.isTime)
        let days = sorted.filter(\.isDay)
        let periods = sorted.filter(\.isPeriod)
        let anchors = times + days

        let acceptedPeriods = periods.filter { p in anchors.contains { isAdjacent(p, $0) } }

        let usableDays = days.filter { d in
            guard case let .day(_, _, weak) = d.kind, weak else { return true }
            return !times.isEmpty || acceptedPeriods.contains { isAdjacent($0, d) }
        }
        var dayToken = usableDays.min { a, b in
            guard case let .day(da, _, _) = a.kind, case let .day(db, _, _) = b.kind else { return false }
            return (da.priority, a.range.lowerBound) < (db.priority, b.range.lowerBound)
        }
        let timeToken = times.first
        guard dayToken != nil || timeToken != nil else { return nil }

        var endToken: QAToken?
        if let st = timeToken, let i = times.firstIndex(where: { $0.range == st.range }),
           i + 1 < times.count, isRangeGap(st, times[i + 1]) {
            endToken = times[i + 1]
        }

        // Period: next to the time first, then next to the day, then implied by the day word.
        var periodToken: QAToken?
        if let tt = timeToken { periodToken = acceptedPeriods.first { isAdjacent($0, tt) } }
        if periodToken == nil, let dt = dayToken { periodToken = acceptedPeriods.first { isAdjacent($0, dt) } }
        var period: QAPeriod?
        if let pt = periodToken, case let .period(p, _, _) = pt.kind { period = p }
        if period == nil, let dt = dayToken, case let .day(_, implied, _) = dt.kind { period = implied }

        // Clock time
        var hm: (Int, Int)?
        if let tt = timeToken, case let .time(c) = tt.kind { hm = resolveHour(c, period) }

        // Day
        let today = cal.startOfDay(for: now)
        var dayDate: Date?
        if let dt = dayToken, case let .day(ref, _, _) = dt.kind {
            dayDate = resolveDay(ref, hm: hm, now: now, today: today, calendar: cal)
            if dayDate == nil { dayToken = nil }
        }
        guard dayToken != nil || hm != nil else { return nil }

        // Start
        var start: Date?
        if case let (h, m)? = hm {
            if let dd = dayDate {
                start = cal.date(bySettingHour: h, minute: m, second: 0, of: dd)
            } else if let s = cal.date(bySettingHour: h, minute: m, second: 0, of: today) {
                start = s > now ? s : cal.date(byAdding: .day, value: 1, to: s)
            }
        } else if let dd = dayDate {
            let isToday = cal.isDate(dd, inSameDayAs: now)
            if let p = period, let s = cal.date(bySettingHour: p.defaultHour, minute: 0, second: 0, of: dd),
               !(isToday && s <= now) {
                start = s
            } else if isToday {
                start = nextFullHour(after: now, calendar: cal)
            } else {
                start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dd)
            }
        }
        guard let startDate = start else { return nil }

        // Duration: explicit phrase, else a "15:00-16:30" range.
        let durationToken = sorted.first(where: \.isDuration)
        var durationMinutes: Int?
        if let dt = durationToken, case let .duration(v) = dt.kind { durationMinutes = v }
        var usedEnd = false
        if case let (sh, sm)? = hm, let et = endToken, case let .time(ec) = et.kind {
            let (eh, em) = resolveHour(ec, ec.meridiem == nil ? period : nil)
            let s = sh * 60 + sm
            var e = eh * 60 + em
            if e <= s, eh < 12 { e += 12 * 60 }
            if e > s, e - s <= 24 * 60 {
                if durationMinutes == nil { durationMinutes = e - s }
                usedEnd = true
            }
        }

        // Tokens to strip from the title
        var strip: [QAToken] = []
        if let dt = dayToken { strip.append(dt) }
        if let tt = timeToken { strip.append(tt) }
        if usedEnd, let et = endToken { strip.append(et) }
        if let pt = periodToken, case let .period(_, keep, _) = pt.kind, !keep { strip.append(pt) }
        if let du = durationToken { strip.append(du) }
        strip.sort { $0.range.lowerBound < $1.range.lowerBound }

        var removeRanges = strip.map(\.range)
        // A "3h chiều đến 5h" / "3pm to 5pm" range also drops its connector.
        if usedEnd, let tt = timeToken, let et = endToken, tt.range.upperBound <= et.range.lowerBound {
            removeRanges.append(tt.range.upperBound..<et.range.lowerBound)
        }
        let title = buildTitle(removing: removeRanges)
        return QuickAddResult(title: title,
                              start: startDate,
                              durationMinutes: durationMinutes,
                              matchedText: strip.map { t.o($0.range) })
    }

    private func resolveHour(_ c: QAClock, _ period: QAPeriod?) -> (Int, Int) {
        var h = c.hour
        if let mer = c.meridiem {
            switch mer {
            case .am: h = h == 12 ? 0 : h
            case .pm: h = h < 12 ? h + 12 : h
            }
        } else if let p = period {
            h = p.apply(to: h)
        } else if c.ambiguous {
            h += 12
        }
        return (h % 24, c.minute)
    }

    private func nextFullHour(after now: Date, calendar cal: Calendar) -> Date? {
        cal.dateInterval(of: .hour, for: now)?.end
    }

    private func resolveDay(_ ref: QADay, hm: (Int, Int)?, now: Date, today: Date, calendar cal: Calendar) -> Date? {
        switch ref {
        case .offset(let k):
            return cal.date(byAdding: .day, value: k, to: today)

        case .weekday(let w, let mode):
            let todayW = cal.component(.weekday, from: today)
            var offset = (w - todayW + 7) % 7
            switch mode {
            case .nextWeek:
                let todayIdx = (todayW + 5) % 7                 // Monday-based week
                let targetIdx = (w + 5) % 7
                offset = 7 - todayIdx + targetIdx
            case .strictlyNext:
                if offset == 0 { offset = 7 }
            case .upcoming:
                if offset == 0 {
                    let stillAhead: Bool
                    if case let (h, m)? = hm, let s = cal.date(bySettingHour: h, minute: m, second: 0, of: today) {
                        stillAhead = s > now
                    } else if let next = nextFullHour(after: now, calendar: cal) {
                        stillAhead = cal.isDate(next, inSameDayAs: today)
                    } else {
                        stillAhead = false
                    }
                    if !stillAhead { offset = 7 }
                }
            }
            return cal.date(byAdding: .day, value: offset, to: today)

        case .date(let d, let month, let year):
            let comps = cal.dateComponents([.year, .month], from: today)
            guard let curYear = comps.year, let curMonth = comps.month else { return nil }
            func make(_ y: Int, _ mo: Int) -> Date? {
                guard let date = cal.date(from: DateComponents(year: y, month: mo, day: d)),
                      cal.component(.day, from: date) == d,
                      cal.component(.month, from: date) == mo else { return nil }   // rejects 31/2
                return date
            }
            if let mo = month {
                if let y = year { return make(y, mo) }
                if let date = make(curYear, mo), date >= today { return date }
                return make(curYear + 1, mo)
            }
            // "ngày 14": this month if still ahead, else the next month that has that day.
            for step in 0..<13 {
                let total = curMonth - 1 + step
                if let date = make(curYear + total / 12, total % 12 + 1), date >= today { return date }
            }
            return nil
        }
    }

    // MARK: Title

    private func buildTitle(removing ranges: [Range<Int>]) -> String {
        let n = t.original.count
        var removed = [Bool](repeating: false, count: n)
        for r in ranges { for i in r where i < n { removed[i] = true } }

        // Dangling connectors right before a removed phrase ("lúc", "vào lúc", "at", "on", "từ").
        let twoWord: [[String]: [[String]]] = [
            ["vao", "luc"]: [["vào", "vao"], ["lúc", "luc"]],
            ["keo", "dai"]: [["kéo", "keo"], ["dài", "dai"]],
            ["bat", "dau"]: [["bắt", "bat"], ["đầu", "dau"]]
        ]
        let oneWord: [String: [String]] = [
            "luc": ["lúc", "luc"], "vao": ["vào", "vao"], "tu": ["từ"], "ngay": ["ngày"], "hom": ["hôm"],
            "at": ["at"], "on": ["on"], "from": ["from"]
        ]
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < n {
                guard removed[i], i == 0 || !removed[i - 1] else { i += 1; continue }
                if let w1 = t.wordBefore(i), !removed[w1.lowerBound] {
                    let f1 = t.f(w1)
                    if let w0 = t.wordBefore(w1.lowerBound), !removed[w0.lowerBound],
                       let allowed = twoWord[[t.f(w0), f1]],
                       t.origIs(w0, allowed[0]), t.origIs(w1, allowed[1]) {
                        for k in w0.lowerBound..<i { removed[k] = true }
                        changed = true
                    } else if let allowed = oneWord[f1], t.origIs(w1, allowed) {
                        for k in w1.lowerBound..<i { removed[k] = true }
                        changed = true
                    }
                }
                i += 1
            }
        }

        // Kept segments made only of punctuation next to a removed phrase are dropped.
        let orphan = CharacterSet(charactersIn: " \t\n,;:-–—·/|.")
        var out = ""
        var i = 0
        while i < n {
            if removed[i] { out.append(" "); i += 1; continue }
            var j = i
            while j < n, !removed[j] { j += 1 }
            let segment = String(t.original[i..<j])
            let touchesRemoved = (i > 0 && removed[i - 1]) || (j < n && removed[j])
            if touchesRemoved, segment.unicodeScalars.allSatisfy({ orphan.contains($0) }) {
                out.append(" ")
            } else {
                out.append(segment)
            }
            i = j
        }

        var title = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+([,;])"#, with: "$1", options: .regularExpression)
        title = title.replacingOccurrences(of: #"([,;])(?:\s*[,;])+"#, with: "$1", options: .regularExpression)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,;:-–—·/|"))

        if let first = title.first, first.isLowercase, t.original.first?.isUppercase == true {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }
}

// MARK: - Self test

#if DEBUG
extension QuickAddParser {

    /// Not called by the app. Run from a scratch target / playground.
    static func _selfTest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        cal.locale = Locale(identifier: "vi_VN")
        cal.firstWeekday = 2
        func d(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        let now = d(10, 13, 10)                       // Tuesday 13/10/2026 10:00

        let cases: [(input: String, title: String, start: Date, minutes: Int?)] = [
            ("Cà phê với Lan 3h chiều mai",            "Cà phê với Lan",   d(10, 14, 15),     nil),
            ("Họp nhóm thứ 6 lúc 9h30",                "Họp nhóm",         d(10, 16, 9, 30),  nil),
            ("Gọi mẹ 20h tối nay",                     "Gọi mẹ",           d(10, 13, 20),     nil),
            ("Gym 18h 1 tiếng rưỡi",                   "Gym",              d(10, 13, 18),     90),
            ("Lunch with Minh tomorrow 12:30",         "Lunch with Minh",  d(10, 14, 12, 30), nil),
            ("Khám răng 14/10 8h sáng",                "Khám răng",        d(10, 14, 8),      nil),
            ("Dentist on Friday at 3pm for 2 hours",   "Dentist",          d(10, 16, 15),     120),
            ("Học tiếng Anh thứ hai 19:00 90 phút",    "Học tiếng Anh",    d(10, 19, 19),     90),
            ("Chạy bộ ngày mai 6h sáng 30p",           "Chạy bộ",          d(10, 14, 6),      30),
            ("Ăn tối nay",                             "Ăn tối",           d(10, 13, 19),     nil),
            ("Họp 15:00-16:30",                        "Họp",              d(10, 13, 15),     90),
            ("Sinh nhật Mai 20/10",                    "Sinh nhật Mai",    d(10, 20, 9),      nil),
            ("Call mom at 9am tomorrow",               "Call mom",         d(10, 14, 9),      nil),
            ("Đi chợ 9h",                              "Đi chợ",           d(10, 14, 9),      nil),
            ("Review 3:30 pm",                         "Review",           d(10, 13, 15, 30), nil),
            ("Họp lần thứ 2 lúc 3h chiều",             "Họp lần thứ 2",    d(10, 13, 15),     nil),
            ("Mai họp 9h",                             "Họp",              d(10, 14, 9),      nil),
            ("Thứ 7 tuần sau đi Đà Lạt",               "Đi Đà Lạt",        d(10, 24, 9),      nil),
            ("Team sync next Monday 10:00 for 45 minutes", "Team sync",    d(10, 19, 10),     45),
            ("Xem phim tối mai",                       "Xem phim",         d(10, 14, 19),     nil),
            ("Ăn trưa với khách 12h trưa thứ 5",       "Ăn trưa với khách", d(10, 15, 12),    nil),
            ("Đón con 3 giờ chiều chủ nhật",           "Đón con",          d(10, 18, 15),     nil),
            ("Họp 3h trong 1h",                        "Họp",              d(10, 13, 15),     60),
            ("Standup 9am",                            "Standup",          d(10, 14, 9),      nil),
            ("Nộp báo cáo ngày 14",                    "Nộp báo cáo",      d(10, 14, 9),      nil),
            ("Họp vào lúc 7h tối ngày 1/11",           "Họp",              d(11, 1, 19),      nil),
            ("Họp từ 3h chiều đến 5h",                 "Họp",              d(10, 13, 15),     120),
            ("Meeting 3pm to 4:30pm",                  "Meeting",          d(10, 13, 15),     90)
        ]
        let noMatch = ["Mua sữa", "Gym 1 tiếng", "Lớp 12A", "Sắp xếp thứ tự", "Gặp Mai"]

        var failures: [String] = []
        for c in cases {
            guard let r = parse(c.input, now: now, calendar: cal) else {
                failures.append("\"\(c.input)\" → nil")
                continue
            }
            if r.title != c.title || r.start != c.start || r.durationMinutes != c.minutes {
                failures.append("\"\(c.input)\" → title \"\(r.title)\", start \(String(describing: r.start)), "
                                + "minutes \(String(describing: r.durationMinutes)); expected \"\(c.title)\", "
                                + "\(c.start), \(String(describing: c.minutes))")
            }
        }
        for input in noMatch {
            if let r = parse(input, now: now, calendar: cal) {
                failures.append("\"\(input)\" should not match, got \(r)")
            }
        }
        for f in failures { print("QuickAddParser self-test FAILED: \(f)") }
        assert(failures.isEmpty, "QuickAddParser self-test: \(failures.count) failure(s)")
        if failures.isEmpty { print("QuickAddParser self-test passed (\(cases.count + noMatch.count) cases)") }
    }
}
#endif
