import AppKit
import Foundation
import SwiftUI

/// Settings saved as JSON in UserDefaults, observable from SwiftUI. Same
/// pattern as the theme / end-of-day / escalation stores, in one generic.
@MainActor
final class PersistedSettings<Value: Codable & Equatable>: ObservableObject {
    private let key: String

    @Published var value: Value {
        didSet { if value != oldValue { persist() } }
    }

    init(key: String, default defaultValue: Value) {
        self.key = key
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            value = decoded
        } else {
            value = defaultValue
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Snooze lengths

struct SnoozeSettings: Codable, Equatable {
    /// Lengths offered on the reminder, in minutes, shortest first. The first
    /// is what a plain Snooze (or the keyboard shortcut) uses.
    var presets: [Int] = [5, 10, 30]

    static let choices = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var defaultMinutes: Int { presets.sorted().first ?? 5 }

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m")
    }
}

// MARK: - Weekly summary

struct WeeklySummarySettings: Codable, Equatable {
    var isEnabled = true
    /// Calendar weekday, 1 = Sunday … 7 = Saturday. Defaults to the last day
    /// of the week in the Mac's calendar.
    var weekday: Int = {
        let first = Calendar.current.firstWeekday
        return first == 1 ? 7 : first - 1
    }()
    var hour = 19
    var minute = 0
    /// "yyyy-Www" of the week it was last shown, so it shows once per week.
    var lastShownWeekKey: String?
}

// MARK: - Goal check-in

/// Goals never fire on their own schedule; once a day, at this time, a popup
/// lists the ones still open.
struct GoalNudgeSettings: Codable, Equatable {
    var isEnabled = true
    var hour = 20
    var minute = 0
    /// Day it last showed, so it comes once a day.
    var lastShownDayKey: String?
}

// MARK: - Reminder popup

struct ReminderPopupSettings: Codable, Equatable {
    /// How long a reminder's popup stays, in seconds. 0 = until clicked.
    var seconds = 10
    /// How to send it off early.
    var dismiss = Dismiss.click

    enum Dismiss: String, Codable, CaseIterable {
        case click, doubleClick, hover

        var label: String {
            switch self {
            case .click: return "Click"
            case .doubleClick: return "Double-click"
            case .hover: return "Rest the pointer on it"
            }
        }
    }

    init(seconds: Int = 10, dismiss: Dismiss = .click) {
        self.seconds = seconds
        self.dismiss = dismiss
    }

    private enum CodingKeys: String, CodingKey { case seconds, dismiss }

    /// Settings saved before `dismiss` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 10
        dismiss = (try? c.decodeIfPresent(Dismiss.self, forKey: .dismiss)) ?? .click
    }

    static let choices = [5, 10, 20, 30, 60, 0]

    static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Until I click it"
        case 60: return "1 minute"
        default: return "\(seconds) seconds"
        }
    }
}

// MARK: - Menu bar face

struct FaceSettings: Codable, Equatable {
    /// The menu bar face wakes up when the pointer comes near and watches it.
    var followPointer = true
}

// MARK: - Break timer

/// A plain sRGB colour that can be saved.
struct RGBColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// Light enough that text on it should be dark.
    var isLight: Bool { 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 }

    static let black = RGBColor(r: 0, g: 0, b: 0)
    static let white = RGBColor(r: 1, g: 1, b: 1)
    static let ink = RGBColor(r: 0.06, g: 0.08, b: 0.13)
    /// The soft blue for breaks (#C5D2E5).
    static let breakBlue = RGBColor(r: 0.773, g: 0.824, b: 0.898)
    static let awayRed = RGBColor(r: 1.0, g: 0.27, b: 0.23)

    /// Quick picks in Settings.
    static let swatches: [RGBColor] = [
        .black,
        RGBColor(r: 0.17, g: 0.17, b: 0.19), // graphite
        .breakBlue,
        RGBColor(r: 0.72, g: 0.89, b: 0.80), // mint
        RGBColor(r: 0.98, g: 0.81, b: 0.69), // peach
        RGBColor(r: 0.83, g: 0.78, b: 0.96), // lavender
        RGBColor(r: 0.11, g: 0.19, b: 0.38), // navy
        .awayRed,
    ]
}

struct BreakTimerSettings: Codable, Equatable {
    /// The work countdown stays at the notch the whole time, counting, and
    /// never hides (on, the default), or only shows at the start, with 10
    /// minutes left and for the last 10 seconds (off). Breaks always show.
    var workCountdownStays = true
    /// "Working" / "Break" stay next to the face the whole time (on, the
    /// default); off: just the face and the time between moments.
    var wordsStay = true
    /// The notch's colour while working.
    var workColor = RGBColor.black
    /// The notch's colour on a break.
    var breakColor = RGBColor.breakBlue
    /// The colour of the time-away count after a break.
    var awayColor = RGBColor.awayRed
    /// Where the face, z's, word and time sit, and how big the notch is.
    var layout = IslandLayout()

