import SwiftUI
import SwiftData

/// Shown once, at whatever time the user picked in Settings, if enabled.
struct EndOfDaySummaryView: View {
    let occurrencesToday: [Occurrence]
    let theme: PanelTheme
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    private var doneCount: Int { occurrencesToday.filter { $0.status == .done }.count }
    private var totalCount: Int { occurrencesToday.count }
    private var unfinished: [Occurrence] { occurrencesToday.filter { $0.status == .unfinished } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("End of Day")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.opacity(0.5))
            }

            Text("\(doneCount) of \(totalCount) done today")
                .font(theme.font.weight(.semibold))
                .foregroundStyle(theme.accent)

            if unfinished.isEmpty {
                Text(totalCount == 0 ? "Nothing was scheduled today." : "Nothing left unfinished.")
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(0.6))
                Spacer()
            } else {
                Text("Unfinished — reschedule for today?")
                    .font(.system(size: theme.fontSize - 1, weight: .semibold))
                    .foregroundStyle(theme.text.opacity(0.7))

                List {
                    ForEach(unfinished) { occurrence in
                        HStack {
                            Text(occurrence.item?.title ?? "Reminder")
                                .font(theme.font)
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            Spacer()
                            Button("Reschedule") { reschedule(occurrence) }
                                .buttonStyle(.plain)
                                .font(.system(size: theme.fontSize - 2, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(14)
    }

    /// Fires this item again right away (next scheduler tick picks it up)
    /// rather than waiting for its next natural occurrence.
    private func reschedule(_ occurrence: Occurrence) {
        guard let item = occurrence.item else { return }
        item.isActive = true
        let fresh = Occurrence(item: item, scheduledFireDate: .now)
        fresh.nextEscalationAt = .now
        modelContext.insert(fresh)
        occurrence.status = .skipped
    }
}
