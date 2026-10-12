import SwiftUI

/// A routine or goal in the panel's list. The round button on the left pauses
/// a routine (for an hour, until tomorrow, a week, or until resumed) or
/// resumes it, and ticks a goal off. Swipe left for Edit / Delete; right-click
/// for everything else.
struct ReminderRowView: View {
    let item: Item
    let theme: PanelTheme
    /// Kept days in a row (routines); shown from 2 up.
    var streak: Int = 0
    /// Goal: achieved on/off. Paused routine: resume.
    let onToggle: () -> Void
    /// Running routine: pause it for this long.
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
                    } else if !item.scheduleSummary.isEmpty {
                        Image(systemName: kindIcon)
                        Text(item.scheduleSummary)
                    }
                }
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.5))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.kind != .goal, streak >= 2 {
                Label("\(streak)", systemImage: "flame.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: theme.fontSize - 2, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .help("\(streak)-day streak")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var toggleControl: some View {
        if item.kind != .goal, item.isActive {
            Menu {
                Section("Pause") {
                    ForEach(ItemActions.PauseLength.allCases) { length in
                        Button(length.label) { onPause(length) }
                    }
                }
            } label: {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(theme.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pause…")
        } else {
            Button(action: onToggle) {
                Image(systemName: toggleIcon)
                    .foregroundStyle(toggleOn ? theme.accent : theme.text.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(toggleHelp)
        }
    }

    private var pausedLine: String? {
        guard item.kind != .goal, !item.isActive else { return nil }
        guard let until = item.pausedUntil else { return "Paused · \(item.scheduleSummary)" }
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
        item.kind == .goal ? item.isAchieved : item.isActive
    }

    private var toggleIcon: String {
        switch item.kind {
        case .goal:
            return item.isAchieved ? "checkmark.circle.fill" : "circle"
        case .repeatingRoutine, .scheduledRoutine:
            return item.isActive ? "bolt.circle.fill" : "pause.circle"
        }
    }

    private var toggleHelp: String {
        switch item.kind {
        case .goal: return item.isAchieved ? "Mark not done" : "Mark done"
        case .repeatingRoutine, .scheduledRoutine: return item.isActive ? "Pause" : "Resume"
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
