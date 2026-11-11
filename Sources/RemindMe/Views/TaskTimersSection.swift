import SwiftUI

/// Task timers in the list: counting down, asking "done?" at zero, or counting
/// on in red when nobody answered. Right-click or swipe: Edit, Delete.
struct TaskTimersSection: View {
    let theme: PanelTheme
    @ObservedObject private var store = TaskTimers.store

    var body: some View {
        let open = store.value.open
        if !open.isEmpty {
            Section("Timers") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ForEach(open) { entry in
                        TaskTimerRow(entry: entry, now: context.date, theme: theme)
                    }
                }
            }
        }
    }
}

private struct TaskTimerRow: View {
    let entry: TaskTimers.Entry
    let now: Date
    let theme: PanelTheme

    @State private var editing = false
    @State private var title = ""
    @State private var minutes = 20

    var body: some View {
        Group {
            if editing { editor } else { display }
        }
        .controlSize(.small)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { delete() } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
            Button { startEditing() } label: { Label("Edit", systemImage: "pencil") }
                .tint(.gray)
        }
        .contextMenu {
            Button("Edit…") { startEditing() }
            if entry.state != .queued {
                Button("Done") { done() }
            }
            Divider()
            Button("Delete", role: .destructive) { delete() }
        }
    }

    private var display: some View {
        HStack(spacing: 8) {
            Text(entry.title)
                .font(theme.font)
                .foregroundStyle(entry.state == .overdue ? Color.red : theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            switch entry.state {
            case .running:
                Text(TaskTimers.clock(entry.endsAt.timeIntervalSince(now)))
                    .monospacedDigit()
                    .foregroundStyle(theme.text.opacity(0.6))
            case .asking:
                Text("Time's up").foregroundStyle(.red)
                Button("Done") { done() }
                Button("Not yet") { TaskTimers.notYet(entry.id) }
            case .overdue:
                Text("+" + TaskTimers.clock(now.timeIntervalSince(entry.overdueAt ?? entry.endsAt)))
                    .monospacedDigit()
                    .foregroundStyle(.red)
                Button("Done") { done() }
            case .queued:
                Text("Next up · \(Int((entry.seconds / 60).rounded())) min").foregroundStyle(theme.text.opacity(0.5))
            case .done:
                EmptyView()
            }
        }
    }

    private var editor: some View {
        HStack(spacing: 6) {
            TextField("Task", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Stepper("\(minutes) min", value: $minutes, in: 1...600)
                .fixedSize()
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
            Button("Cancel") { editing = false }
        }
    }

    private func startEditing() {
        title = entry.title
        minutes = max(1, Int((entry.seconds / 60).rounded()))
        editing = true
    }

    private func save() {
        TaskTimers.update(entry.id, title: title, seconds: Double(minutes) * 60)
        editing = false
        ReminderScheduler.shared.timersChanged()
    }

    private func done() {
        TaskTimers.markDone(entry.id)
        ReminderScheduler.shared.timersChanged()
    }

    private func delete() {
        TaskTimers.remove(entry.id)
        ReminderScheduler.shared.timersChanged()
    }
}
