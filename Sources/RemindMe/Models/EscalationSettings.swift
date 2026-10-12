import Foundation

/// User-adjustable escalation behavior: how many times an unanswered
/// routine pops the panel, and how many minutes apart. Read fresh by the
/// scheduler on every check, so a change takes effect on the next pop
/// without disturbing whatever's already in flight.
struct EscalationSettings: Codable, Equatable {
    /// Total pop-ups before giving up and marking it unfinished.
    var maxReminders: Int = 3
    /// Minutes between each pop-up.
    var intervalMinutes: Int = 15

    static let `default` = EscalationSettings()

    static let maxRemindersRange = 1...10
    static let intervalMinutesRange = 1...120
}

@MainActor
final class EscalationSettingsStore: ObservableObject {
    static let shared = EscalationSettingsStore()

    private static let defaultsKey = "escalationSettings.v1"

    @Published var settings: EscalationSettings {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(EscalationSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
