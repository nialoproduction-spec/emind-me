import SwiftUI

/// One row in today's checklist — a read-only record of a single firing.
/// Resolved through the live reminder (Done/Snooze/Skip), not from here.
struct ChecklistRowView: View {
    let occurrence: Occurrence
    let theme: PanelTheme

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)

            Text(occurrence.item?.title ?? "Reminder")
                .font(theme.font)
                .foregroundStyle(occurrence.status == .done ? theme.text.opacity(0.5) : theme.text)
                .strikethrough(occurrence.status == .done)
                .lineLimit(1)

            Spacer()

            Text(Self.timeFormatter.string(from: occurrence.scheduledFireDate))
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.4))
        }
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
