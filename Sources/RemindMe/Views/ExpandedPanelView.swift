import SwiftUI
import SwiftData

/// What's been typed in the panel but not saved yet. Lives outside the view
/// so it survives the panel fading away and coming back: a half-typed
/// reminder is still there next time.
@MainActor
final class PanelDraft: ObservableObject {
    static let shared = PanelDraft()
    @Published var text = "" {
        didSet { if text.trimmingCharacters(in: .whitespaces).isEmpty { chosen = nil } }
    }
    /// Reminder / Habit / Goal picked in the preview; nil = the default.
    @Published var chosen: ItemType?
    private init() {}

    /// What Enter would save, shown live above the field while typing.
    var preview: ParsedItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var parsed = ItemParser.parse(trimmed)
        parsed.chosen = chosen
        return parsed
    }
}

/// The open panel: goals at the top, reminders (routines) in the middle,
/// today's checklist at the bottom, and the add field. Every row is live —
/// tap to open or tick off, swipe left for Edit / Delete, swipe right for a
/// quick Done / Pause, right-click for the rest.
struct ExpandedPanelView: View {
    let items: [Item]
    let occurrences: [Occurrence]
    let todayOccurrences: [Occurrence]
    let theme: PanelTheme
    let onCollapse: () -> Void
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var draft = PanelDraft.shared
    @ObservedObject private var voice = VoiceInput.shared
    @ObservedObject private var smart = AppSettings.smart
    @ObservedObject private var undo = UndoCenter.shared
    @FocusState private var fieldFocused: Bool

    /// Inner pages, shown in place of the list.
    @State private var editing: Item?
    @State private var historyOf: Item?
    @State private var showingWeekly = false
    @State private var categoryFilter: String?
    @State private var pendingDeletion: Deletion?

    private enum Deletion: Identifiable {
        case item(Item)
        case entry(Occurrence)

        var id: String {
            switch self {
            case .item(let item): return "item-\(item.id)"
            case .entry(let occurrence): return "entry-\(occurrence.id)"
            }
        }
    }

    // MARK: - Lists

    private func matchesFilter(_ item: Item?) -> Bool {
        guard let categoryFilter else { return true }
        return item?.category?.caseInsensitiveCompare(categoryFilter) == .orderedSame
    }

    private var goals: [Item] {
        items.filter { $0.kind == .goal && matchesFilter($0) }
            .sorted { $0.isAchieved != $1.isAchieved ? !$0.isAchieved : $0.createdAt > $1.createdAt }
    }

    /// Over (a one-time reminder that has fired, a delivered or past
    /// deadline): gone from the list.
    private func routines(styled style: ReminderStyle) -> [Item] {
        items.filter { $0.kind != .goal && $0.style == style && !$0.isOver && $0.dueDate == nil && matchesFilter($0) }
            .sorted { $0.isActive != $1.isActive ? $0.isActive : $0.createdAt > $1.createdAt }
    }

