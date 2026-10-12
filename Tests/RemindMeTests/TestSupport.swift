import Foundation
@testable import RemindMe

@MainActor
extension PersistedSettings {
    /// Settings under a throwaway key, so tests never read or change the real ones.
    static func testing(_ value: Value) -> PersistedSettings<Value> {
        PersistedSettings(key: "test.\(UUID().uuidString)", default: value)
    }
}
