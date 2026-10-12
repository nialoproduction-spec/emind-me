import SwiftUI

struct ReminderRowView: View {
    let item: Item
    let theme: PanelTheme
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: toggleIcon)
                    .foregroundStyle(toggleOn ? theme.accent : theme.text.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(toggleHelp)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(theme.font)
                    .foregroundStyle(dimmed ? theme.text.opacity(0.4) : theme.text)
                    .strikethrough(dimmed)
                    .lineLimit(1)

                if !item.scheduleSummary.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: kindIcon)
                        Text(item.scheduleSummary)
                    }
                    .font(.system(size: theme.fontSize - 2))
                    .foregroundStyle(theme.text.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
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
            return item.isActive ? "bolt.circle.fill" : "bolt.circle"
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
