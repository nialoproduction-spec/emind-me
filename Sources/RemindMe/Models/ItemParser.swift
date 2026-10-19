import Foundation

/// What free text was understood as, before it's saved. Shown to the user
/// for confirmation — this parser is a set of local heuristics, not magic,
/// so the confirmation step is where mistakes get caught and fixed.
struct ParsedItem {
    var kind: ItemKind
    var title: String
    var intervalSeconds: Double?
    var hour: Int?
    var minute: Int?
    var weekdays: Set<Int>
    var targetDate: Date?
    /// From a hashtag in the text ("#work" → "Work").
    var category: String? = nil
    /// Set for "rest every 40 min and take a 10 min break": saving starts the
    /// menu bar break timer instead of adding a routine.
    var breakCycle: BreakCycleConfig? = nil
    /// What the person picked in the confirmation bar; nil = the default.
    var chosen: ItemType? = nil

    /// Has a time or interval, so it can be a reminder or a habit.
    var hasSchedule: Bool { kind != .goal }

    /// Reminder, habit or goal. Text with a time or interval starts out as a
    /// reminder (the quiet one); text without starts out as a goal.
    var type: ItemType {
        if let chosen, chosen == .goal || hasSchedule { return chosen }
        return hasSchedule ? .reminder : .goal
    }

    /// Schedule description for the confirmation banner (title shown separately).
    var detailLine: String {
        if let breakCycle {
            return "\(breakCycle.breakMinutes) min break · repeats until you stop it"
        }
        if type == .goal, kind != .goal { return "8 PM check-in" }
        switch kind {
        case .repeatingRoutine:
            guard let intervalSeconds else { return "" }
            return "every \(Item.durationString(intervalSeconds))"
        case .scheduledRoutine:
            guard let hour, let minute else { return "" }
            let time = Item.clockTimeString(hour: hour, minute: minute)
            if weekdays.isEmpty || weekdays.count == 7 { return "\(time) · Daily" }
            let symbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return "\(time) · " + weekdays.sorted().map { symbols[$0] }.joined(separator: ", ")
        case .goal:
            guard let targetDate else { return "No date" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "by \(formatter.string(from: targetDate))"
        }
    }

    var kindLabel: String {
        if breakCycle != nil { return "Break timer" }
        return type.label
    }
}

/// Local, on-device natural-language classification — no network call, no
/// model download, just regexes and small word lists. That matches the
/// app's "no cloud, no account" brief, and keeps this instant.
enum ItemParser {
    static func parse(_ raw: String) -> ParsedItem {
        // Hashtags first: "#work" anywhere sets the category and is taken out
        // of the text before anything else reads it.
        let (withoutTags, category) = extractCategory(from: raw)
        // A break phrase ("and take a 10 min break") is cut out first, so its
        // number can't be mistaken for part of the "every 40 min" interval.
        if let rest = breakPhrase(in: withoutTags) {
            let schedule = (withoutTags as NSString).replacingCharacters(in: rest.range, with: " ")
            var cycle = parseSchedule(schedule)
            if cycle.kind == .repeatingRoutine, let interval = cycle.intervalSeconds {
                let work = max(1, Int((interval / 60).rounded()))
                let breakMinutes = max(1, Int((rest.seconds / 60).rounded()))
                cycle.category = category
                cycle.breakCycle = BreakCycleConfig(workMinutes: work, breakMinutes: breakMinutes)
                cycle.title = "Rest every \(work) min"
                return cycle
            }
        }
        var parsed = parseSchedule(withoutTags)
        parsed.category = category
        return parsed
    }

    /// A break named in the text ("take a 10 min break", "break for ten
    /// minutes"): its length in seconds and where it sits in the text.
    static func breakPhrase(in text: String) -> (seconds: Double, range: NSRange)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for regex in [breakAfterRegex, breakBeforeRegex] {
            guard let match = regex.firstMatch(in: text, range: full) else { continue }
            let quantity = parseQuantity(ns.substring(with: match.range(withName: "qty")))
            let unit = ns.substring(with: match.range(withName: "unit")).lowercased()
            if let quantity, quantity > 0 { return (quantity * unitSeconds(unit), match.range) }
        }
        return nil
    }

    /// A number as digits or words ("10", "ten", "forty five") — and nothing
    /// else, so surrounding words can't leak into the amount.
    private static let breakQuantity: String = {
        let word = "(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)"
        return #"(?:\d+(?:\.\d+)?|"# + word + #"(?:[\s-]"# + word + #")?)"#
    }()

    /// "10 min break", "ten-minute break".
    private static let breakAfterRegex = try! NSRegularExpression(
        pattern: #"\b(?<qty>"# + breakQuantity + #")\s*-?\s*(?<unit>minutes?|mins?|hours?|hrs?)\s+break\b"#,
        options: [.caseInsensitive]
    )

