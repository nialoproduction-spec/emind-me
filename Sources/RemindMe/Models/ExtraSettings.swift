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

    static let choices = [5, 10, 20, 30, 60, 0]

    static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Until I click it"
        case 60: return "1 minute"
        default: return "\(seconds) seconds"
        }
    }
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
    /// Keep the work countdown at the notch the whole time (on), or only
    /// show it at the start, with 10 minutes left and for the last 10
    /// seconds (off). Breaks always show.
    var keepWorkCountdown = true
    /// The notch's colour while working.
    var workColor = RGBColor.black
    /// The notch's colour on a break.
    var breakColor = RGBColor.breakBlue
    /// The colour of the time-away count after a break.
    var awayColor = RGBColor.awayRed

    init() {}

    private enum CodingKeys: String, CodingKey { case keepWorkCountdown, workColor, breakColor, awayColor }

    /// Settings saved before colours existed still load (and keep their choice).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepWorkCountdown = try c.decodeIfPresent(Bool.self, forKey: .keepWorkCountdown) ?? true
        workColor = try c.decodeIfPresent(RGBColor.self, forKey: .workColor) ?? .black
        breakColor = try c.decodeIfPresent(RGBColor.self, forKey: .breakColor) ?? .breakBlue
        awayColor = try c.decodeIfPresent(RGBColor.self, forKey: .awayColor) ?? .awayRed
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
    /// ⌃⌥D / ⌃⌥S / ⌃⌥K answer the reminder on screen from any app.
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
    static let smart = PersistedSettings(key: "smartSettings.v1", default: SmartSettings())
    static let categories = PersistedSettings(key: "categorySettings.v1", default: CategorySettings())
}