    /// Deadlines still ahead, soonest first.
    private var deadlines: [Item] {
        items.filter { $0.kind != .goal && $0.dueDate != nil && !$0.isOver && matchesFilter($0) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var habits: [Item] { routines(styled: .habit) }
    private var reminders: [Item] { routines(styled: .justRemind) }

    /// Today's entries for habits only: a plain reminder has nothing to
    /// tick off, so it never shows up here (even an old entry from before it
    /// was switched to a reminder).
    private var sortedToday: [Occurrence] {
        todayOccurrences
            .filter { ($0.item?.style ?? .habit) == .habit && $0.item?.kind != .goal && matchesFilter($0.item) }
            .sorted { $0.scheduledFireDate < $1.scheduledFireDate }
    }

    /// The same habit coming due again and again today is one row with a
    /// count, not a wall of identical lines. Newest group first.
    struct TodayGroup: Identifiable {
        let id: String
        let item: Item?
        let occurrences: [Occurrence]
        var doneCount: Int { occurrences.filter { $0.status == .done }.count }
        var latest: Date { occurrences.map(\.scheduledFireDate).max() ?? .distantPast }
    }

    private var todayGroups: [TodayGroup] {
        var order: [String] = []
        var buckets: [String: [Occurrence]] = [:]
        var owners: [String: Item?] = [:]
        for occurrence in sortedToday {
            let key = occurrence.item.map { "item-\($0.id)" } ?? "entry-\(occurrence.id)"
            if buckets[key] == nil { order.append(key); owners[key] = .some(occurrence.item) }
            buckets[key, default: []].append(occurrence)
        }
        return order.map { key in
            TodayGroup(id: key, item: owners[key] ?? nil, occurrences: buckets[key] ?? [])
        }
        .sorted { $0.latest > $1.latest }
    }

    private var categoriesInUse: [String] {
        var seen: [String] = []
        for name in items.compactMap(\.category)
        where !seen.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            seen.append(name)
        }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var suggestion: Insights.Suggestion? {
        guard smart.value.suggestionsEnabled else { return nil }
        let dismissed = Set(smart.value.dismissedSuggestions)
        return Insights.suggestions(items: items, occurrences: occurrences)
            .first { !dismissed.contains($0.id) }
    }

    private func streak(for item: Item) -> Int {
        Insights.streak(Insights.dailyRecords(Insights.occurrences(of: item, in: occurrences), days: 60, now: .now))
    }

    /// Times done, all time. Plain reminders have nothing to count.
    private func total(for item: Item) -> Int {
        guard item.style == .habit || item.kind == .goal else { return 0 }
        return Insights.occurrences(of: item, in: occurrences).filter { $0.status == .done }.count
    }

    private func doneToday(_ item: Item) -> Bool {
        GoalCheckIn.todaysAnswer(for: item, in: occurrences, now: .now)?.status == .done
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let item = editing {
                EditItemView(item: item, theme: theme) { editing = nil }
            } else if let item = historyOf {
                ItemHistoryView(
                    item: item,
                    occurrences: occurrences,
                    theme: theme,
                    onBack: { historyOf = nil },
                    onEdit: { editing = item },
                    onPause: { pause(item, for: $0) },
                    onResume: { ItemActions.resume(item) },
                    onDelete: { pendingDeletion = .item(item) }
                )
            } else if showingWeekly {
                WeeklySummaryView(items: items, occurrences: occurrences, theme: theme,
                                  onClose: { showingWeekly = false }, closeIcon: "chevron.backward.circle.fill")
            } else {
                mainPage
            }
        }
        // Typing counts as using the panel, even with the pointer elsewhere,
        // so it never fades out mid-sentence.
        .onChange(of: draft.text) { ReminderPanelController.shared.noteActivity() }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { target in
            Button("Delete", role: .destructive) { performDeletion(target) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { target in
            switch target {
            case .item(let item):
                Text(item.kind == .goal
                     ? "This goal will be removed."
                     : "This reminder and its history will be removed. ⌘Z brings it back.")
            case .entry:
                Text("Removes this entry from today's list. The reminder itself stays.")
            }
        }
    }

    private var deletionTitle: String {
        switch pendingDeletion {
        case .item(let item): return "Delete “\(item.title)”?"
        case .entry(let occurrence): return "Remove “\(occurrence.item?.title ?? "this entry")” from today?"
        case nil: return "Delete?"
        }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)

            if !categoriesInUse.isEmpty {
                categoryBar
                Divider().opacity(0.1)
            }

            if items.isEmpty && BreakCycleManager.shared.config == nil {
                emptyState
            } else {
                list
            }

            if let suggestion {
                Divider().opacity(0.15)
                suggestionBar(suggestion)
            }

            if let action = undo.available {
                Divider().opacity(0.15)
                undoBar(action)
            }

            Divider().opacity(0.15)
            inputRow
        }
        // ⌘Z: take back the last delete, Done or Skip.
        .background(
            Button("Undo") { undo.undoLast() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private func undoBar(_ action: UndoCenter.Action) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(theme.text.opacity(0.6))
            Text(action.label)
                .font(.system(size: theme.fontSize - 1))
                .foregroundStyle(theme.text.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { undo.undoLast() } label: {
                Text("Undo ⌘Z")
                    .font(.system(size: theme.fontSize - 2, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(ReminderRowView.onColor.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReminderRowView.onColor)
            Button { undo.clear() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.4))
            .help("Keep it")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var list: some View {
        List {
            if categoryFilter == nil {
                BreakTimerSection(theme: theme)
            }
            TaskTimersSection(theme: theme)
            if !deadlines.isEmpty {
                Section("Deadlines") {
                    ForEach(deadlines) { item in itemRow(item) }
                }
            }
            if !goals.isEmpty {
                Section("Goals") {
                    ForEach(goals) { item in itemRow(item) }
                }
            }
            if !habits.isEmpty {
                Section("Habits") {
                    ForEach(habits) { item in itemRow(item) }
                }
            }
            if !reminders.isEmpty {
                Section("Reminders") {
                    ForEach(reminders) { item in itemRow(item) }
                }
            }
            if !sortedToday.isEmpty {
                let done = sortedToday.filter { $0.status == .done }.count
                Section("Today — \(done) of \(sortedToday.count) done") {
                    ForEach(todayGroups) { group in
                        if group.occurrences.count == 1, let occurrence = group.occurrences.first {
                            checklistRow(occurrence)
                        } else {
                            groupRow(group)
                        }
                    }
                }
            }
            if goals.isEmpty && habits.isEmpty && reminders.isEmpty && deadlines.isEmpty && sortedToday.isEmpty
                && (categoryFilter != nil || BreakCycleManager.shared.config == nil) {
                Text("Nothing in this category yet.")
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(0.5))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Rows

    private func itemRow(_ item: Item) -> some View {
        ReminderRowView(
            item: item,
            theme: theme,
            streak: item.style == .justRemind && item.kind != .goal ? 0 : streak(for: item),
            total: total(for: item),
            doneToday: item.kind == .goal && doneToday(item),
            onToggle: { toggle(item) },
            onPause: { pause(item, for: $0) }
        )
        .onTapGesture { open(item) }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.08))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { pendingDeletion = .item(item) } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            Button { editing = item } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.kind == .goal {
                Button { toggle(item) } label: {
                    Label(doneToday(item) ? "Undo" : "Done today", systemImage: "checkmark")
                }
                .tint(theme.accent)
            } else if item.isActive {
                Button { pause(item, for: .oneHour) } label: {
                    Label("Pause 1h", systemImage: "pause")
                }
                .tint(.orange)
            } else {
                Button { ItemActions.resume(item) } label: {
                    Label("Resume", systemImage: "play")
                }
                .tint(theme.accent)
            }
        }
        .contextMenu { itemMenu(item) }
    }

    @ViewBuilder
    private func itemMenu(_ item: Item) -> some View {
        Button("Edit…") { editing = item }
        if item.kind == .goal {
            if !item.isAchieved {
                Button("Done today") { GoalCheckIn.answer(item, done: true, now: .now, in: modelContext) }
                Button("Not today") { GoalCheckIn.answer(item, done: false, now: .now, in: modelContext) }
            }
            Button(item.isAchieved ? "Not finished after all" : "Finished for good (stop asking)") { item.isAchieved.toggle() }
            Button("History & streak") { historyOf = item }
        } else if item.dueDate != nil {
            Button("Delivered") { ItemActions.finish(item) }
            if item.isActive {
                Button("Stop the nudges") { pause(item, for: .indefinitely) }
            } else {
                Button("Nudge me again") { ItemActions.resume(item) }
            }
        } else {
            if item.onceAt != nil {
                Button("Done with it") { ItemActions.finish(item) }
            }
            Button(item.style == .habit ? "Make it a Reminder (no buttons)" : "Make it a Habit (tap Done)") {
                item.style = item.style == .habit ? .justRemind : .habit
                NotificationService.shared.schedule(for: item)
            }
            Button("History & streak") { historyOf = item }
            if item.isActive {
                Menu("Pause") {
                    ForEach(ItemActions.PauseLength.allCases) { length in
                        Button(length.label) { pause(item, for: length) }
                    }
                }
            } else {
                Button("Resume") { ItemActions.resume(item) }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = .item(item) }
    }

    /// One habit that came due several times today: a single row with the
    /// count ("×5" when all are done, "3/5" otherwise). Tap for its history.
    private func groupRow(_ group: TodayGroup) -> some View {
        let total = group.occurrences.count
        let allDone = group.doneCount == total
        return HStack(spacing: 10) {
            Image(systemName: allDone ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                .foregroundStyle(allDone ? theme.accent : theme.text.opacity(0.5))
                .frame(width: 16)
            Text(group.item?.title ?? "Reminder")
                .font(theme.font)
                .foregroundStyle(allDone ? theme.text.opacity(0.5) : theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(allDone ? "×\(total)" : "\(group.doneCount)/\(total)")
                .font(.system(size: theme.fontSize - 1, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(allDone ? theme.accent : theme.text.opacity(0.7))
                .background((allDone ? theme.accent : theme.text).opacity(0.14))
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture { if let item = group.item { historyOf = item } }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.08))
        .contextMenu {
            Button("Mark all done") {
                for occurrence in group.occurrences where occurrence.status != .done {
                    OccurrenceActions.set(occurrence, to: .done)
                }
            }
            .disabled(group.doneCount == total)
            if let item = group.item {
                Divider()
                Button("Edit reminder…") { editing = item }
                Button("History & streak") { historyOf = item }
            }
        }
    }

    private func checklistRow(_ occurrence: Occurrence) -> some View {
        ChecklistRowView(occurrence: occurrence, theme: theme) {
            OccurrenceActions.toggle(occurrence)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.08))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { pendingDeletion = .entry(occurrence) } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            if let item = occurrence.item {
                Button { editing = item } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { OccurrenceActions.toggle(occurrence) } label: {
                Label(occurrence.status == .done ? "Undo" : "Done",
                      systemImage: occurrence.status == .done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(theme.accent)
        }
        .contextMenu {
            Button("Done") { OccurrenceActions.set(occurrence, to: .done) }
                .disabled(occurrence.status == .done)
            Button("Skipped") { OccurrenceActions.set(occurrence, to: .skipped) }
                .disabled(occurrence.status == .skipped)
            Button("Not done") { OccurrenceActions.set(occurrence, to: .unfinished) }
                .disabled(occurrence.status == .unfinished)
            if let item = occurrence.item {
                Divider()
                Button("Edit reminder…") { editing = item }
                Button("History & streak") { historyOf = item }
            }
            Divider()
            Button("Remove from today…", role: .destructive) { pendingDeletion = .entry(occurrence) }
        }
    }

    // MARK: - Header, filter, suggestion

    private var header: some View {
        HStack(spacing: 12) {
            Text("Remind Me")
                .font(theme.titleFont)
                .foregroundStyle(theme.text)
            Spacer()
            Button { showingWeekly = true } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.7))
            .help("Weekly summary")

            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.7))
            .help("Settings")

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

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                filterChip("All", selected: categoryFilter == nil, color: theme.accent) { categoryFilter = nil }
                ForEach(categoriesInUse, id: \.self) { name in
                    filterChip(name, selected: categoryFilter == name, color: CategoryStyle.color(for: name)) {
                        categoryFilter = categoryFilter == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
    }

    private func filterChip(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.fontSize - 2, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? color : theme.text.opacity(0.65))
                .background(selected ? color.opacity(0.2) : theme.text.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func suggestionBar(_ suggestion: Insights.Suggestion) -> some View {
        SuggestionBar(
            suggestion: suggestion,
            theme: theme,
            onApply: { apply(suggestion) },
            onDismiss: { dismiss(suggestion) }
        )
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
            Text("Add #work or #health to tag it")
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            if voice.isListening {
                // Red while Command is held; released to stop.
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .help("Listening. Let go of Command to stop.")
            }
            TextField(voice.isListening ? "Listening…" : "Drink water every 40 min", text: $draft.text)
                .textFieldStyle(.plain)
                .font(theme.font)
                .foregroundStyle(theme.text)
                .focused($fieldFocused)
                .onSubmit(handleSubmit)

            TypePicker(preview: draft.preview, theme: theme) { draft.chosen = $0 }

            Button(action: handleSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(draft.preview == nil ? theme.text.opacity(0.25) : ReminderRowView.onColor)
            }
            .buttonStyle(.plain)
            .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Save (Enter)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func open(_ item: Item) {
        if item.kind == .goal {
            editing = item
        } else {
            historyOf = item
        }
    }

    /// Enter saves straight away; the preview above the field already showed
    /// what it will be (and the Reminder / Habit / Goal pick).
    private func handleSubmit() {
        saveConfirmed()
    }

    private func saveConfirmed() {
        guard let pending = draft.preview else { return }
        if let timer = pending.timer {
            // "choosing music within 30 min": counts down in the Timers section.
            TaskTimers.start(timer, category: pending.category)
        } else if let cycle = pending.breakCycle {
            // A break timer isn't a routine: it starts the menu bar countdown
            // and shows in the list's "Break timer" section.
            BreakCycleManager.shared.startCycle(cycle)
        } else {
            let item = Item(from: pending)
            if let category = pending.category { rememberCategory(category) }
            modelContext.insert(item)
            NotificationService.shared.schedule(for: item)
        }
        draft.text = ""
        draft.chosen = nil
        fieldFocused = true
        // Added: the panel stays up until the next click elsewhere.
        ReminderPanelController.shared.keepOpenUntilClickAway()
    }

    /// A new #tag joins the category list, so it can be picked when editing.
    private func rememberCategory(_ name: String) {
        let store = AppSettings.categories
        guard !store.value.names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        store.value.names.append(name)
    }

    private func toggle(_ item: Item) {
        if item.kind == .goal {
            if item.isAchieved {
                item.isAchieved = false
            } else if let answer = GoalCheckIn.todaysAnswer(for: item, in: occurrences, now: .now), answer.status == .done {
                OccurrenceActions.delete(answer, in: modelContext)
            } else {
                GoalCheckIn.answer(item, done: true, now: .now, in: modelContext)
            }
        } else if item.isActive {
            pause(item, for: .indefinitely)
        } else {
            ItemActions.resume(item)
        }
    }

    private func pause(_ item: Item, for length: ItemActions.PauseLength) {
        ItemActions.pause(item, until: length.endDate(from: .now), in: modelContext)
    }

    private func performDeletion(_ target: Deletion) {
        pendingDeletion = nil
        switch target {
        case .item(let item):
            if editing?.persistentModelID == item.persistentModelID { editing = nil }
            if historyOf?.persistentModelID == item.persistentModelID { historyOf = nil }
            // Removes the item's occurrences too (see ItemDeletion).
            ItemDeletion.delete(item, in: modelContext)
        case .entry(let occurrence):
            OccurrenceActions.delete(occurrence, in: modelContext)
        }
    }

    private func apply(_ suggestion: Insights.Suggestion) {
        guard let item = items.first(where: { $0.persistentModelID == suggestion.itemID }) else { return }
        ItemActions.apply(suggestion, to: item)
        dismiss(suggestion)
    }

    private func dismiss(_ suggestion: Insights.Suggestion) {
        guard !smart.value.dismissedSuggestions.contains(suggestion.id) else { return }
        smart.value.dismissedSuggestions.append(suggestion.id)
    }
}

/// A smart suggestion above the add field: "You usually do this at 4:35 —
/// move it there?" with Apply and ✕.
struct SuggestionBar: View {
    let suggestion: Insights.Suggestion
    let theme: PanelTheme
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color.yellow.opacity(0.9))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.message)
                    .font(.system(size: theme.fontSize - 1))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onApply) {
                    Text(suggestion.actionLabel)
                        .font(.system(size: theme.fontSize - 2, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.4))
            .help("Don't suggest this")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.06))
    }
}

/// The break timer as a list row, like any routine: blue bolt while it runs,
/// grey when off (click to switch), a live "Working · 32:10 left" line, and
/// right-click / swipe to delete. Its own view so the per-second countdown
/// only redraws this row, not the whole list.
struct BreakTimerSection: View {
    let theme: PanelTheme
    @ObservedObject private var breaks = BreakCycleManager.shared
    @ObservedObject private var settings = AppSettings.breakTimer

    var body: some View {
        if let config = breaks.config {
            Section("Break timer") {
                row(config, running: breaks.state)
            }
        }
    }

    private func row(_ config: BreakCycleConfig, running: BreakCycleState?) -> some View {
        HStack(spacing: 10) {
            Button { toggle() } label: {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: theme.fontSize + 3))
                    .foregroundStyle(running != nil ? ReminderRowView.onColor : theme.text.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help(running != nil ? "Turn off" : "Turn on")

            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(theme.font)
                    .foregroundStyle(running != nil ? theme.text : theme.text.opacity(0.4))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let running, running.phase == .waiting {
                        Image(systemName: "moon.zzz.fill")
                        Text("Break's over · starts when you're back")
                    } else if let running {
                        Image(systemName: running.phase == .onBreak ? "cup.and.saucer.fill" : "repeat")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = BreakCycleState.clockString(running.remaining(at: context.date))
                            Text(running.phase == .onBreak ? "On break · \(left) left" : "Working · \(left) to break")
                                .monospacedDigit()
                        }
                    } else {
                        Image(systemName: "pause.fill")
                        Text("Off")
                    }
                }
                .font(.system(size: theme.fontSize - 2))
                .foregroundStyle(theme.text.opacity(0.5))
                .lineLimit(1)
            }
            Spacer(minLength: 4)

            // Pin = the work countdown stays at the notch; unpinned it hides
            // while you work and only peeks at the key moments.
            Button { settings.value.keepWorkCountdown.toggle() } label: {
                Image(systemName: settings.value.keepWorkCountdown ? "pin.fill" : "pin.slash")
                    .font(.system(size: theme.fontSize - 1))
                    .foregroundStyle(settings.value.keepWorkCountdown ? ReminderRowView.onColor : theme.text.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(settings.value.keepWorkCountdown
                  ? "Work countdown stays at the notch. Click to hide it while working."
                  : "Work countdown hidden while working. Click to keep it at the notch.")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.08))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { breaks.remove() } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
        }
        .contextMenu {
            if running != nil {
                Button("Turn off") { breaks.stop() }
                Button("Start over") { breaks.resume() }
            } else {
                Button("Turn on") { breaks.resume() }
            }
            Button(settings.value.keepWorkCountdown ? "Hide work countdown" : "Keep work countdown at the notch") {
                settings.value.keepWorkCountdown.toggle()
            }
            Divider()
            Button("Delete", role: .destructive) { breaks.remove() }
        }
    }

    private func toggle() {
        if breaks.isRunning { breaks.stop() } else { breaks.resume() }
    }
}

/// Reminder · Habit · Goal as three small icons beside the send arrow. As
/// you type, the one your text points to lights up blue (a time → Reminder,
/// no time → Goal); click another to switch, and the rest go grey. Reminder
/// and Habit need a time in the text. A break timer shows a cup instead.
struct TypePicker: View {
    let preview: ParsedItem?
    let theme: PanelTheme
    var onPick: (ItemType) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 1) {
            if let preview, preview.breakCycle != nil {
                chip(icon: "cup.and.saucer.fill", lit: true, enabled: true, help: "Break timer") {}
            } else {
                ForEach(ItemType.allCases, id: \.self) { type in
                    let enabled = preview.map { type == .goal || $0.hasSchedule } ?? false
                    let lit = preview?.type == type
                    chip(icon: lit ? Self.filledIcon(type) : type.icon, lit: lit, enabled: enabled,
                         help: Self.help(type, enabled: enabled)) { onPick(type) }
                        .keyboardShortcut(type == .habit ? KeyboardShortcut(.return, modifiers: .command) : nil)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.text.opacity(0.07)))
        .animation(.snappy(duration: 0.18), value: preview?.type)
    }

    private func chip(icon: String, lit: Bool, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .foregroundStyle(lit ? ReminderRowView.onColor : theme.text.opacity(enabled ? 0.45 : 0.18))
                .background(Capsule().fill(lit ? ReminderRowView.onColor.opacity(0.2) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    static func filledIcon(_ type: ItemType) -> String {
        switch type {
        case .reminder: return "bell.fill"
        case .habit: return "checkmark.circle.fill"
        case .goal: return "flag.fill"
        }
    }

    static func help(_ type: ItemType, enabled: Bool) -> String {
        if !enabled { return "\(type.label): add a time first, like “every 2 hours”" }
        switch type {
        case .reminder: return "Reminder: just reminds you"
        case .habit: return "Habit: you tap Done each time (⌘↩)"
        case .goal: return "Goal: asked about at the evening check-in"
        }
    }
}
