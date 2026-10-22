import SwiftUI

/// Task timers in the list: counting down, asking "done?" at zero, or counting
/// on in red when nobody answered.
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

    var body: some View {
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
                Button("Done") { TaskTimers.markDone(entry.id); ReminderScheduler.shared.timersChanged() }
                Button("Not yet") { TaskTimers.notYet(entry.id) }
            case .overdue:
                Text("+" + TaskTimers.clock(now.timeIntervalSince(entry.endsAt)))
                    .monospacedDigit()
                    .foregroundStyle(.red)
                Button("Done") { TaskTimers.markDone(entry.id); ReminderScheduler.shared.timersChanged() }
            case .queued:
                Text("Next up").foregroundStyle(theme.text.opacity(0.5))
            case .done:
                EmptyView()
            }
        }
        .controlSize(.small)
    }
}
