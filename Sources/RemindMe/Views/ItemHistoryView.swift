import SwiftUI

/// A routine's track record: its streak, how often it gets done, the last two
/// weeks day by day, and the latest reminders. Opens from a tap on the
/// routine in the panel; Edit / Pause / Delete are right here too.
struct ItemHistoryView: View {
    let item: Item
    let occurrences: [Occurrence]
    let theme: PanelTheme
    let onBack: () -> Void
    let onEdit: () -> Void
    let onPause: (ItemActions.PauseLength) -> Void
    let onResume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: item.title, theme: theme, onBack: onBack) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.plain)
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }

            ScrollView {
                ItemHistoryContent(item: item, occurrences: occurrences, theme: theme, now: .now)
            }
            .scrollIndicators(.never)

            HStack(spacing: 8) {
                if item.kind != .goal {
                    if item.isActive {
                        Menu {
                            ForEach(ItemActions.PauseLength.allCases) { length in
                                Button(length.label) { onPause(length) }
                            }
                        } label: {
                            Label("Pause", systemImage: "pause.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    } else {
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .font(.system(size: theme.fontSize - 1, weight: .medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The figures and the day grid, separate so previews can draw them.
struct ItemHistoryContent: View {
    let item: Item
    let occurrences: [Occurrence]
    let theme: PanelTheme
    let now: Date

    private var mine: [Occurrence] { Insights.occurrences(of: item, in: occurrences) }

    private static let dayLetter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    private static let entryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let mine = self.mine
        let fortnight = Insights.dailyRecords(mine, days: 14, now: now)
        let month = Insights.dailyRecords(mine, days: 30, now: now)
        let streak = Insights.streak(Insights.dailyRecords(mine, days: 120, now: now))
        let rate = Insights.completionRate(month)
        let snoozes = mine.filter { ($0.snoozedMinutes ?? 0) > 0 && $0.scheduledFireDate > now.addingTimeInterval(-7 * 86400) }.count

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let category = item.category { CategoryTag(name: category, theme: theme) }
                Text(item.scheduleSummary)
                    .font(.system(size: theme.fontSize - 2))
                    .foregroundStyle(theme.text.opacity(0.55))
            }

            HStack(spacing: 10) {
                figure(value: "\(streak)", label: "day streak", icon: "flame.fill", tint: .orange)
                figure(value: rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", label: "done, 30 days",
                       icon: "checkmark.circle.fill", tint: theme.accent)
                figure(value: "\(snoozes)", label: "snoozes, 7 days", icon: "moon.zzz.fill", tint: theme.text.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Last 14 days")
                    .font(.system(size: theme.fontSize - 2, weight: .semibold))
                    .foregroundStyle(theme.text.opacity(0.6))
                HStack(spacing: 4) {
                    ForEach(Array(fortnight.enumerated()), id: \.offset) { _, record in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(for: record))
                                .frame(height: 18)
                                .help(help(for: record))
                            Text(Self.dayLetter.string(from: record.day))
                                .font(.system(size: 8))
                                .foregroundStyle(theme.text.opacity(0.35))
                        }
                    }
                }
                HStack(spacing: 10) {
                    legend(theme.accent, "kept")
                    legend(theme.accent.opacity(0.35), "some")
                    legend(Color.orange.opacity(0.55), "missed")
                    legend(theme.text.opacity(0.08), "none")
                }
            }

            let recent = mine.sorted { $0.scheduledFireDate > $1.scheduledFireDate }.prefix(8)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent")
                        .font(.system(size: theme.fontSize - 2, weight: .semibold))
                        .foregroundStyle(theme.text.opacity(0.6))
                    ForEach(Array(recent), id: \.id) { occurrence in
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon(occurrence.status))
                                .foregroundStyle(statusColor(occurrence.status))
                                .frame(width: 14)
                            Text(Self.entryFormatter.string(from: occurrence.scheduledFireDate))
                                .foregroundStyle(theme.text.opacity(0.8))
                            Spacer()
                            if let minutes = occurrence.snoozedMinutes, minutes > 0 {
                                Text("snoozed \(SnoozeSettings.label(minutes))")
                                    .foregroundStyle(theme.text.opacity(0.45))
                            }
                        }
                        .font(.system(size: theme.fontSize - 2))
                    }
                }
            } else {
                Text("No reminders yet — they'll show up here.")
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.text)
            }
            Text(label)
                .font(.system(size: theme.fontSize - 4))
                .foregroundStyle(theme.text.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(theme.text.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 9)).foregroundStyle(theme.text.opacity(0.45))
        }
    }

    private func color(for record: Insights.DayRecord) -> Color {
        if record.isEmpty { return theme.text.opacity(0.08) }
        if record.isKept { return theme.accent }
        if record.done > 0 { return theme.accent.opacity(0.35) }
        if record.pending == record.total { return theme.text.opacity(0.18) }
        return Color.orange.opacity(0.55)
    }

    private func help(for record: Insights.DayRecord) -> String {
        record.isEmpty ? "Nothing scheduled" : "\(record.done) of \(record.total) done"
    }

    private func statusIcon(_ status: OccurrenceStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .unfinished: return "flag.fill"
        }
    }

    private func statusColor(_ status: OccurrenceStatus) -> Color {
        switch status {
        case .pending, .skipped: return theme.text.opacity(0.4)
        case .done: return theme.accent
        case .unfinished: return .orange
        }
    }
}

/// Back button, title and an optional trailing control, for the panel's
/// inner pages.
struct PageHeader<Trailing: View>: View {
    let title: String
    let theme: PanelTheme
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text.opacity(0.7))
            .keyboardShortcut(.cancelAction)
            .help("Back")

            Text(title)
                .font(theme.titleFont)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 4)
            trailing()
        }
    }
}
