import SwiftUI

/// The last seven days at a glance: how much got done, the best streak, what
/// got snoozed most, and each routine's tally. Pops up once a week (day and
/// time in Settings → Smart), and opens any time from the panel's chart
/// button or the menu bar icon's right-click menu.
struct WeeklySummaryView: View {
    let items: [Item]
    let occurrences: [Occurrence]
    let theme: PanelTheme
    let onClose: () -> Void
    var closeIcon = "xmark.circle.fill"

    var body: some View {
        let summary = Insights.weeklySummary(items: items, occurrences: occurrences, now: .now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your week")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.text)
                    Text(Self.range(summary))
                        .font(.system(size: theme.fontSize - 2))
                        .foregroundStyle(theme.text.opacity(0.5))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: closeIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.opacity(0.5))
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                WeeklySummaryContent(summary: summary, theme: theme)
            }
            .scrollIndicators(.never)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    static func range(_ summary: Insights.WeeklySummary) -> String {
        "\(dayFormatter.string(from: summary.start)) – \(dayFormatter.string(from: summary.end))"
    }
}

/// The summary's body, separate so previews can draw it without a scroll view.
struct WeeklySummaryContent: View {
    let summary: Insights.WeeklySummary
    let theme: PanelTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            if let best = summary.bestStreak {
                highlight(icon: "flame.fill", tint: .orange,
                          title: "Best streak", detail: "\(best.title) — \(best.streak) day\(best.streak == 1 ? "" : "s")")
            }
            if let snoozed = summary.mostSnoozed {
                highlight(icon: "moon.zzz.fill", tint: theme.text.opacity(0.7),
                          title: "Snoozed most", detail: "\(snoozed.title) — \(snoozed.snoozed) time\(snoozed.snoozed == 1 ? "" : "s")")
            }
            if summary.openGoals > 0 {
                highlight(icon: "flag.fill", tint: theme.accent,
                          title: "Goals in progress", detail: "\(summary.openGoals) open")
            }
            if !summary.routines.isEmpty {
                Text("Routines")
                    .font(.system(size: theme.fontSize - 1, weight: .semibold))
                    .foregroundStyle(theme.text.opacity(0.7))
                    .padding(.top, 2)
                VStack(spacing: 8) {
                    ForEach(summary.routines) { routine in
                        routineRow(routine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.done)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                Text("of \(summary.total) done")
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                if let rate = summary.rate {
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text.opacity(0.8))
                }
            }
            if summary.total > 0 {
                ProgressBar(fraction: Double(summary.done) / Double(summary.total), tint: theme.accent, track: theme.text.opacity(0.1))
                    .frame(height: 6)
                HStack(spacing: 12) {
                    stat("Skipped", summary.skipped)
                    stat("Missed", summary.unfinished)
                    let waiting = summary.total - summary.done - summary.skipped - summary.unfinished
                    if waiting > 0 { stat("Waiting", waiting) }
                }
            } else {
                Text("No reminders this week yet.")
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(0.6))
            }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        Text("\(label) \(value)")
            .font(.system(size: theme.fontSize - 2))
            .foregroundStyle(theme.text.opacity(0.55))
    }

    private func highlight(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: theme.fontSize - 3))
                    .foregroundStyle(theme.text.opacity(0.5))
                Text(detail)
                    .font(theme.font)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
        }
    }

    private func routineRow(_ routine: Insights.RoutineWeek) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(routine.title)
                    .font(theme.font)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let category = routine.category {
                    CategoryTag(name: category, theme: theme)
                }
                Spacer()
                if routine.streak >= 2 {
                    Label("\(routine.streak)", systemImage: "flame.fill")
                        .font(.system(size: theme.fontSize - 3, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("\(routine.done)/\(routine.total)")
                    .font(.system(size: theme.fontSize - 2).monospacedDigit())
                    .foregroundStyle(theme.text.opacity(0.6))
            }
            ProgressBar(fraction: routine.total > 0 ? Double(routine.done) / Double(routine.total) : 0,
                        tint: theme.accent.opacity(0.8), track: theme.text.opacity(0.08))
                .frame(height: 4)
        }
    }
}

/// A plain rounded progress bar.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
    }
}
