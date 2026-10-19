import Foundation
import AppKit
import Combine

/// "Work for N minutes, then rest for M minutes", repeating until stopped.
struct BreakCycleConfig: Codable, Equatable {
    var workMinutes: Int
    var breakMinutes: Int
}

/// Where a break cycle is right now. Pure data and date maths, no timers:
/// the end of the current phase is an absolute `Date` (rule 3), and callers
/// just ask "has it passed?".
struct BreakCycleState: Codable, Equatable {
    enum Phase: String, Codable { case work, onBreak }
    enum Event: Equatable { case breakStarted, breakEnded }

    var config: BreakCycleConfig
    var phase: Phase
    /// When the current phase ends.
    var phaseEnd: Date

    static func started(_ config: BreakCycleConfig, at now: Date) -> BreakCycleState {
        BreakCycleState(
            config: config, phase: .work,
            phaseEnd: now.addingTimeInterval(TimeInterval(config.workMinutes * 60))
        )
    }

    /// Moves to the next phase if the current one is over. Returns what
    /// happened, or nil if nothing changed. At most one step per call, and the
    /// next phase counts from `now`: a long gap costs one missed switch, never
    /// a backlog of them.
    @discardableResult
    mutating func advance(now: Date) -> Event? {
        guard now >= phaseEnd else { return nil }
        switch phase {
        case .work:
            phase = .onBreak
            phaseEnd = now.addingTimeInterval(TimeInterval(config.breakMinutes * 60))
            return .breakStarted
        case .onBreak:
            phase = .work
            phaseEnd = now.addingTimeInterval(TimeInterval(config.workMinutes * 60))
            return .breakEnded
        }
    }

    /// The Mac was asleep for `seconds`: push the end back so sleep doesn't
    /// count as work or as rest.
    mutating func shiftForward(by seconds: TimeInterval) {
        phaseEnd = phaseEnd.addingTimeInterval(max(0, seconds))
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, phaseEnd.timeIntervalSince(now))
    }

    /// "9:42" — rounds up, so it reads 0:01 until the moment it ends.
    static func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Text shown next to the menu bar icon.
    func menuBarTitle(at now: Date) -> String {
        let time = Self.clockString(remaining(at: now))
        return phase == .onBreak ? "Break \(time)" : time
    }
}

/// Runs the break cycle and shows its countdown in the menu bar.
///
/// Kept out of SwiftData on purpose: it's one small piece of live state, not
/// a routine with a history, so it lives in UserDefaults (no model change,
/// and it survives a restart). The 1-second timer only refreshes the text and
/// compares dates; it never accumulates elapsed time itself.
@MainActor
final class BreakCycleManager: ObservableObject {
    static let shared = BreakCycleManager()

    @Published private(set) var state: BreakCycleState?
    /// Empty when no cycle is running.
    @Published private(set) var menuBarTitle = ""

    var isRunning: Bool { state != nil }

    private let defaults: UserDefaults
    private let key = "breakCycle.v1"
    private let clock: @MainActor () -> Date
    private let beep: @MainActor (Int) -> Void
    private let notify: @MainActor (String, String) -> Void

    private var timer: Timer?
    private var timerEnabled = false
    private var sleepStart: Date?
    private var observers: [NSObjectProtocol] = []

    init(
        defaults: UserDefaults = .standard,
        now: (@MainActor () -> Date)? = nil,
        beep: (@MainActor (Int) -> Void)? = nil,
        notify: (@MainActor (String, String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.clock = now ?? { Date.now }
        self.beep = beep ?? { count in
            // The system alert sound, a few times so it isn't missed.
            Task { @MainActor in
                for _ in 0..<count {
                    NSSound.beep()
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        self.notify = notify ?? { title, body in
            NotificationService.shared.postNow(title: title, body: body)
        }
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(BreakCycleState.self, from: data) {
            state = saved
            menuBarTitle = saved.menuBarTitle(at: self.clock())
        }
    }

    // MARK: - Lifecycle

    /// Called once at launch: starts the countdown display and the sleep /
    /// wake handling. Tests skip this and call `tick()` themselves.
    func activate() {
        timerEnabled = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.willSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        })
        if state != nil { startTimer() }
        tick()
    }

    /// Begins a fresh cycle (replacing any running one) with the work phase.
    func startCycle(_ config: BreakCycleConfig) {
        sleepStart = nil
        let fresh = BreakCycleState.started(config, at: clock())
        state = fresh
        persist()
        menuBarTitle = fresh.menuBarTitle(at: clock())
        if timerEnabled { startTimer() }
    }

    func stop() {
        state = nil
        sleepStart = nil
        menuBarTitle = ""
        timer?.invalidate()
        timer = nil
        defaults.removeObject(forKey: key)
    }

    // MARK: - Tick

    func tick() {
        guard var current = state, sleepStart == nil else { return }
        let now = clock()
        if let event = current.advance(now: now) {
            state = current
            persist()
            switch event {
            case .breakStarted:
                beep(1)
                notify("Time for a break", "Rest for \(current.config.breakMinutes) minutes.")
            case .breakEnded:
                beep(3)
                notify("Break over", "Back to work. Next break in \(current.config.workMinutes) minutes.")
            }
        }
        let title = current.menuBarTitle(at: now)
        if title != menuBarTitle { menuBarTitle = title }
    }

    // MARK: - Sleep: the cycle pauses while the Mac sleeps

    func willSleep() {
        guard state != nil, sleepStart == nil else { return }
        sleepStart = clock()
    }

    func didWake() {
        guard var current = state, let started = sleepStart else { return }
        current.shiftForward(by: clock().timeIntervalSince(started))
        sleepStart = nil
        state = current
        persist()
        tick()
    }

    // MARK: - Private

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        newTimer.tolerance = 0.2
        RunLoop.main.add(newTimer, forMode: .common) // keeps counting while a menu is open
        timer = newTimer
    }

    private func persist() {
        guard let state, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
