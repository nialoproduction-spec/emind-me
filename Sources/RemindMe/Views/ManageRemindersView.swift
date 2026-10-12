import SwiftUI
import SwiftData

/// Settings → Your reminders: every routine and goal, each with a delete
/// button. Deleting always asks first, and removes the item's history from the
/// daily checklist along with it (`ItemDeletion`).
struct ManageRemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    @State private var pendingDeletion: Item?

    /// Active first (running routines, open goals), then paused / achieved.
    private var activeRoutines: [Item] { items.filter { $0.kind != .goal && $0.isActive } }
    private var openGoals: [Item] { items.filter { $0.kind == .goal && !$0.isAchieved } }
    private var inactive: [Item] {
        items.filter { $0.kind == .goal ? $0.isAchieved : !$0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text("No reminders yet. Add one from the panel by typing something like “drink water every 40 minutes”.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                group("Routines", activeRoutines, empty: "No active routines.")
                group("Goals", openGoals, empty: "No open goals.")
                if !inactive.isEmpty {
                    group("Paused & achieved", inactive, empty: "")
                }
            }
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                ItemDeletion.delete(item, in: modelContext)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { item in
            Text(item.kind == .goal
                 ? "This goal will be removed. This can't be undone."
                 : "This routine stops reminding you, and its history is removed from the daily checklist. This can't be undone.")
        }
    }

    private var dialogTitle: String {
        guard let item = pendingDeletion else { return "Delete?" }
        return "Delete “\(item.title)”?"
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [Item], empty: String) -> some View {
        Text(title)
            .font(.headline)
        if list.isEmpty {
            if !empty.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(list) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: item))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                Text(detail(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                pendingDeletion = item
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete “\(item.title)”")
            .accessibilityLabel("Delete \(item.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func icon(for item: Item) -> String {
        switch item.kind {
        case .repeatingRoutine: return "repeat"
        case .scheduledRoutine: return "clock"
        case .goal: return "flag"
        }
    }

    private func detail(for item: Item) -> String {
        let summary = item.scheduleSummary
        var status = ""
        if item.kind == .goal, item.isAchieved { status = "Achieved" }
        if item.kind != .goal, !item.isActive { status = "Paused" }
        switch (summary.isEmpty, status.isEmpty) {
        case (true, true): return item.kind == .goal ? "Goal" : "Routine"
        case (false, true): return summary
        case (true, false): return status
        case (false, false): return "\(summary) · \(status)"
        }
    }
}
