import SwiftUI
import SwiftData

/// The daily goal check-in (8 PM by default): each goal not answered yet
/// today, with Done and Not today. Honest either way, and both count toward
/// "how often do I actually hit this". Closes by itself once all are answered;
/// Later puts it away until tomorrow.
struct GoalCheckInView: View {
    let items: [Item]
    let occurrences: [Occurrence]
    let theme: PanelTheme

    @ObservedObject private var scheduler = ReminderScheduler.shared
    @State private var quote = ReminderQuotes.goal.randomElement() ?? ""

    private var waiting: [Item] {
        GoalCheckIn.unanswered(goals: items, occurrences: occurrences, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarFace.faceImage(.sheepish, span: MenuBarFace.span(of: [.sheepish]), offset: .zero))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 14)
                    .foregroundStyle(theme.text.opacity(0.85))
                Text("Goal check-in")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Later") { scheduler.dismissGoalCheckIn() }
                    .buttonStyle(.plain)
                    .font(.system(size: theme.fontSize - 1))
                    .foregroundStyle(theme.text.opacity(0.55))
                    .help("Ask again tomorrow")
            }

            Text("Did you do these today?")
                .font(theme.font)
                .foregroundStyle(theme.text.opacity(0.6))
            Text("“\(quote)”")
                .font(.system(size: max(theme.fontSize - 2, 10)).italic())
                .foregroundStyle(theme.text.opacity(0.45))

            if waiting.isEmpty {
                Spacer()
                Text("All answered.")
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(0.6))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(waiting) { goal in row(goal) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ goal: Item) -> some View {
        let mine = Insights.occurrences(of: goal, in: occurrences)
        let total = mine.filter { $0.status == .done }.count
        let streak = Insights.streak(Insights.dailyRecords(mine, days: 60, now: .now))
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(goal.title)
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                if let category = goal.category {
                    CategoryTag(name: category, theme: theme)
                }
                Spacer(minLength: 0)
            }
            if total > 0 {
                HStack(spacing: 8) {
                    Text("\(total) total")
                    if streak >= 2 {
                        Label("\(streak) days in a row", systemImage: "flame.fill")
                            .foregroundStyle(Color.orange)
                    }
                }
                .font(.system(size: theme.fontSize - 2, weight: .semibold))
                .foregroundStyle(theme.text.opacity(0.6))
            }
            HStack(spacing: 8) {
                answerButton("Not today", icon: "moon.zzz", tint: theme.text.opacity(0.75)) {
                    scheduler.answerGoal(goal, done: false)
                }
                answerButton("Done", icon: "checkmark.circle.fill", tint: ReminderRowView.onColor) {
                    scheduler.answerGoal(goal, done: true)
                }
            }
        }
        .padding(10)
        .background(theme.text.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func answerButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: theme.fontSize - 1, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}
