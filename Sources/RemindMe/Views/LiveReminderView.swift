import SwiftUI

/// Force-shown when a routine's time arrives: an animated face, the title,
/// and three buttons. If none are tapped, `ReminderScheduler` keeps popping
/// this back up (count and gap set in Settings) until one is.
///
/// The face's mood rises with each unanswered pop — cute on the first,
/// pouty in the middle, angry on the last — and each button gets a short
/// reaction (happy hop / dozing off / crying) before the panel closes.
struct LiveReminderView: View {
    let occurrence: Occurrence
    let theme: PanelTheme

    @ObservedObject private var scheduler = ReminderScheduler.shared
    @ObservedObject private var escalationStore = EscalationSettingsStore.shared
    @State private var reaction: FaceMood?

    /// How long the reaction plays before the button's action actually runs.
    nonisolated static let reactionDuration: Duration = .milliseconds(900)

    init(occurrence: Occurrence, theme: PanelTheme, initialReaction: FaceMood? = nil) {
        self.occurrence = occurrence
        self.theme = theme
        _reaction = State(initialValue: initialReaction)
    }

    private var mood: FaceMood {
        reaction ?? FaceMood.forPop(
            count: occurrence.remindersSentCount,
            maxPops: escalationStore.settings.maxReminders
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            AnimatedFaceView(mood: mood, color: theme.text)
                .frame(width: 168, height: 87)

            Text(occurrence.item?.title ?? "Reminder")
                .font(theme.titleFont)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                actionButton("Done", icon: "checkmark.circle.fill", tint: theme.accent) {
                    respond(with: .done) { scheduler.markDone() }
                }
                actionButton("Snooze 5m", icon: "moon.zzz.fill", tint: theme.text.opacity(0.85)) {
                    respond(with: .snoozed) { scheduler.snooze() }
                }
                actionButton("Skip", icon: "arrow.uturn.forward.circle", tint: theme.text.opacity(0.6)) {
                    respond(with: .skipped) { scheduler.skip() }
                }
            }
            .disabled(reaction != nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Plays the reaction face, then performs the action. The panel's
    /// auto-collapse is paused first so it can't close mid-reaction and lose
    /// the tap.
    private func respond(with reactionMood: FaceMood, then action: @escaping () -> Void) {
        guard reaction == nil else { return }
        scheduler.holdForReaction()
        reaction = reactionMood
        Task { @MainActor in
            try? await Task.sleep(for: Self.reactionDuration)
            action()
        }
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
