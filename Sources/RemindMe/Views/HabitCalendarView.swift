import SwiftUI

/// A month of a habit (or goal), one square per day: done, partly done,
/// missed, skipped, nothing due. Arrows step back through earlier months.
struct HabitCalendarView: View {
    let occurrences: [Occurrence]
    let theme: PanelTheme
    var now: Date = .now
    /// Months back from this one (0 = this month).
    @State private var monthsBack = 0

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private var month: Date {
        Calendar.current.date(byAdding: .month, value: -monthsBack, to: now) ?? now
    }

    private var weekdayLetters: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        let weeks = Insights.monthGrid(occurrences, month: month)
        let today = Calendar.current.startOfDay(for: now)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(Self.monthFormatter.string(from: month))
                    .font(.system(size: theme.fontSize - 2, weight: .semibold))
                    .foregroundStyle(theme.text.opacity(0.6))
                Spacer()
                arrow("chevron.backward", help: "Earlier month") { monthsBack += 1 }
                arrow("chevron.forward", help: "Later month") { monthsBack = max(0, monthsBack - 1) }
                    .opacity(monthsBack == 0 ? 0.3 : 1)
                    .disabled(monthsBack == 0)
            }
            HStack(spacing: 4) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.text.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, record in
                        cell(record, today: today)
                    }
                }
            }
            HStack(spacing: 10) {
                legend(theme.accent, "done")
                legend(theme.accent.opacity(0.35), "some")
                legend(Color.orange.opacity(0.6), "missed")
                legend(theme.text.opacity(0.2), "skipped")
            }
        }
    }

    @ViewBuilder
    private func cell(_ record: Insights.DayRecord?, today: Date) -> some View {
        if let record {
            let future = record.day > today
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(future ? Color.clear : color(for: record))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.text.opacity(record.day == today ? 0.7 : (future ? 0.1 : 0)), lineWidth: 1)
                )
                .overlay(
                    Text("\(Calendar.current.component(.day, from: record.day))")
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(record.isKept ? Color.white.opacity(0.9) : theme.text.opacity(future ? 0.25 : 0.5))
                )
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .help(help(for: record, future: future))
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 20)
        }
    }

    private func color(for record: Insights.DayRecord) -> Color {
        if record.isEmpty { return theme.text.opacity(0.06) }
        if record.isKept { return theme.accent }
        if record.done > 0 { return theme.accent.opacity(0.35) }
        if record.unfinished > 0 { return Color.orange.opacity(0.6) }
        if record.skipped > 0 { return theme.text.opacity(0.2) }
        return theme.text.opacity(0.12) // still waiting
    }

    private func help(for record: Insights.DayRecord, future: Bool) -> String {
        if future { return "Not yet" }
        if record.isEmpty { return "Nothing due" }
        return "\(record.done) of \(record.total) done"
    }

    private func arrow(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.text.opacity(0.6))
        .help(help)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 9)).foregroundStyle(theme.text.opacity(0.45))
        }
    }
}
