import Foundation

/// Settings for the optional end-of-day summary. Off by default; the user
/// turns it on and picks a time from the panel's settings.
struct EndOfDaySettings: Codable, Equatable {
    var isEnabled: Bool = false
    var hour: Int = 21
    var minute: Int = 0
    /// "yyyy-MM-dd" of the last day the summary was shown, so it never
    /// shows twice for the same day even if the app relaunches.
    var lastShownDayKey: String?

    static let `default` = EndOfDaySettings()
}

@MainActor
final class EndOfDaySettingsStore: ObservableObject {
    static let shared = EndOfDaySettingsStore()

    private static let defaultsKey = "endOfDaySettings.v1"

    @Published var settings: EndOfDaySettings {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(EndOfDaySettings.self, from: data) {
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
