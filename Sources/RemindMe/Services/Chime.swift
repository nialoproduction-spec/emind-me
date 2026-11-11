import AppKit

/// The faint sounds: a soft purr with a light trackpad buzz when a habit's
/// card appears, a quiet tink for a reminder's popup. Each can be turned off.
struct SoundSettings: Codable, Equatable {
    var habit = true
    var reminder = true
    /// 0…1; faint by default.
    var volume: Double = 0.25
}

@MainActor
enum Chime {
    enum Kind { case habit, reminder }

    static let settings = PersistedSettings(key: "sounds.v1", default: SoundSettings())

    static func play(_ kind: Kind) {
        // Only inside the real app: never in tests or previews.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let chosen = settings.value
        switch kind {
        case .habit:
            guard chosen.habit else { return }
            sound("Purr", volume: chosen.volume)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        case .reminder:
            guard chosen.reminder else { return }
            sound("Tink", volume: chosen.volume)
        }
    }

    private static func sound(_ name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(max(0, min(1, volume)))
        sound.play()
    }
}
