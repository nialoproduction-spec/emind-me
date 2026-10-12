import SwiftUI
import SwiftData

/// What's been typed in the panel but not saved yet. Lives outside the view
/// so it survives the panel fading away and coming back: a half-typed
/// reminder or a confirmation waiting for Save is still there next time.
@MainActor
final class PanelDraft: ObservableObject {
    static let shared = PanelDraft()
    @Published var text = ""
    @Published var pending: ParsedItem?
    private init() {}
}

struct ExpandedPanelView: View {
    let items: [Item]
    let todayOccurrences: [Occurrence]
    let theme: PanelTheme
    let onCollapse: () -> Void
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var draft = PanelDraft.shared
    @FocusState private var fieldFocused: Bool

    private var routines: [Item] {
        items.filter { $0.kind != .goal }
            .sorted { $0.isActive != $1.isActive ? $0.isActive : $0.createdAt > $1.createdAt }
    }

    private var goals: [Item] {
        items.filter { $0.kind == .goal }
            .sorted { $0.isAchieved != $1.isAchieved ? !$0.isAchieved : $0.createdAt > $1.createdAt }
    }

    private var sortedToday: [Occurrence] {
        todayOccurrences.sorted { $0.scheduledFireDate < $1.scheduledFireDate }
    }

    private var todayDoneCount: Int { todayOccurrences.filter { $0.status == .done }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)

            if items.isEmpty {
                emptyState
            } else {
                List {
                    if !todayOccurrences.isEmpty {
                        Section("Today — \(todayDoneCount) of \(todayOccurrences.count) done") {
                            ForEach(sortedToday) { occurrence in
                                ChecklistRowView(occurrence: occurrence, theme: theme)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                        }
                    }
                    if !routines.isEmpty {
                        Section("Routines") {
                            ForEach(routines) { item in
                                ReminderRowView(item: item, theme: theme, onToggle: { toggle(item) })
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                            .onDelete { delete(routines, at: $0) }
                        }
                    }
                    if !goals.isEmpty {
                        Section("Goals") {
                            ForEach(goals) { item in
                                ReminderRowView(item: item, theme: theme, onToggle: { toggle(item) })
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                            .onDelete { delete(goals, at: $0) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider().opacity(0.15)
            if let pending = draft.pending {
                confirmationBar(pending)
                Divider().opacity(0.15)
            }
            inputRow
        }
        // Typing counts as using the panel, even with the pointer elsewhere,
        // so it never fades out mid-sentence.
        .onChange(of: draft.text) { ReminderPanelController.shared.noteActivity() }
    }

    private var header: some View {
        HStack {
            Text("Remind Me")
                .font(theme.titleFont)
                .foregroundStyle(theme.text)
            Spacer()
            Button(action: onShowSettings) {
                Image(systemName: "paintbrush")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.7))

            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(theme.text.opacity(0.3))
            Text("Type a routine or a goal below")
                .font(theme.font)
                .foregroundStyle(theme.text.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confirmation

    private func confirmationBar(_ parsed: ParsedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: confirmationIcon(for: parsed))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(parsed.kindLabel) · \(parsed.title)")
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if !parsed.detailLine.isEmpty {
                    Text(parsed.detailLine)
                        .font(.system(size: theme.fontSize - 2))
                        .foregroundStyle(theme.text.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: cancelConfirmation) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.5))
            .help("Discard")

            Button(action: editConfirmation) {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.5))
            .help("Edit the text and re-check")

            Button(action: saveConfirmed) {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .help("Save")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.accent.opacity(0.08))
    }

    private func confirmationIcon(for parsed: ParsedItem) -> String {
        switch parsed.kind {
        case .repeatingRoutine: return "repeat"
        case .scheduledRoutine: return "clock"
        case .goal: return "flag"
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Drink water every 40 minutes…", text: $draft.text)
                .textFieldStyle(.plain)
                .font(theme.font)
                .foregroundStyle(theme.text)
                .focused($fieldFocused)
                .onSubmit(handleSubmit)

            Button(action: handleSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func handleSubmit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.pending = ItemParser.parse(trimmed)
    }

    private func saveConfirmed() {
        guard let pending = draft.pending else { return }
        let item = Item(from: pending)
        modelContext.insert(item)
        NotificationService.shared.schedule(for: item)
        draft.text = ""
        draft.pending = nil
        // Added: the panel tucks itself away (after a beat, so the save registers).
        ReminderPanelController.shared.closeAfterAdding()
    }

    private func cancelConfirmation() {
        draft.text = ""
        draft.pending = nil
        fieldFocused = true
    }

    /// Dismisses the confirmation but keeps the typed text, so the person
    /// can tweak it and submit again rather than retyping from scratch.
    private func editConfirmation() {
        draft.pending = nil
        fieldFocused = true
    }

    private func toggle(_ item: Item) {
        if item.kind == .goal {
            item.isAchieved.toggle()
        } else {
            item.isActive.toggle()
            if item.isActive {
                // Stale from before the pause — recompute from now rather
                // than resuming against a timestamp that may be in the past.
                item.nextFireDate = item.computeNextFireDate()
                NotificationService.shared.schedule(for: item)
            } else {
                item.nextFireDate = nil
                NotificationService.shared.cancel(for: item)
            }
        }
    }

    private func delete(_ list: [Item], at offsets: IndexSet) {
        for index in offsets {
            // Removes the item's occurrences too (see ItemDeletion).
            ItemDeletion.delete(list[index], in: modelContext)
        }
    }
}
