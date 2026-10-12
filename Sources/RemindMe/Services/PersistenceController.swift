import SwiftData
import Foundation

/// Local-only SwiftData store. No CloudKit, no sync, no account — the
/// database file lives in the app's own Application Support folder.
enum PersistenceController {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, Occurrence.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        // Clear out occurrences left pointing at deleted routines by older
        // builds — before SwiftData opens the store and trips over them.
        StoreRepair.removeOrphanedOccurrences(storeURL: configuration.url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData ModelContainer: \(error)")
        }
    }
}
