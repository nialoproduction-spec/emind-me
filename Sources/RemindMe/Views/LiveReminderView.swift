import SwiftUI

/// Force-shown when a routine's time arrives. Three buttons; if none are
/// tapped, `ReminderScheduler` keeps popping this back up every 15 minutes
/// (up to 3 times total) until one is.
struct LiveReminderView: View {
    let occurrence: Occurrence
    let theme: PanelTheme

    @ObservedObject private var scheduler = ReminderScheduler.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(theme.accent)
                Text(occurrence.item?.title ?? "Reminder")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Spacer()
            }

            HStack(spacing: 8) {
                actionButton("Done", icon: "checkmark.circle.fill", tint: theme.accent) {
                    scheduler.markDone()
                }
                actionButton("Snooze 5m", icon: "moon.zzz.fill", tint: theme.text.opacity(0.85)) {
                    scheduler.snooze()
                }
                actionButton("Skip", icon: "arrow.uturn.forward.circle", tint: theme.text.opacity(0.6)) {
                    scheduler.skip()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func actionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(.system(size: theme.fontSize - 2))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}