    /// The older name, still used by the list's pin and the right-click menu.
    var keepWorkCountdown: Bool {
        get { workCountdownStays }
        set { workCountdownStays = newValue }
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case workCountdownStays, wordsStay, workColor, breakColor, awayColor, layout
    }

    /// Settings saved before colours or the layout existed still load (and
    /// keep their choices). The old "keepWorkCountdown" is ignored on
    /// purpose: a click at the notch used to turn it off by accident, and
    /// the countdown staying is the default now.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workCountdownStays = try c.decodeIfPresent(Bool.self, forKey: .workCountdownStays) ?? true
        wordsStay = try c.decodeIfPresent(Bool.self, forKey: .wordsStay) ?? true
        workColor = try c.decodeIfPresent(RGBColor.self, forKey: .workColor) ?? .black
        breakColor = try c.decodeIfPresent(RGBColor.self, forKey: .breakColor) ?? .breakBlue
        awayColor = try c.decodeIfPresent(RGBColor.self, forKey: .awayColor) ?? .awayRed
        layout = (try? c.decodeIfPresent(IslandLayout.self, forKey: .layout)) ?? IslandLayout()
    }
}

/// Where things sit on the notch, set in Settings → Smart by dragging them.
/// Offsets are points from their usual spot (x to the right, y down); sizes
/// are multiples of the usual size. The sides grow by themselves when
/// something is moved outward, so nothing gets cut off.
struct IslandLayout: Codable, Equatable {
    enum Part: String, CaseIterable, Codable {
        case face, zees, words, time

        var label: String {
            switch self {
            case .face: return "Face"
            case .zees: return "Zzz"
            case .words: return "Word"
            case .time: return "Time"
            }
        }
    }

    struct Spot: Codable, Equatable {
        var x: Double = 0
        var y: Double = 0
        var size: Double = 1

        init(x: Double = 0, y: Double = 0, size: Double = 1) {
            self.x = x
            self.y = y
            self.size = size
        }

        private enum CodingKeys: String, CodingKey { case x, y, size }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
            y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
            size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 1
        }
    }

    var face = Spot()
    /// Relative to the face (they float up from it).
    var zees = Spot()
    var words = Spot()
    var time = Spot()
    /// Extra width on each side, in points.
    var leftExtra: Double = 0
    var rightExtra: Double = 0
    /// How far it reaches down below the notch, in points.
    var drop: Double = 0

    static let sizes: ClosedRange<Double> = 0.6...2.4
    static let reach: ClosedRange<Double> = -160...160
    static let maxExtra: Double = 160
    static let maxDrop: Double = 48

    init() {}

    subscript(part: Part) -> Spot {
        get {
            switch part {
            case .face: return face
            case .zees: return zees
            case .words: return words
            case .time: return time
            }
        }
        set {
            var spot = newValue
            spot.x = min(Self.reach.upperBound, max(Self.reach.lowerBound, spot.x))
            // Up to the top edge, down to the bottom of whatever it reaches.
            spot.y = min(30 + drop, max(-30, spot.y))
            spot.size = min(Self.sizes.upperBound, max(Self.sizes.lowerBound, spot.size))
            switch part {
            case .face: face = spot
            case .zees: zees = spot
            case .words: words = spot
            case .time: time = spot
            }
        }
    }

    mutating func nudge(_ part: Part, dx: Double = 0, dy: Double = 0) {
        var spot = self[part]
        spot.x += dx
        spot.y += dy
        self[part] = spot
    }

    mutating func resize(_ part: Part, by step: Double) {
        var spot = self[part]
        spot.size = ((spot.size + step) * 10).rounded() / 10
        self[part] = spot
    }

    static func clampExtra(_ value: Double) -> Double { min(maxExtra, max(0, value)) }
    static func clampDrop(_ value: Double) -> Double { min(maxDrop, max(0, value)) }

    private enum CodingKeys: String, CodingKey { case face, zees, words, time, leftExtra, rightExtra, drop }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        face = try c.decodeIfPresent(Spot.self, forKey: .face) ?? Spot()
        zees = try c.decodeIfPresent(Spot.self, forKey: .zees) ?? Spot()
        words = try c.decodeIfPresent(Spot.self, forKey: .words) ?? Spot()
        time = try c.decodeIfPresent(Spot.self, forKey: .time) ?? Spot()
        leftExtra = try c.decodeIfPresent(Double.self, forKey: .leftExtra) ?? 0
        rightExtra = try c.decodeIfPresent(Double.self, forKey: .rightExtra) ?? 0
        drop = try c.decodeIfPresent(Double.self, forKey: .drop) ?? 0
    }
}

// MARK: - Smart features

