import Foundation

/// Decides when a *held* Command key means "talk now": Command pressed on its
/// own for a moment, with no other key or modifier. Pure logic with no AppKit,
/// so it's tested with plain dates.
struct CommandHold {
    enum Event: Equatable { case begin, end }

    /// How long Command must be held alone before recording starts. Short
    /// enough to feel instant, long enough that a quick ⌘C or ⌘Z never starts it.
    static let threshold: TimeInterval = 0.35

    private(set) var armedAt: Date?
    private(set) var isHolding = false

    /// Call on every modifier change. `commandOnly` is true when Command is
    /// down and no other modifier is.
    mutating func modifiersChanged(commandOnly: Bool, at now: Date) -> Event? {
        if commandOnly {
            if armedAt == nil && !isHolding { armedAt = now }
            return nil
        }
        // Command let go, or another modifier joined it.
        armedAt = nil
        guard isHolding else { return nil }
        isHolding = false
        return .end
    }

    /// Call once the threshold may have passed. Returns `.begin` only once.
    mutating func tick(at now: Date) -> Event? {
        guard !isHolding, let armedAt, now.timeIntervalSince(armedAt) >= Self.threshold else { return nil }
        isHolding = true
        return .begin
    }

    /// Any other key while Command is held makes it a shortcut (⌘C), not a
    /// hold. Once recording has started, other keys don't stop it.
    mutating func otherKeyPressed() {
        if !isHolding { armedAt = nil }
    }
}

/// Decides when the talk key is *double-pressed* on its own: two quick taps
/// with nothing else in between. Pure logic, tested with plain dates.
struct DoubleTap {
    enum Event: Equatable { case tap, doubleTap }

    /// A tap is a press shorter than this.
    static let maxPress: TimeInterval = 0.35
    /// The second tap has to start within this of the first one ending.
    static let maxGap: TimeInterval = 0.45

    private(set) var downAt: Date?
    private(set) var lastTapAt: Date?
    private var interrupted = false

    /// Call on every modifier change. `talkOnly`: the talk key is down and no
    /// other modifier is. `anyModifier`: any modifier at all is down.
    mutating func modifiersChanged(talkOnly: Bool, anyModifier: Bool, at now: Date) -> Event? {
        if talkOnly {
            if downAt == nil {
                downAt = now
                interrupted = false
            }
            return nil
        }
        guard let down = downAt else { return nil }
        downAt = nil
        // Another modifier joined (⌘⇧…), a key was pressed, or it was held: not a tap.
        if anyModifier || interrupted || now.timeIntervalSince(down) > Self.maxPress {
            lastTapAt = nil
            return nil
        }
        if let last = lastTapAt, down.timeIntervalSince(last) <= Self.maxGap {
            lastTapAt = nil
            return .doubleTap
        }
        lastTapAt = now
        return .tap
    }

    /// Any other key (⌘C) means it was a shortcut, not a tap.
    mutating func otherKeyPressed() {
        interrupted = true
        lastTapAt = nil
    }

    /// Start fresh (after listening starts or stops).
    mutating func reset() {
        lastTapAt = nil
    }
}
