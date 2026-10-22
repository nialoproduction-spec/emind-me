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
    /// One-time: "tomorrow 3pm", "Nov 5 at 10am", "in 2 hours".
    var onceAt: Date? = nil
    /// Monthly on this day ("pay rent on the 1st"), or yearly with `yearMonth`.
    var monthDay: Int? = nil
    var yearMonth: Int? = nil
    /// Deadline ("Sharma teaser due Nov 10"): nudges 7, 3, 1 day before.
    var dueDate: Date? = nil
    /// "choosing music within 30 min": a timer that counts down in the list.
    var timer: TimerRequest? = nil

    /// Has a time or interval, so it can be a reminder or a habit.
    var hasSchedule: Bool { kind != .goal }

    /// Reminder, habit or goal. Text with a time or interval starts out as a
    /// reminder (the quiet one); text without starts out as a goal.
    var type: ItemType {
        if let chosen, chosen == .goal || hasSchedule { return chosen }
        if timer != nil { return .reminder }
        return hasSchedule ? .reminder : .goal
    }

    /// Schedule description for the confirmation banner (title shown separately).
    var detailLine: String {
        if let timer {
            return "Timer · \(Int((timer.seconds / 60).rounded())) min"
        }
        if let breakCycle {
            return "\(BreakCycleConfig.short(breakCycle.breakSeconds)) break · repeats until you turn it off"
        }
        if type == .goal, kind != .goal { return "8 PM check-in" }
        switch kind {
        case .repeatingRoutine:
            guard let intervalSeconds else { return "" }
            return "every \(Item.durationString(intervalSeconds))"
        case .scheduledRoutine:
            if dueDate != nil {
                let line = Item.specialSummary(repeat: .deadline, onceAt: nil, monthDay: nil, yearMonth: nil,
                                               dueDate: dueDate, hour: hour, minute: minute) ?? ""
                return line + " · nudges 7, 3, 1 day before"
            }
            let special: Item.Repeat? = onceAt != nil ? .once
                : monthDay != nil ? (yearMonth != nil ? .yearly : .monthly) : nil
            if let special, let line = Item.specialSummary(repeat: special, onceAt: onceAt, monthDay: monthDay,
                                                           yearMonth: yearMonth, dueDate: nil,
                                                           hour: hour, minute: minute) {
                return line
            }
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
    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedItem {
        // Typos in "every" ("evry", "rvry 4 min") are fixed and "remind me
        // to" is dropped first, so they never reach the title or the rules.
        let fixed = fixEveryTypos(raw)
        let cleaned = dropLeadIn(fixed)
        // "remind me to …" with a date but no time is a reminder (9 AM), not a goal.
        let askedToRemind = cleaned != fixed
        // Hashtags first: "#work" anywhere sets the category and is taken out
        // of the text before anything else reads it.
        let (withoutTags, category) = extractCategory(from: cleaned)
        // "work 25 min and rest 5 min", "work every 1 minute break every 10
        // minute", "40 min work 10 min rest": both lengths named outright.
        if let (work, rest) = workAndRest(in: withoutTags) {
            let config = BreakCycleConfig(workSeconds: Int(work.rounded()), breakSeconds: Int(rest.rounded()))
            var cycle = ParsedItem(kind: .repeatingRoutine, title: config.title, intervalSeconds: work,
                                   hour: nil, minute: nil, weekdays: [], targetDate: nil)
            cycle.category = category
            cycle.breakCycle = config
            return cycle
        }
        // A break phrase ("and take a 10 min break") is cut out first, so its
        // number can't be mistaken for part of the "every 40 min" interval.
        if let rest = breakPhrase(in: withoutTags) {
            let schedule = (withoutTags as NSString).replacingCharacters(in: rest.range, with: " ")
            var cycle = parseSchedule(schedule, now: now, calendar: calendar, askedToRemind: askedToRemind)
            if cycle.kind == .repeatingRoutine, let interval = cycle.intervalSeconds {
                let config = BreakCycleConfig(workSeconds: Int(interval.rounded()), breakSeconds: Int(rest.seconds.rounded()))
                cycle.category = category
                cycle.breakCycle = config
                cycle.title = "Rest every \(BreakCycleConfig.short(config.workSeconds))"
                return cycle
            }
        }
        // "choosing music within 30 min": a timer, not a reminder or a goal.
        if !askedToRemind, let request = TimerRequest.parse(withoutTags) {
            var timer = ParsedItem(kind: .goal, title: request.title, intervalSeconds: nil, hour: nil,
                                   minute: nil, weekdays: [], targetDate: nil)
            timer.category = category ?? request.category
            timer.timer = request
            return timer
        }
        var parsed = parseSchedule(withoutTags, now: now, calendar: calendar, askedToRemind: askedToRemind)
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

    // MARK: - Clean-up before parsing

    /// "remind me to drink water…" → "drink water…". Also "please remind
    /// me to", "remind me about", "reminder:", "don't forget to".
    static func dropLeadIn(_ text: String) -> String {
        let ns = text as NSString
        guard let match = leadInRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        let rest = ns.substring(from: match.range.location + match.range.length)
        return rest.trimmingCharacters(in: .whitespaces).isEmpty ? text : rest
    }

    private static let leadInRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:please\s+)?(?:(?:remind|rmind|remid|remnd)\s+me\s+(?:to\s+|about\s+|that\s+)?|reminder\s*(?::|to\b)?\s*|(?:don'?t|dont|do\s+not)\s+forget\s+(?:to\s+)?)"#,
        options: [.caseInsensitive]
    )

    /// A word that's close to "every" ("evry", "rvry", "rvrry", "evrey") and
    /// is followed by a number or a unit becomes "every". Real words that
    /// look alike ("over", "even") are left alone.
    static func fixEveryTypos(_ text: String) -> String {
        let ns = text as NSString
        let matches = everyTypoRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let word = ns.substring(with: match.range).lowercased()
            guard word != "every", !["over", "even", "eve"].contains(word),
                  editDistance(word, "every") <= 2 else { continue }
            result.replaceCharacters(in: match.range, with: "every")
        }
        return result as String
    }

    private static let everyTypoRegex = try! NSRegularExpression(
        pattern: #"\b[a-z]{3,7}\b(?=\s*(?:\d|(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty|fifty|sixty|half)\b|(?:sec|min|hour|hr|day|week)[a-z]*\b))"#,
        options: [.caseInsensitive]
    )

    /// Levenshtein distance; words here are a few letters, so the simple
    /// table is plenty.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Work and rest lengths (seconds) when the text names both with the
    /// words "work" and "rest"/"break". The work part is cut out before the
    /// rest part is looked for, so one number is never read twice.
    static func workAndRest(in text: String) -> (work: Double, rest: Double)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        // "40 min work 10 min rest" must read 40 as the work, so the
        // number-first form is tried first.
        for regex in [workAfterRegex, workBeforeRegex] {
            guard let match = regex.firstMatch(in: text, range: full),
                  let work = seconds(in: ns, match) else { continue }
            let remainder = ns.replacingCharacters(in: match.range, with: " ")
            let rns = remainder as NSString
            let rfull = NSRange(location: 0, length: rns.length)
            for restRegex in [restBeforeRegex, breakAfterRegex] {
                if let restMatch = restRegex.firstMatch(in: remainder, range: rfull),
                   let rest = seconds(in: rns, restMatch) {
                    return (work, rest)
                }
            }
        }
        return nil
    }

    private static func seconds(in ns: NSString, _ match: NSTextCheckingResult) -> Double? {
        guard let quantity = parseQuantity(ns.substring(with: match.range(withName: "qty"))), quantity > 0 else { return nil }
        return quantity * unitSeconds(ns.substring(with: match.range(withName: "unit")).lowercased())
    }

    /// Units, long forms first so "min" never stops short of "minutes";
    /// h / m / s only as whole words ("40m", "2 h", "30s").
    private static let durationUnit = #"(?:hou?r[a-z]*|hr[a-z]*|h|min[a-z]*|m|sec[a-z]*|s)\b"#

    /// "work 40 min", "work for 25 minutes", "work every 1 minute", "focus 2h".
    private static let workBeforeRegex = try! NSRegularExpression(
        pattern: #"\b(?:work|working|focus|study)\s+(?:for\s+|every\s+)?(?<qty>"# + breakQuantity + #")\s*-?\s*(?<unit>"# + durationUnit + #")"#,
        options: [.caseInsensitive]
    )

    /// "40 min work", "25-minute focus", "1 hr of work".
    private static let workAfterRegex = try! NSRegularExpression(
        // Not when the number belongs to a rest ("rest 5 min work 25 min").
        pattern: #"(?<!rest\s)(?<!break\s)(?<!relax\s)\b(?<qty>"# + breakQuantity + #")\s*-?\s*(?<unit>"# + durationUnit + #")\s+(?:of\s+)?(?:work|focus|study)\b"#,
        options: [.caseInsensitive]
    )

    /// "rest 1 minute", "break every 10 minute", "rest for 5 min", "relax 30 sec".
    private static let restBeforeRegex = try! NSRegularExpression(
        pattern: #"\b(?:rest|break|relax|pause)\s+(?:for\s+|every\s+|of\s+|is\s+)?(?<qty>"# + breakQuantity + #")\s*-?\s*(?<unit>"# + durationUnit + #")"#,
        options: [.caseInsensitive]
    )

    /// A number as digits or words ("10", "ten", "forty five") — and nothing
    /// else, so surrounding words can't leak into the amount.
    private static let breakQuantity: String = {
        let word = "(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)"
        return #"(?:\d+(?:\.\d+)?|"# + word + #"(?:[\s-]"# + word + #")?)"#
    }()

    /// "10 min break", "ten-minute break".
    private static let breakAfterRegex = try! NSRegularExpression(
        pattern: #"\b(?<qty>"# + breakQuantity + #")\s*-?\s*(?<unit>"# + durationUnit + #")\s+(?:of\s+)?(?:break|rest)\b"#,
        options: [.caseInsensitive]
    )

    /// "break of 10 minutes", "break for ten min".
    private static let breakBeforeRegex = try! NSRegularExpression(
        pattern: #"\bbreak\s+(?:of|for|is|lasting)?\s*(?<qty>"# + breakQuantity + #")\s*(?<unit>"# + durationUnit + #")"#,
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

    private static func parseSchedule(_ raw: String, now: Date, calendar: Calendar,
                                      askedToRemind: Bool) -> ParsedItem {
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
            func group(_ names: [String]) -> String? {
                for name in names {
                    let range = match.range(withName: name)
                    if range.location != NSNotFound { return ns.substring(with: range) }
                }
                return nil
            }
            let unit = (group(["unit", "unit2", "unit3"]) ?? "").lowercased()
            let qtyPhrase = group(["qty", "qty2"])
            let isDayOrWeek = unit.hasPrefix("d") || unit.hasPrefix("w")
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
            } else if let time = bareClockTime(in: trimmed) {
                // No "at": "every 6pm", "6:30 pm", "9.15am", "21:00".
                hour = time.hour
                minute = time.minute
                stripRanges.append(time.range)
            } else if let match = clockWordRegex.firstMatch(in: trimmed, range: fullRange) {
                let word = ns.substring(with: match.range).lowercased()
                hour = word == "noon" ? 12 : 0
                minute = 0
                stripRanges.append(match.range)
            }
        }

        // 3. Dates: one-time ("tomorrow", "Nov 5", "in 2 hours"), monthly
        // ("on the 1st"), yearly ("every Mar 12"), deadlines ("due Nov 10").
        if intervalSeconds == nil,
           var dated = datedSchedule(in: trimmed, hour: hour, minute: minute, now: now, calendar: calendar,
                                     askedToRemind: askedToRemind) {
            stripRanges += dated.ranges
            dated.item.title = buildTitle(from: trimmed, stripping: stripRanges)
            return dated.item
        }

        // 4. Weekday / daily repeat signal.
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

    // MARK: - Dates

    /// One-time, monthly, yearly and deadline schedules, worked out from the
    /// text (`hour` / `minute`: a clock time already found in it). Nil when
    /// there's no date, or a date with no time that reads as a goal's target
    /// ("finish the album by Nov 5").
    static func datedSchedule(in text: String, hour: Int?, minute: Int?, now: Date, calendar: Calendar,
                              askedToRemind: Bool) -> (item: ParsedItem, ranges: [NSRange])? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        func base() -> ParsedItem {
            ParsedItem(kind: .scheduledRoutine, title: "", intervalSeconds: nil, hour: hour, minute: minute,
                       weekdays: [], targetDate: nil)
        }
        func at(_ day: Date, defaultHour: Int) -> Date {
            calendar.date(bySettingHour: hour ?? defaultHour, minute: hour == nil ? 0 : (minute ?? 0),
                          second: 0, of: day) ?? day
        }

        let dueMatch = deadlineRegex.firstMatch(in: text, range: full)
        let monthDate = monthDayDate(in: text)
        let relative = relativeDay(in: text, now: now, calendar: calendar)
        let soon = Self.inDuration(in: text)

        // Deadline: "due Nov 10", "deadline tomorrow", "due in 3 days".
        if let dueMatch {
            var day: Date?
            if let monthDate {
                day = monthDate.date(now: now, calendar: calendar)
                ranges.append(monthDate.range)
            } else if let relative {
                day = relative.day
                ranges.append(relative.range)
            } else if let soon {
                day = now.addingTimeInterval(soon.seconds)
                ranges.append(soon.range)
            }
            if let day {
                ranges.append(dueMatch.range)
                var item = base()
                let due = calendar.startOfDay(for: day)
                item.dueDate = due
                item.hour = hour ?? 10
                item.minute = hour == nil ? 0 : (minute ?? 0)
                return (item, ranges)
            }
        }

        // "in 2 hours", "in 30 min": once, from now.
        if let soon {
            var item = base()
            let when = now.addingTimeInterval(soon.seconds)
            item.onceAt = when
            let parts = calendar.dateComponents([.hour, .minute], from: when)
            item.hour = parts.hour
            item.minute = parts.minute
            return (item, [soon.range])
        }

        let everyYear = everyYearRegex.firstMatch(in: text, range: full)
        let yearlyWord = yearlyWordRegex.firstMatch(in: text, range: full) != nil
        let everyMonth = everyMonthRegex.firstMatch(in: text, range: full)

        if let monthDate {
            ranges.append(monthDate.range)
            // "every Mar 12", "Mar 12 every year", birthdays and anniversaries.
            if monthDate.everyBefore || everyYear != nil || yearlyWord {
                if let everyYear { ranges.append(everyYear.range) }
                var item = base()
                item.monthDay = monthDate.day
                item.yearMonth = monthDate.month
                item.hour = hour ?? 9
                item.minute = hour == nil ? 0 : (minute ?? 0)
                return (item, ranges)
            }
            // A date with no time and no "remind me": a goal's target date.
            guard hour != nil || askedToRemind else { return nil }
            var item = base()
            item.onceAt = at(monthDate.date(now: now, calendar: calendar), defaultHour: 9)
            item.hour = hour ?? 9
            item.minute = hour == nil ? 0 : (minute ?? 0)
            return (item, ranges)
        }

        // "on the 1st", "every 15th", "1st of every month", "monthly".
        let ordinal = ordinalDay(in: text)
        if ordinal != nil || everyMonth != nil {
            if let ordinal { ranges.append(ordinal.range) }
            if let everyMonth { ranges.append(everyMonth.range) }
            var item = base()
            item.monthDay = ordinal?.day ?? calendar.component(.day, from: now)
            item.hour = hour ?? 9
            item.minute = hour == nil ? 0 : (minute ?? 0)
            return (item, ranges)
        }

        // "every year" / "yearly" with no date: on today's date each year.
        if let everyYear {
            var item = base()
            item.monthDay = calendar.component(.day, from: now)
            item.yearMonth = calendar.component(.month, from: now)
            item.hour = hour ?? 9
            item.minute = hour == nil ? 0 : (minute ?? 0)
            return (item, [everyYear.range])
        }

        // "tomorrow 3pm", "tonight", "today at 5".
        if let relative {
            // No time and no "remind me" ("finish the edit tomorrow"): a goal.
            guard hour != nil || askedToRemind else { return nil }
            var item = base()
            let when = at(relative.day, defaultHour: relative.defaultHour)
            item.onceAt = when
            item.hour = calendar.component(.hour, from: when)
            item.minute = calendar.component(.minute, from: when)
            return (item, [relative.range])
        }
        return nil
    }

    struct MonthDate {
        let month: Int
        let day: Int
        let year: Int?
        let range: NSRange
        /// "every" right before it: yearly.
        let everyBefore: Bool

        /// This date at the start of its day: this year, or next year once
        /// it has gone (unless a year was written).
        func date(now: Date, calendar: Calendar) -> Date {
            let thisYear = calendar.component(.year, from: now)
            var comps = DateComponents(year: year ?? thisYear, month: month, day: day)
            var date = calendar.date(from: comps) ?? now
            if year == nil, date < calendar.startOfDay(for: now) {
                comps.year = thisYear + 1
                date = calendar.date(from: comps) ?? date
            }
            return date
        }
    }

    private static let monthPattern = #"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"#

    private static let monthDateRegex = try! NSRegularExpression(
        pattern: #"(?<every>\b(?:every|each)\s+)?(?:\bon\s+)?(?:\b(?<mon>"# + monthPattern + #")\.?\s+(?<day>\d{1,2})(?:st|nd|rd|th)?|\b(?:the\s+)?(?<day2>\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(?<mon2>"# + monthPattern + #")\.?)(?:,?\s+(?<year>20\d{2}))?(?![a-z0-9])"#,
        options: [.caseInsensitive]
    )

    /// "Nov 5", "November 5th", "5 Nov", "the 5th of November", "Mar 12, 2027".
    static func monthDayDate(in text: String) -> MonthDate? {
        let ns = text as NSString
        for match in monthDateRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func part(_ name: String) -> String? {
                let range = match.range(withName: name)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            guard let monthWord = part("mon") ?? part("mon2"),
                  let dayText = part("day") ?? part("day2"), let day = Int(dayText) else { continue }
            // "may" is also an everyday word: only "May" counts.
            if monthWord.lowercased() == "may", monthWord.first?.isUppercase != true { continue }
            let month = monthIndex(monthWord)
            guard month > 0, (1...monthLength(month)).contains(day) else { continue }
            return MonthDate(month: month, day: day, year: part("year").flatMap { Int($0) },
                             range: match.range, everyBefore: part("every") != nil)
        }
        return nil
    }

    static func monthIndex(_ word: String) -> Int {
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let start = String(word.lowercased().prefix(3))
        return (prefixes.firstIndex(of: start) ?? -1) + 1
    }

    /// Longest the month can be (February: 29, so leap-day birthdays work).
    private static func monthLength(_ month: Int) -> Int {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    private static let ordinalRegex = try! NSRegularExpression(
        pattern: #"(?:\b(?:on|every|each)\s+(?:the\s+)?|\bthe\s+)(?<day>\d{1,2})(?:st|nd|rd|th)\b(?:\s+of\s+(?:every|each|the|a)\s+month)?|\b(?<day2>\d{1,2})(?:st|nd|rd|th)\s+of\s+(?:every|each|the|a)\s+month\b"#,
        options: [.caseInsensitive]
    )

    /// "on the 1st", "every 15th", "the 5th", "1st of every month" (not "my
    /// 2nd draft": it needs "on" / "every" / "the" before, or "of the month" after).
    static func ordinalDay(in text: String) -> (day: Int, range: NSRange)? {
        let ns = text as NSString
        guard let match = ordinalRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let range = match.range(withName: "day").location != NSNotFound ? match.range(withName: "day") : match.range(withName: "day2")
        guard range.location != NSNotFound, let day = Int(ns.substring(with: range)), (1...31).contains(day) else { return nil }
        return (day, match.range)
    }

    private static let relativeRegex = try! NSRegularExpression(
        pattern: #"\b(?:(?<after>day\s+after\s+tomorrow)|(?<tomorrow>tomorrow|tmrw|tmr|tomorow|tommorow|tommorrow)|(?<tonight>tonight|tonite)|(?<today>today))\b(?:\s+(?:morning|evening|night))?"#,
        options: [.caseInsensitive]
    )

    /// "today", "tonight" (8 PM), "tomorrow" (9 AM), "day after tomorrow".
    static func relativeDay(in text: String, now: Date, calendar: Calendar)
        -> (day: Date, defaultHour: Int, range: NSRange)? {
        let ns = text as NSString
        guard let match = relativeRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let today = calendar.startOfDay(for: now)
        func has(_ name: String) -> Bool { match.range(withName: name).location != NSNotFound }
        let phrase = ns.substring(with: match.range).lowercased()
        let evening = phrase.hasSuffix("evening") || phrase.hasSuffix("night")
        if has("after") {
            return (calendar.date(byAdding: .day, value: 2, to: today) ?? today, evening ? 19 : 9, match.range)
        }
        if has("tomorrow") {
            return (calendar.date(byAdding: .day, value: 1, to: today) ?? today, evening ? 19 : 9, match.range)
        }
        if has("tonight") { return (today, 20, match.range) }
        return (today, evening ? 19 : 18, match.range)
    }

    private static let inDurationRegex = try! NSRegularExpression(
        pattern: #"\bin\s+(?:(?<qty>\d+(?:\.\d+)?)\s*(?<unit>sec[a-z]*|min[a-z]*|hou?r[a-z]*|hrs?|day[a-z]*|week[a-z]*|wk[a-z]*|s|m|h|d|w)|(?<wqty>half\s+an?|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|forty-five|fifty|sixty)\s+(?<wunit>sec[a-z]*|min[a-z]*|hou?r[a-z]*|hrs?|day[a-z]*|week[a-z]*|wk[a-z]*))\b"#,
        options: [.caseInsensitive]
    )

    /// "in 2 hours", "in 30 min", "in an hour", "in half an hour", "in 3 days".
    static func inDuration(in text: String) -> (seconds: Double, range: NSRange)? {
        let ns = text as NSString
        guard let match = inDurationRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func part(_ name: String) -> String? {
            let range = match.range(withName: name)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        guard let qtyText = part("qty") ?? part("wqty"), let unit = (part("unit") ?? part("wunit"))?.lowercased(),
              let quantity = parseQuantity(qtyText), quantity > 0 else { return nil }
        return (quantity * unitSeconds(unit), match.range)
    }

    private static let deadlineRegex = try! NSRegularExpression(
        pattern: #"\b(?:due|deadline)\b(?:\s*:)?(?:\s+(?:on|by|is))?"#,
        options: [.caseInsensitive]
    )

    private static let everyYearRegex = try! NSRegularExpression(
        pattern: #"\b(?:every|each)\s+year\b|\byearly\b|\bannually\b"#,
        options: [.caseInsensitive]
    )

    /// Things that come round every year: a date with these is yearly.
    private static let yearlyWordRegex = try! NSRegularExpression(
        pattern: #"\b(?:birthday|bday|anniversary)\b"#,
        options: [.caseInsensitive]
    )

    private static let everyMonthRegex = try! NSRegularExpression(
        pattern: #"\b(?:every|each)\s+month\b|\bmonthly\b"#,
        options: [.caseInsensitive]
    )

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
        if unit.hasPrefix("s") { return 1 }
        if unit.hasPrefix("m") { return 60 }
        if unit.hasPrefix("h") { return 3600 }
        if unit.hasPrefix("d") { return 86400 }
        if unit.hasPrefix("w") { return 604800 }
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
        // Words + full unit ("every forty minutes"), digits + any unit incl.
        // shortcuts ("every 40m", "every 2 hrs", "every 30 sec"), or a bare
        // unit ("every hour"). Single-letter units only after digits.
        // Unit words tolerate typos past their first letters ("minuts",
        // "mintue", "houres").
        pattern: #"every\s+(?:(?<qty>[a-z]+(?:[\s-][a-z]+)*)\s+(?<unit>"# + unitWord + #")|(?<qty2>\d+(?:\.\d+)?)\s*(?<unit2>"# + unitWord + #"|s|m|h|d|w)|(?<unit3>"# + unitWord + #"))\b"#,
        options: [.caseInsensitive]
    )

    private static let unitWord = #"(?:sec[a-z]*|min[a-z]*|hou?r[a-z]*|hr[a-z]*|day[a-z]*|week[a-z]*|wk[a-z]*)"#

    private static let clockAtRegex = try! NSRegularExpression(
        pattern: #"\bat\s+(?<hour>\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s*:\s*(?<minute>\d{2}))?\s*(?<ampm>a\.?m\.?|p\.?m\.?|o'clock)?"#,
        options: [.caseInsensitive]
    )

    /// A clock time written without "at": "6pm", "every 6pm" (daily),
    /// "6:30 pm", "9.15am", "six pm", "21:00". It needs am/pm or a colon
    /// with minutes, so plain numbers ("3 glasses", "2 times") never count.
    /// A leading "every" / "each" goes with it, so the title stays clean.
    static func bareClockTime(in text: String) -> (hour: Int, minute: Int, range: NSRange)? {
        let ns = text as NSString
        for match in bareClockRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func part(_ name: String) -> String? {
                let range = match.range(withName: name)
                return range.location == NSNotFound ? nil : ns.substring(with: range).lowercased()
            }
            guard let hourWord = part("hour") else { continue }
            let ampm = part("ampm")
            let minute = part("minute").flatMap { Int($0) }
            // Without am/pm only "18:00"-style (a colon and minutes) counts.
            if ampm == nil, minute == nil || part("sep") != ":" { continue }
            guard var hour = Int(hourWord) ?? wordNumbers[hourWord].map(Int.init) else { continue }
            if let ampm {
                guard (1...12).contains(hour) else { continue }
                if ampm.hasPrefix("p"), hour != 12 { hour += 12 }
                if ampm.hasPrefix("a"), hour == 12 { hour = 0 }
            } else if !(0...23).contains(hour) {
                continue
            }
            let minutes = minute ?? 0
            guard (0...59).contains(minutes) else { continue }
            return (hour, minutes, match.range)
        }
        return nil
    }

    private static let bareClockRegex = try! NSRegularExpression(
        pattern: #"(?:\b(?:every|each)\s+)?\b(?<hour>\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s*(?<sep>[:.])\s*(?<minute>\d{2}))?\s*(?<ampm>a\.?m\.?|p\.?m\.?)?(?![a-z0-9])"#,
        options: [.caseInsensitive]
    )

    private static let clockWordRegex = try! NSRegularExpression(
        pattern: #"\b(noon|midnight)\b"#,
        options: [.caseInsensitive]
    )
}
