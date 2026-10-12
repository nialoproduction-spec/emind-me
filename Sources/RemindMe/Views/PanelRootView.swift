import SwiftUI
import SwiftData

/// Root of the panel's SwiftUI content. Three layers, in priority order:
/// a live reminder (routine just fired) overrides everything; the
/// end-of-day summary overrides the ordinary expand/collapse; otherwise
/// it's just the collapsed pill or the expanded list, as toggled by the
/// user. The controller owns the actual window resize animation for all of
/// these, this view just asks for it and draws whichever layer applies.
struct PanelRootView: View {
    unowned let controller: ReminderPanelController

    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var scheduler = ReminderScheduler.shared
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Query(sort: \Occurrence.scheduledFireDate, order: .reverse) private var occurrences: [Occurrence]
    @State private var isExpanded = false
    @State private var showingSettings = false

    private var active: [Item] {
        items.filter { $0.kind == .goal ? !$0.isAchieved : $0.isActive }
    }

    private var todayOccurrences: [Occurrence] {
        let key = Occurrence.dayKey(for: .now)
        return occurrences.filter { $0.dayKey == key }
    }

    var body: some View {
        ZStack {
            background

            if let occurrence = scheduler.activeOccurrence {
                LiveReminderView(occurrence: occurrence, theme: themeStore.theme)
                    .transition(.opacity)
            } else if scheduler.showEndOfDaySummary {
                EndOfDaySummaryView(
                    occurrencesToday: todayOccurrences,
                    theme: themeStore.theme,
                    onDismiss: { scheduler.dismissEndOfDaySummary() }
                )
                .transition(.opacity)
            } else if isExpanded {
                ExpandedPanelView(
                    items: items,
                    todayOccurrences: todayOccurrences,
                    theme: themeStore.theme,
                    onCollapse: collapse,
                    onShowSettings: { showingSettings = true }
                )
                .transition(.opacity)
            } else {
                CollapsedPillView(
                    activeItems: active,
                    theme: themeStore.theme,
                    onTap: expand
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: themeStore.theme.cornerRadius, style: .continuous))
        .sheet(isPresented: $showingSettings) {
            ThemeSettingsView(isPresented: $showingSettings)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: themeStore.theme.cornerRadius, style: .continuous)
            .fill(themeStore.theme.background.opacity(themeStore.theme.backgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: themeStore.theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func expand() {
        isExpanded = true
        controller.setExpanded(true)
    }

    private func collapse() {
        isExpanded = false
        controller.setExpanded(false)
    }
}
