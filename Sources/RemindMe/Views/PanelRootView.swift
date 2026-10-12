import SwiftUI
import SwiftData

/// Root of the panel's SwiftUI content. Layers, in priority order: a live
/// reminder (routine just fired) overrides everything; the end-of-day and
/// weekly summaries override the ordinary views; otherwise it's the collapsed pill
/// or the expanded list. The controller owns the window itself — its size,
/// and when it fades in and out — and this view draws whichever layer
/// applies.
struct PanelRootView: View {
    @ObservedObject var controller: ReminderPanelController

    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var scheduler = ReminderScheduler.shared
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Query(sort: \Occurrence.scheduledFireDate, order: .reverse) private var occurrences: [Occurrence]
    @State private var showingSettings = false
    /// The reminder or summary that was on screen when the panel started to
    /// fade out, kept so the fade shows it rather than a sudden swap to the pill.
    @State private var heldOverlay: Layer?

    private enum Layer {
        case live(Occurrence)
        case endOfDay
        case weekly
        case expanded
        case pill
    }

    private var layer: Layer {
        if let occurrence = scheduler.activeOccurrence { return .live(occurrence) }
        if scheduler.showEndOfDaySummary { return .endOfDay }
        if scheduler.showWeeklySummary { return .weekly }
        if controller.isHiding, let held = heldOverlay { return held }
        return controller.isExpanded ? .expanded : .pill
    }

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

            switch layer {
            case .live(let occurrence):
                LiveReminderView(occurrence: occurrence, theme: themeStore.theme)
                    .id(occurrence.id) // fresh face + reaction state for every reminder
                    .transition(.opacity)
            case .endOfDay:
                EndOfDaySummaryView(
                    occurrencesToday: todayOccurrences,
                    theme: themeStore.theme,
                    onDismiss: { scheduler.dismissEndOfDaySummary() }
                )
                .transition(.opacity)
            case .weekly:
                WeeklySummaryView(
                    items: items,
                    occurrences: occurrences,
                    theme: themeStore.theme,
                    onClose: { scheduler.dismissWeeklySummary() }
                )
                .transition(.opacity)
            case .expanded:
                ExpandedPanelView(
                    items: items,
                    occurrences: occurrences,
                    todayOccurrences: todayOccurrences,
                    theme: themeStore.theme,
                    onCollapse: collapse,
                    onShowSettings: { showingSettings = true }
                )
                .transition(.opacity)
            case .pill:
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
        // Remember the overlay while it's up; forget it once it's gone and
        // the panel isn't mid-fade (e.g. it went back to the open list).
        .onChange(of: scheduler.activeOccurrence?.id) {
            if let occurrence = scheduler.activeOccurrence {
                heldOverlay = .live(occurrence)
            } else if !controller.isHiding {
                heldOverlay = nil
            }
        }
        .onChange(of: scheduler.showEndOfDaySummary) {
            if scheduler.showEndOfDaySummary {
                heldOverlay = .endOfDay
            } else if !controller.isHiding {
                heldOverlay = nil
            }
        }
        .onChange(of: scheduler.showWeeklySummary) {
            if scheduler.showWeeklySummary {
                heldOverlay = .weekly
            } else if !controller.isHiding {
                heldOverlay = nil
            }
        }
        .onChange(of: controller.isHiding) {
            if !controller.isHiding { heldOverlay = nil }
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
        controller.setExpanded(true)
    }

    private func collapse() {
        controller.setExpanded(false)
    }
}
