import Foundation
import SwiftData

/// The one way to delete a routine or goal, used by the list and by
/// Settings → Your reminders. It removes the item *and its occurrences*.
///
/// Why this matters: `Occurrence.item` is a one-way link, so deleting just the
/// item used to leave its occurrences pointing at a record that no longer
/// existed — and SwiftData stops the app the moment anything follows such a
/// link (which the scheduler does on every check, including at launch).
/// Deleting the occurrences here, explicitly, fixes that without changing the
/// database's shape, so existing data needs no migration.
@MainActor
enum ItemDeletion {
    /// How long to wait for the panel's fade-out before removing data the
    /// fading reminder card might still be drawing.
    static let fadeAllowance: Duration = .milliseconds(500)

    /// Deletes `item` with all its occurrences, cancels its notifications,
    /// and closes its reminder if that's what's on screen right now.
    static func delete(
        _ item: Item,
        in context: ModelContext,
        scheduler: ReminderScheduler? = nil,
        cancelNotifications: ((Item) -> Void)? = nil
    ) {
        let scheduler = scheduler ?? ReminderScheduler.shared
        (cancelNotifications ?? { NotificationService.shared.cancel(for: $0) })(item)

        if scheduler.closeLiveReminder(belongingTo: item) {
            // Its card is fading out: let it finish before the data goes, so
            // nothing on screen is left reading a deleted record.
            Task { @MainActor in
                try? await Task.sleep(for: fadeAllowance)
                removeData(of: item, in: context)
            }
        } else {
            removeData(of: item, in: context)
        }
    }

    /// The occurrences first, then the item, then save.
    static func removeData(of item: Item, in context: ModelContext) {
        guard !item.isDeleted else { return }
        let itemID = item.persistentModelID
        let occurrences = (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
        // Match on the link's identifier, which doesn't need to load the
        // linked record.
        for occurrence in occurrences where occurrence.item?.persistentModelID == itemID {
            context.delete(occurrence)
        }
        context.delete(item)
        try? context.save()
    }
}
