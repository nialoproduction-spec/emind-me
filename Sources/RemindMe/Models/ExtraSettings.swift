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

// MARK: - Break timer

struct BreakTimerSettings: Codable, Equatable {
    /// Keep the work countdown at the notch the whole time (on), or only
    /// show it at the start, with 10 minutes left and for the last 10
    /// seconds (off). Breaks always show.
    var keepWorkCountdown = true
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
    static let smart = PersistedSettings(key: "smartSettings.v1", default: SmartSettings())
    static let categories = PersistedSettings(key: "categorySettings.v1", default: CategorySettings())
}
