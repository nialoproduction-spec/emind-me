import SwiftUI

/// The card that asks when a timer is up: Done, Not yet (keeps counting, red)
/// or Skip (drops it). Buttons match the reminder card's.
struct TimerAskView: View {
    let entry: TaskTimers.Entry
    let theme: PanelTheme

    var body: some View {
        VStack(spacing: 14) {
            Text("\(entry.title): time's up")
                .font(.system(size: theme.fontSize + 2, weight: .semibold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            Text("Done with it?")
                .font(theme.font)
                .foregroundStyle(theme.text.opacity(0.6))
            HStack(spacing: 8) {
                choice("Done", icon: "checkmark.circle.fill", tint: theme.accent) {
                    TaskTimers.markDone(entry.id)
                }
                choice("Not yet", icon: "clock", tint: theme.text.opacity(0.85)) {
                    TaskTimers.notYet(entry.id)
                }
                choice("Skip", icon: "arrow.uturn.forward.circle", tint: theme.text.opacity(0.6)) {
                    TaskTimers.skip(entry.id)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func choice(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            ReminderScheduler.shared.timersChanged()
        } label: {
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
    }
}
