import SwiftUI

/// A routine or goal in the panel's list. The round button on the left pauses
/// a routine (for an hour, until tomorrow, a week, or until resumed) or
/// resumes it, and ticks a goal off. Swipe left for Edit / Delete; right-click
/// for everything else.
struct ReminderRowView: View {
    let item: Item
    let theme: PanelTheme
    /// Kept days in a row; shown from 2 up ("3 days in a row").
    var streak: Int = 0
    /// Times done, all time ("5 total").
    var total: Int = 0
    /// Goals: answered Done today (the circle is ticked until tomorrow).
    var doneToday = false
    /// Goal: achieved on/off. Paused routine: resume.
    let onToggle: () -> Void
    /// Kept for callers; pausing for a set time is in the right-click menu.
    var onPause: (ItemActions.PauseLength) -> Void = { _ in }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            toggleControl

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(theme.font)
                        .foregroundStyle(dimmed ? theme.text.opacity(0.4) : theme.text)
                        .strikethrough(item.kind == .goal && item.isAchieved)
                        .lineLimit(1)
                    if let category = item.category {
                        CategoryTag(name: category, theme: theme)
                    }
                }

                HStack(spacing: 4) {
                    if let paused = pausedLine {
                        // Paused: say until when, instead of the schedule.
                        Image(systemName: "pause.fill")
                        Text(paused)
                    } else if !subtitle.isEmpty {
                        Image(systemName: kindIcon)
                        Text(subtitle)
                    }
                }
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.5))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if total > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(total) total")
                        .font(.system(size: theme.fontSize - 2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.text.opacity(0.75))
                    if streak >= 2 {
                        Label("\(streak) days in a row", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: theme.fontSize - 3, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .help(streak >= 2 ? "Done \(total) times · \(streak) days in a row" : "Done \(total) times")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// One click turns it off (grey) or back on (blue). Longer pauses are
    /// in the right-click menu.
    private var toggleControl: some View {
        Button(action: onToggle) {
            Image(systemName: toggleIcon)
                .font(.system(size: theme.fontSize + 3))
                .foregroundStyle(toggleOn ? ReminderRowView.onColor : theme.text.opacity(0.3))
        }
        .buttonStyle(.plain)
        .help(toggleHelp)
    }

    /// The "on" colour for every toggle in the list.
    static let onColor = Color(red: 0.25, green: 0.56, blue: 1.0)

    private var pausedLine: String? {
        guard item.kind != .goal, !item.isActive else { return nil }
        guard let until = item.pausedUntil else { return "Off · \(item.scheduleSummary)" }
        let calendar = Calendar.current
        let time = Self.timeFormatter.string(from: until)
        if calendar.isDateInToday(until) { return "Paused until \(time)" }
        if calendar.isDateInTomorrow(until) { return "Paused until tomorrow, \(time)" }
        return "Paused until \(Self.dayFormatter.string(from: until))"
    }

    private var dimmed: Bool {
        item.kind == .goal ? item.isAchieved : !item.isActive
    }

    private var toggleOn: Bool {
        item.kind == .goal ? (item.isAchieved || doneToday) : item.isActive
    }

    /// Schedule line; goals say when they're asked about, or that today's done.
    private var subtitle: String {
        guard item.kind == .goal else { return item.scheduleSummary }
        if item.isAchieved { return "Finished" }
        if doneToday { return "Done today" }
        if !item.scheduleSummary.isEmpty { return item.scheduleSummary }
        let nudge = AppSettings.goalNudge.value
        return nudge.isEnabled ? "Check-in at \(Item.clockTimeString(hour: nudge.hour, minute: nudge.minute))" : ""
    }

    private var toggleIcon: String {
        switch item.kind {
        case .goal:
            if item.isAchieved { return "checkmark.seal.fill" }
            return doneToday ? "checkmark.circle.fill" : "circle"
        case .repeatingRoutine, .scheduledRoutine:
            return "bolt.circle.fill"
        }
    }

    private var toggleHelp: String {
        switch item.kind {
        case .goal:
            if item.isAchieved { return "Not finished after all" }
            return doneToday ? "Undo today" : "Done today"
        case .repeatingRoutine, .scheduledRoutine: return item.isActive ? "Turn off" : "Turn on"
        }
    }

    private var kindIcon: String {
        switch item.kind {
        case .repeatingRoutine: return "repeat"
        case .scheduledRoutine: return "clock"
        case .goal: return "flag"
        }
    }
}

/// A small coloured label for a category.
struct CategoryTag: View {
    let name: String
    let theme: PanelTheme

    var body: some View {
        Text(name)
            .font(.system(size: max(theme.fontSize - 4, 9), weight: .semibold))
            .foregroundStyle(CategoryStyle.color(for: name))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(CategoryStyle.color(for: name).opacity(0.16))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}
