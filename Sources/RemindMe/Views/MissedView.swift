import SwiftUI

/// What came due while you were away, or while the Mac was asleep or off:
/// "You missed: Msg wife, 6:00 PM". Shown once when you're back; Got it
/// clears the list.
struct MissedView: View {
    let entries: [MissedList.Entry]
    let theme: PanelTheme
    var now: Date = .now
    var onDone: () -> Void = {}

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// "6:00 PM" today, "Yesterday, 6:00 PM" otherwise.
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? clockFormatter.string(from: date) : timeFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarFace.faceImage(.owo, span: MenuBarFace.span(of: [.owo]), offset: .zero))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 14)
                    .foregroundStyle(theme.text.opacity(0.85))
                Text("You missed")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Spacer()
            }
            Text("While you were away:")
                .font(theme.font)
                .foregroundStyle(theme.text.opacity(0.6))

            VStack(spacing: 6) {
                ForEach(entries.prefix(8)) { entry in row(entry) }
                if entries.count > 8 {
                    Text("and \(entries.count - 8) more")
                        .font(.system(size: theme.fontSize - 2))
                        .foregroundStyle(theme.text.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
            Button(action: onDone) {
                Label("Got it", systemImage: "checkmark.circle.fill")
                    .font(.system(size: theme.fontSize - 1, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(ReminderRowView.onColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReminderRowView.onColor)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ entry: MissedList.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(Color.orange.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: theme.fontSize - 2))
                        .foregroundStyle(theme.text.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(entry.count > 1 ? "×\(entry.count) since \(Self.when(entry.dueAt, now: now))"
                                 : Self.when(entry.dueAt, now: now))
                .font(.system(size: theme.fontSize - 2).monospacedDigit())
                .foregroundStyle(theme.text.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.text.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
