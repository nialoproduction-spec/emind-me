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
    /// Heads-ups partway through a phase, each shown once per phase.
    enum Milestone: Hashable { case lastTen, lastSeconds }

    /// "Last 10 minutes" pops up when a work stretch is down to this.
    static let lastTenThreshold: TimeInterval = 10 * 60
    /// The final stretch: the countdown popup stays on screen from here.
    static let lastSecondsThreshold: TimeInterval = 10

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

    var phaseMinutes: Int { phase == .work ? config.workMinutes : config.breakMinutes }

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

    /// The most urgent heads-up that's due and hasn't been shown this phase.
    /// "Last 10 minutes" only exists for work stretches long enough for it to
    /// mean something (so a 5-minute test cycle doesn't open with it).
    func dueMilestone(at now: Date, shown: Set<Milestone>) -> Milestone? {
        let left = remaining(at: now)
        if left > 0, left <= Self.lastSecondsThreshold, !shown.contains(.lastSeconds) {
            return .lastSeconds
        }
        if phase == .work,
           TimeInterval(phaseMinutes * 60) > Self.lastTenThreshold + 60,
           left > Self.lastSecondsThreshold, left <= Self.lastTenThreshold,
           !shown.contains(.lastTen) {
            return .lastTen
        }
        return nil
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

/// Runs the break cycle: a countdown in the menu bar plus a popup at the
/// moments that matter. Silent: no beeps, no notification sounds.
///
/// Popups: when a work stretch starts ("40 minutes to go", counting), with
/// 10 minutes left, for the last 10 seconds (stays up, counting), when the
/// break starts ("Time for a break · Rest for 10 minutes."), and when it ends.
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
    /// Show a popup; nil puts the current one away.
    private let notice: @MainActor (NoticeContent?) -> Void

    private var timer: Timer?
    private var timerEnabled = false
    private var sleepStart: Date?
    private var observers: [NSObjectProtocol] = []
    private var shown: Set<BreakCycleState.Milestone> = []

    init(
        defaults: UserDefaults = .standard,
        now: (@MainActor () -> Date)? = nil,
        notice: (@MainActor (NoticeContent?) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.clock = now ?? { Date.now }
        self.notice = notice ?? { content in
            if let content {
                NoticePillController.shared.show(content)
            } else {
                NoticePillController.shared.hide()
            }
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
        shown = []
        let now = clock()
        let fresh = BreakCycleState.started(config, at: now)
        state = fresh
        persist()
        menuBarTitle = fresh.menuBarTitle(at: now)
        if timerEnabled { startTimer() }
        notice(Self.workStartNotice(for: fresh, afterBreak: false))
    }

    func stop() {
        state = nil
        sleepStart = nil
        shown = []
        menuBarTitle = ""
        timer?.invalidate()
        timer = nil
        defaults.removeObject(forKey: key)
        notice(nil)
    }

    // MARK: - Tick

    func tick() {
        guard var current = state, sleepStart == nil else { return }
        let now = clock()
        if let event = current.advance(now: now) {
            state = current
            shown = []
            persist()
            switch event {
            case .breakStarted: notice(Self.breakStartNotice(for: current))
            case .breakEnded: notice(Self.workStartNotice(for: current, afterBreak: true))
            }
        } else if let milestone = current.dueMilestone(at: now, shown: shown) {
            shown.insert(milestone)
            // The last seconds also cover "last 10 minutes" if a wake-up jumped
            // straight past it, so it doesn't pop up late.
            if milestone == .lastSeconds { shown.insert(.lastTen) }
            notice(Self.milestoneNotice(milestone, for: current))
        }
        let title = current.menuBarTitle(at: now)
        if title != menuBarTitle { menuBarTitle = title }
    }

    // MARK: - Popup wording

    static func workStartNotice(for state: BreakCycleState, afterBreak: Bool) -> NoticeContent {
        let left = Item.durationString(TimeInterval(state.config.workMinutes * 60))
        return NoticeContent(
            title: afterBreak ? "Break over · \(left) to go" : "\(left) to go",
            countdownTo: state.phaseEnd,
            face: afterBreak ? .happy : .smug
        )
    }

    static func breakStartNotice(for state: BreakCycleState) -> NoticeContent {
        let rest = Item.durationString(TimeInterval(state.config.breakMinutes * 60))
        return NoticeContent(
            title: "Time for a break",
            detail: "Rest for \(rest).",
            face: .sheepish,
            duration: 8
        )
    }

    static func milestoneNotice(_ milestone: BreakCycleState.Milestone, for state: BreakCycleState) -> NoticeContent {
        switch milestone {
        case .lastTen:
            return NoticeContent(title: "Last 10 minutes to go", countdownTo: state.phaseEnd, face: .owo, duration: 8)
        case .lastSeconds:
            let title = state.phase == .work ? "Break time is almost here" : "Break is almost over"
            // Stays up, counting, until the phase ends and the next popup replaces it.
            return NoticeContent(title: title, countdownTo: state.phaseEnd, face: .squee, sticky: true)
        }
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
