import Foundation
import CoreGraphics

/// "Is anyone at the Mac?" — from how long it's been since the last key
/// press, click or mouse move. Used to hold reminders while you're away and
/// show them when you're back, instead of letting them nag an empty room and
/// run out of attempts.
///
/// Reading the idle time needs no permission and sees no keystrokes — just
/// the number of seconds since the last input event of any kind.
@MainActor
enum AwayDetector {
    static func idleSeconds() -> TimeInterval {
        // ~0 is "any input event type".
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static func isAway() -> Bool {
        isAway(idleSeconds: idleSeconds(), settings: AppSettings.smart.value)
    }

    nonisolated static func isAway(idleSeconds: TimeInterval, settings: SmartSettings) -> Bool {
        guard settings.holdWhileAway, settings.awayMinutes > 0 else { return false }
        return idleSeconds >= TimeInterval(settings.awayMinutes * 60)
    }
}