    /// "break of 10 minutes", "break for ten min".
    private static let breakBeforeRegex = try! NSRegularExpression(
        pattern: #"\bbreak\s+(?:of|for|is|lasting)?\s*(?<qty>"# + breakQuantity + #")\s*(?<unit>minutes?|mins?|hours?|hrs?)\b"#,
        options: [.caseInsensitive]
    )

    /// The first "#tag" becomes the category (capitalised); all tags are removed.
    static func extractCategory(from text: String) -> (text: String, category: String?) {
        let ns = text as NSString
        let matches = hashtagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else { return (text, nil) }
        let tag = ns.substring(with: first.range(at: 1))
        let category = tag.prefix(1).uppercased() + tag.dropFirst().lowercased()
        let stripped = NSMutableString(string: text)
        for match in matches.reversed() { stripped.deleteCharacters(in: match.range) }
        let cleaned = (stripped as String)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return (cleaned, category)
    }

    private static let hashtagRegex = try! NSRegularExpression(pattern: #"#(\p{L}[\p{L}\p{N}_-]*)"#)

    private static func parseSchedule(_ raw: String) -> ParsedItem {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedItem(kind: .goal, title: "Untitled", intervalSeconds: nil,
                              hour: nil, minute: nil, weekdays: [], targetDate: nil)
        }

        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var stripRanges: [NSRange] = []

        // 1. Explicit repeating interval ("every 40 minutes", "every 3 days").
        // "every day" / "every week" alone (no quantity) is deliberately NOT
        // an interval — that's a daily/weekly *schedule* signal, handled below.
        var intervalSeconds: Double?
        if let match = intervalRegex.firstMatch(in: trimmed, range: fullRange) {
            let unitRange = match.range(withName: "unit")
            let qtyRange = match.range(withName: "qty")
            let unit = ns.substring(with: unitRange).lowercased()
            let qtyPhrase = qtyRange.location != NSNotFound ? ns.substring(with: qtyRange) : nil
            let isDayOrWeek = unit.hasPrefix("day") || unit.hasPrefix("week")
            if !(isDayOrWeek && qtyPhrase == nil) {
                let quantity = qtyPhrase.flatMap(parseQuantity) ?? 1
                if quantity > 0 {
                    intervalSeconds = quantity * unitSeconds(unit)
                    stripRanges.append(match.range)
                }
            }
        }

        // 2. Clock time ("at 4am", "at seven a.m.", "noon") — only looked for
        // when there's no interval, since an interval already makes this a
        // repeating routine.
        var hour: Int?
        var minute: Int?
        if intervalSeconds == nil {
            if let match = clockAtRegex.firstMatch(in: trimmed, range: fullRange) {
                let hourPhrase = ns.substring(with: match.range(withName: "hour")).lowercased()
                let minuteRange = match.range(withName: "minute")
                let ampmRange = match.range(withName: "ampm")
                var parsedHour = Int(hourPhrase) ?? wordNumbers[hourPhrase].map(Int.init) ?? -1
                let parsedMinute = minuteRange.location != NSNotFound
                    ? Int(ns.substring(with: minuteRange)) ?? 0 : 0
                var ampm = ampmRange.location != NSNotFound
                    ? ns.substring(with: ampmRange).lowercased() : nil
                if ampm?.contains("o'clock") == true { ampm = nil }

                let isPM = ampm?.hasPrefix("p") == true
                let isAM = ampm?.hasPrefix("a") == true
                var isValidTime = false
                if isPM || isAM {
                    // 12-hour clock: only 1–12 make sense with am/pm.
                    if (1...12).contains(parsedHour) {
                        if isPM, parsedHour != 12 { parsedHour += 12 }
                        if isAM, parsedHour == 12 { parsedHour = 0 }
                        isValidTime = true
                    }
                } else if (0...23).contains(parsedHour) {
                    // No am/pm: 13–23 read as a 24-hour clock ("at 16:30").
                    // A bare "at 9" reads as 9am and "at 12" as noon — both
                    // defaults the confirmation step shows before saving.
                    isValidTime = true
                }
                if isValidTime, (0...59).contains(parsedMinute) {
                    hour = parsedHour
                    minute = parsedMinute
                    stripRanges.append(match.range)
                }
            } else if let match = clockWordRegex.firstMatch(in: trimmed, range: fullRange) {
                let word = ns.substring(with: match.range).lowercased()
                hour = word == "noon" ? 12 : 0
                minute = 0
                stripRanges.append(match.range)
            }
        }

        // 3. Weekday / daily repeat signal.
        var weekdays = Set<Int>()
        for matcher in weekdayMatchers {
            for match in matcher.regex.matches(in: trimmed, range: fullRange) {
                weekdays.formUnion(matcher.weekdays)
                stripRanges.append(match.range)
            }
        }

        // Classify.
        let kind: ItemKind
        if let intervalSeconds, intervalSeconds > 0 {
            kind = .repeatingRoutine
        } else if hour != nil {
            kind = .scheduledRoutine
        } else {
            kind = .goal
        }

        // 4. Goals only: an optional target date, found with the system's
        // own date detector rather than more hand-rolled regex.
        var targetDate: Date?
        if kind == .goal,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            if let match = detector.matches(in: trimmed, range: fullRange).first, let date = match.date {
                targetDate = date
                stripRanges.append(match.range)
            }
        }

