import SwiftUI

/// Force-shown when a routine's time arrives: an animated face, the title,
/// and three buttons. It stays until one of them is tapped; while it waits,
/// `ReminderScheduler` nags in place (count and gap set in Settings).
///
/// The face's mood rises with each nag — cute on the first, pouty in the
/// middle, angry on the last — and each button gets a short reaction (happy
/// hop / dozing off / crying) before the panel closes.
///
/// Snooze opens a row of lengths (set in Settings → Smart). Keyboard: ⌃⌥D /
/// ⌃⌥S / ⌃⌥K from any app, or Return / S / K while the card has focus.
struct LiveReminderView: View {
    let occurrence: Occurrence
    let theme: PanelTheme

    @ObservedObject private var scheduler = ReminderScheduler.shared
    @ObservedObject private var escalationStore = EscalationSettingsStore.shared
    @ObservedObject private var snoozeSettings = AppSettings.snooze
    @ObservedObject private var smart = AppSettings.smart
    @State private var reaction: FaceMood?
    @State private var choosingSnooze: Bool

    /// How long the reaction plays before the button's action actually runs.
    nonisolated static let reactionDuration: Duration = .milliseconds(900)

    init(occurrence: Occurrence, theme: PanelTheme, initialReaction: FaceMood? = nil,
         choosingSnooze: Bool = false) {
        self.occurrence = occurrence
        self.theme = theme
        _reaction = State(initialValue: initialReaction)
        _choosingSnooze = State(initialValue: choosingSnooze)
    }

    private var mood: FaceMood {
        reaction ?? FaceMood.forPop(
            count: occurrence.remindersSentCount,
            maxPops: escalationStore.settings.maxReminders
        )
    }

    private var presets: [Int] { snoozeSettings.value.presets.sorted() }

    var body: some View {
        VStack(spacing: 8) {
            AnimatedFaceView(mood: mood, color: theme.text, wakeToken: occurrence.remindersSentCount)

            Text(occurrence.item?.title ?? "Reminder")
                .font(theme.titleFont)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            Group {
                if choosingSnooze {
                    snoozeRow
                } else {
                    mainRow
                }
            }
            .disabled(reaction != nil)

            if smart.value.globalShortcuts {
                Text(shortcutHint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.text.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: scheduler.shortcutRequest) {
            guard let request = scheduler.shortcutRequest else { return }
            scheduler.consumeShortcut()
            switch request.action {
            case .done: done()
            case .snooze: snooze(minutes: nil)
            case .skip: skip()
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            actionButton("Done", icon: "checkmark.circle.fill", tint: theme.accent, action: done)
                .keyboardShortcut(.return, modifiers: [])
                .help("Done — \(GlobalHotkeys.label(for: .done))")
            actionButton("Snooze", icon: "moon.zzz.fill", tint: theme.text.opacity(0.85)) {
                if presets.count > 1 {
                    withAnimation(.easeOut(duration: 0.15)) { choosingSnooze = true }
                } else {
                    snooze(minutes: presets.first)
                }
            }
            .keyboardShortcut("s", modifiers: [])
            .help("Snooze — \(GlobalHotkeys.label(for: .snooze)) snoozes \(SnoozeSettings.label(snoozeSettings.value.defaultMinutes))")
            actionButton("Skip", icon: "arrow.uturn.forward.circle", tint: theme.text.opacity(0.6), action: skip)
                .keyboardShortcut("k", modifiers: [])
                .help("Skip — \(GlobalHotkeys.label(for: .skip))")
        }
    }

    private var snoozeRow: some View {
        HStack(spacing: 6) {
            ForEach(presets.prefix(4), id: \.self) { minutes in
                Button { snooze(minutes: minutes) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 13))
                        Text(SnoozeSettings.label(minutes)).font(.system(size: theme.fontSize - 2, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.text.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.opacity(0.85))
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { choosingSnooze = false }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26)
                    .padding(.vertical, 17)
                    .background(theme.text.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.6))
            .keyboardShortcut(.cancelAction)
            .help("Back")
        }
    }

    private var shortcutHint: String {
        "\(GlobalHotkeys.label(for: .done)) done · \(GlobalHotkeys.label(for: .snooze)) snooze · \(GlobalHotkeys.label(for: .skip)) skip"
    }

    // MARK: - Actions

    private func done() { respond(with: .done) { scheduler.markDone() } }
    private func skip() { respond(with: .skipped) { scheduler.skip() } }
    private func snooze(minutes: Int?) {
        respond(with: .snoozed) { scheduler.snooze(minutes: minutes) }
    }

    /// Plays the reaction face, then performs the action.
    private func respond(with reactionMood: FaceMood, then action: @escaping () -> Void) {
        guard reaction == nil else { return }
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