struct SmartSettings: Codable, Equatable {
    /// Hold reminders while nobody's at the Mac, show them on return.
    var holdWhileAway = true
    /// Minutes without keyboard / mouse input that count as away.
    var awayMinutes = 3
    /// Suggestions like "You usually do this at 4:35 — move it?".
    var suggestionsEnabled = true
    /// Suggestions the user dismissed, so they don't come back.
    var dismissedSuggestions: [String] = []
    /// ⌥D / ⌥S / ⌥K answer the reminder on screen from any app (keys set in KeyBindings).
    var globalShortcuts = true
}

// MARK: - Categories

struct CategorySettings: Codable, Equatable {
    var names: [String] = ["Health", "Work", "Home", "Study", "Personal"]
}

enum CategoryStyle {
    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.70, blue: 0.45), // green
        Color(red: 0.25, green: 0.52, blue: 0.96), // blue
        Color(red: 0.96, green: 0.58, blue: 0.20), // orange
        Color(red: 0.62, green: 0.40, blue: 0.92), // purple
        Color(red: 0.93, green: 0.36, blue: 0.56), // pink
        Color(red: 0.90, green: 0.75, blue: 0.15), // yellow
        Color(red: 0.20, green: 0.70, blue: 0.80), // teal
    ]
    private static let known = ["health": 0, "work": 1, "home": 2, "study": 3, "personal": 4]

    /// A stable colour per category name.
    static func color(for name: String) -> Color {
        let key = name.lowercased()
        if let index = known[key] { return palette[index] }
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}

// MARK: - Shared instances

@MainActor
enum AppSettings {
    static let snooze = PersistedSettings(key: "snoozeSettings.v1", default: SnoozeSettings())
    static let weekly = PersistedSettings(key: "weeklySummarySettings.v1", default: WeeklySummarySettings())
    static let goalNudge = PersistedSettings(key: "goalNudge.v1", default: GoalNudgeSettings())
    static let breakTimer = PersistedSettings(key: "breakTimer.v1", default: BreakTimerSettings())
    static let reminderPopup = PersistedSettings(key: "reminderPopup.v1", default: ReminderPopupSettings())
    static let face = PersistedSettings(key: "faceSettings.v1", default: FaceSettings())
    static let smart = PersistedSettings(key: "smartSettings.v1", default: SmartSettings())
    static let categories = PersistedSettings(key: "categorySettings.v1", default: CategorySettings())
    static let missed = PersistedSettings(key: "missed.v1", default: MissedList())
    static let ignored = PersistedSettings(key: "ignoredCounts.v1", default: IgnoreCounts())
    static let login = PersistedSettings(key: "loginItem.v1", default: LoginSettings())
    static let renderWatch = PersistedSettings(key: "renderWatch.v1", default: RenderWatchSettings())
}

// MARK: - Missed while away

/// Reminders that came due while the Mac was asleep or off, or while you
/// were away: shown together when you're back ("You missed: Msg wife, 6 PM").
struct MissedList: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var title: String
        /// When it was first due.
        var dueAt: Date
        /// How many times it came due meanwhile (an every-40-minutes one).
        var count = 1
        /// A line under it: "Due in 3 days", a render's file name.
        var detail: String? = nil
    }

    var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Adds one; the same title again just counts up (and keeps the first time).
    mutating func add(title: String, dueAt: Date, count: Int = 1, detail: String? = nil) {
        if let index = entries.firstIndex(where: { $0.title == title && $0.detail == detail }) {
            entries[index].count += max(count, 1)
            entries[index].dueAt = min(entries[index].dueAt, dueAt)
        } else {
            entries.append(Entry(title: title, dueAt: dueAt, count: max(count, 1), detail: detail))
        }
        entries.sort { $0.dueAt < $1.dueAt }
        if entries.count > 50 { entries.removeFirst(entries.count - 50) }
    }
}

// MARK: - Ignored reminders

/// How many times in a row each reminder was ignored (its popup timed out
/// while you were busy at the Mac; a habit left unfinished). From
/// `loudAfter` on it comes back louder: angry, buzzing, and it stays until
/// clicked. Answering it resets the count.
struct IgnoreCounts: Codable, Equatable {
    var counts: [String: Int] = [:]

    static let loudAfter = 3

    func count(for id: UUID) -> Int { counts[id.uuidString] ?? 0 }
    func isLoud(_ id: UUID) -> Bool { count(for: id) >= Self.loudAfter }

    mutating func ignored(_ id: UUID) { counts[id.uuidString, default: 0] += 1 }
    mutating func answered(_ id: UUID) { counts[id.uuidString] = nil }
}

// MARK: - Open at login

struct LoginSettings: Codable, Equatable {
    /// Open Remind Me when the Mac starts, so reminders fire after a restart.
    var openAtLogin = true
    /// Turned on once already (so turning it off in System Settings sticks).
    var registeredOnce = false
}

// MARK: - Render done ping

/// Watches the folders you render into; when a new video file there stops
/// growing while DaVinci Resolve is open, it says "Render done".
struct RenderWatchSettings: Codable, Equatable {
    var isEnabled = false
    /// Folders to watch (and everything inside them).
    var folders: [String] = []
}