        let title = buildTitle(from: trimmed, stripping: stripRanges)

        return ParsedItem(
            kind: kind, title: title, intervalSeconds: intervalSeconds,
            hour: hour, minute: minute, weekdays: weekdays, targetDate: targetDate
        )
    }

    // MARK: - Title cleanup

    private static func buildTitle(from text: String, stripping ranges: [NSRange]) -> String {
        let mutable = NSMutableString(string: text)
        // Delete right-to-left so earlier ranges' offsets stay valid; merge
        // any overlapping matches first so a deletion never double-counts.
        for range in mergedRanges(ranges).sorted(by: { $0.location > $1.location }) {
            guard range.location != NSNotFound, range.location + range.length <= mutable.length else { continue }
            mutable.deleteCharacters(in: range)
        }

        let stopwords: Set<String> = ["to", "at", "on", "by", "for", "every", "the", "a", "an", "is", "and", "of"]
        var tokens = (mutable as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:")) }
            .filter { !$0.isEmpty }

        while let first = tokens.first, stopwords.contains(first.lowercased()) { tokens.removeFirst() }
        while let last = tokens.last, stopwords.contains(last.lowercased()) { tokens.removeLast() }

        var result = tokens.joined(separator: " ")
        if result.isEmpty { result = "Untitled" }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let valid = ranges.filter { $0.location != NSNotFound }.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in valid {
            if let last = result.last, range.location <= last.location + last.length {
                let end = max(last.location + last.length, range.location + range.length)
                result[result.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: - Quantity / unit helpers

    static func unitSeconds(_ unit: String) -> Double {
        if unit.hasPrefix("sec") { return 1 }
        if unit.hasPrefix("min") { return 60 }
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") { return 3600 }
        if unit.hasPrefix("day") { return 86400 }
        if unit.hasPrefix("week") { return 604800 }
        return 60
    }

    static func parseQuantity(_ raw: String) -> Double? {
        let cleaned = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.contains("half") { return 0.5 }
        if let value = Double(cleaned) { return value }
        if cleaned == "a" || cleaned == "an" { return 1 }
        let tokens = cleaned.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
        var total = 0.0
        var matchedAny = false
        for token in tokens {
            if let value = wordNumbers[token] {
                total += value
                matchedAny = true
            }
        }
        return matchedAny ? total : nil
    }

    private static let wordNumbers: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    // MARK: - Weekday matchers

    private struct WeekdayMatcher {
        let regex: NSRegularExpression
        let weekdays: Set<Int>
    }

    /// Calendar weekday ints: 1 = Sunday ... 7 = Saturday.
    private static let weekdayMatchers: [WeekdayMatcher] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return [
            // Contributes no weekdays (empty set means "every day" already),
            // but still needs to be stripped out of the title text.
            WeekdayMatcher(regex: regex(#"\bevery\s+day\b|\bdaily\b|\beveryday\b"#), weekdays: []),
            WeekdayMatcher(regex: regex(#"\bsun(day)?s?\b"#), weekdays: [1]),
            WeekdayMatcher(regex: regex(#"\bmon(day)?s?\b"#), weekdays: [2]),
            WeekdayMatcher(regex: regex(#"\btue(s(day)?)?\b"#), weekdays: [3]),
            WeekdayMatcher(regex: regex(#"\bwed(nesday)?s?\b"#), weekdays: [4]),
            WeekdayMatcher(regex: regex(#"\bthu(r(s(day)?)?)?\b"#), weekdays: [5]),
            WeekdayMatcher(regex: regex(#"\bfri(day)?s?\b"#), weekdays: [6]),
            WeekdayMatcher(regex: regex(#"\bsat(urday)?s?\b"#), weekdays: [7]),
            WeekdayMatcher(regex: regex(#"\bweekdays?\b"#), weekdays: [2, 3, 4, 5, 6]),
            WeekdayMatcher(regex: regex(#"\bweekends?\b"#), weekdays: [1, 7]),
        ]
    }()

    // MARK: - Regexes

    private static let intervalRegex = try! NSRegularExpression(
        pattern: #"every\s+(?:(?<qty>[a-z]+(?:[\s-][a-z]+)*|\d+(?:\.\d+)?)\s+)?(?<unit>seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?)\b"#,
        options: [.caseInsensitive]
    )

    private static let clockAtRegex = try! NSRegularExpression(
        pattern: #"\bat\s+(?<hour>\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s*:\s*(?<minute>\d{2}))?\s*(?<ampm>a\.?m\.?|p\.?m\.?|o'clock)?"#,
        options: [.caseInsensitive]
    )

    private static let clockWordRegex = try! NSRegularExpression(
        pattern: #"\b(noon|midnight)\b"#,
        options: [.caseInsensitive]
    )
}
