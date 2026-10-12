import SwiftUI

/// The small floating pill: current time, and a countdown to whatever's
/// next. `TimelineView(.periodic(... by: 60))` redraws about once a minute —
/// no custom Timer, no battery cost beyond what SwiftUI already schedules.
///
/// Dragging works anywhere on it because nothing here is a `Button` — a
/// `Button` would swallow the mouse-down before AppKit's
/// `isMovableByWindowBackground` ever sees it. A plain `onTapGesture` lets
/// the click pass through to the window for a drag, while still firing on a
/// clean click-and-release.
struct CollapsedPillView: View {
    let activeItems: [Item]
    let theme: PanelTheme
    let onTap: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            row(now: context.date)
        }
    }

    private func row(now: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activeItems.isEmpty ? "bell" : "bell.badge.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.timeFormatter.string(from: now))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Text(nextLine(now: now))
                    .font(theme.font.weight(.regular))
                    .foregroundStyle(theme.text.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func nextLine(now: Date) -> String {
        let upcoming = activeItems
            .compactMap { item -> (title: String, date: Date)? in
                item.nextFireDate.map { (item.title, $0) }
            }
            .filter { $0.date > now }
            .min { $0.date < $1.date }

        guard let upcoming else { return "Nothing scheduled" }

        let minutes = max(0, Int(upcoming.date.timeIntervalSince(now) / 60))
        let countdown: String
        if minutes < 1 { countdown = "due now" }
        else if minutes < 60 { countdown = "in \(minutes)m" }
        else { countdown = "in \(minutes / 60)h \(minutes % 60)m" }
        return "\(upcoming.title) \(countdown)"
    }
}
