import SwiftUI

/// One entry in today's checklist. Click it (or its circle) to tick it off,
/// click again to un-tick; right-click for Done / Skipped / Not done. If it's
/// the reminder on screen right now, ticking it answers that reminder too.
struct ChecklistRowView: View {
    let occurrence: Occurrence
    let theme: PanelTheme
    var onToggle: () -> Void = {}

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help(occurrence.status == .done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.item?.title ?? "Reminder")
                    .font(theme.font)
                    .foregroundStyle(occurrence.status == .done ? theme.text.opacity(0.5) : theme.text)
                    .strikethrough(occurrence.status == .done)
                    .lineLimit(1)
                if let note = statusNote {
                    Text(note)
                        .font(.system(size: theme.fontSize - 3))
                        .foregroundStyle(theme.text.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let category = occurrence.item?.category {
                CategoryTag(name: category, theme: theme)
            }

            Text(Self.timeFormatter.string(from: occurrence.scheduledFireDate))
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.4))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private var statusNote: String? {
        var parts: [String] = []
        switch occurrence.status {
        case .skipped: parts.append("skipped")
        case .unfinished: parts.append("missed")
        case .pending, .done: break
        }
        if let minutes = occurrence.snoozedMinutes, minutes > 0 {
            parts.append("snoozed \(SnoozeSettings.label(minutes))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var icon: String {
        switch occurrence.status {
        case .pending: return "circle"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .unfinished: return "flag.fill"
        }
    }

    private var color: Color {
        switch occurrence.status {
        case .pending: return theme.text.opacity(0.4)
        case .done: return theme.accent
        case .skipped: return theme.text.opacity(0.4)
        case .unfinished: return .orange
        }
    }
}
