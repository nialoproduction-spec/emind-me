import Foundation
import AppKit
import Combine

/// "Work for N, then rest for M", repeating until stopped. Lengths are in
/// seconds so "work 30 sec, rest 10 sec" works; saved cycles from before
/// (in minutes) still load.
struct BreakCycleConfig: Codable, Equatable {
    var workSeconds: Int
    var breakSeconds: Int

    init(workSeconds: Int, breakSeconds: Int) {
        self.workSeconds = max(1, workSeconds)
        self.breakSeconds = max(1, breakSeconds)
    }

    init(workMinutes: Int, breakMinutes: Int) {
        self.init(workSeconds: workMinutes * 60, breakSeconds: breakMinutes * 60)
    }

    private enum CodingKeys: String, CodingKey { case workSeconds, breakSeconds, workMinutes, breakMinutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let work = try c.decodeIfPresent(Int.self, forKey: .workSeconds),
           let rest = try c.decodeIfPresent(Int.self, forKey: .breakSeconds) {
            self.init(workSeconds: work, breakSeconds: rest)
        } else {
            self.init(workMinutes: try c.decode(Int.self, forKey: .workMinutes),
                      breakMinutes: try c.decode(Int.self, forKey: .breakMinutes))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workSeconds, forKey: .workSeconds)
        try c.encode(breakSeconds, forKey: .breakSeconds)
    }

    /// "Work 40 min · Rest 10 min"
    var title: String { "Work \(Self.short(workSeconds)) · Rest \(Self.short(breakSeconds))" }

    /// "40 min", "1 hr", "30 sec", "1 hr 30 min".
    static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds % 3600 == 0 { return "\(seconds / 3600) hr" }
        if seconds > 3600 { return "\(seconds / 3600) hr \((seconds % 3600) / 60) min" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60) min \(seconds % 60) sec"
    }
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
            phaseEnd: now.addingTimeInterval(TimeInterval(config.workSeconds))
        )
    }

    var phaseSeconds: Int { phase == .work ? config.workSeconds : config.breakSeconds }

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
            phaseEnd = now.addingTimeInterval(TimeInterval(config.breakSeconds))
            return .breakStarted
        case .onBreak:
            phase = .work
            phaseEnd = now.addingTimeInterval(TimeInterval(config.workSeconds))
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
           TimeInterval(phaseSeconds) > Self.lastTenThreshold + 60,
           left > Self.lastSecondsThreshold, left <= Self.lastTenThreshold,
           !shown.contains(.lastTen) {
            return .lastTen
        }
        return nil
    }

    /// "9:42" — rounds up, so it reads 0:01 until the moment it ends.
    static func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
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
/// Popups (the notch island): when a work stretch starts ("Work · 40:00",
/// counting, a few seconds), with 10 minutes left ("Last 10 minutes · 9:59"),
/// for the last 10 seconds (stays out, counting to 0:00), when the break
/// starts ("Time for a break · Rest for 10 minutes."), and when it ends.
///
/// Kept out of SwiftData on purpose: it's one small piece of live state, not
/// a routine with a history, so it lives in UserDefaults (no model change,
/// and it survives a restart). The 1-second timer only refreshes the text and
/// compares dates; it never accumulates elapsed time itself.
@MainActor
final class BreakCycleManager: ObservableObject {
    static let shared = BreakCycleManager()

    @Published private(set) var state: BreakCycleState?
    /// The saved timer, running or not. It stays (greyed out in the list)
    /// when turned off, so it can be turned back on with one click; only
    /// `remove()` forgets it.
    @Published private(set) var config: BreakCycleConfig?
    /// Empty when no cycle is running.
    @Published private(set) var menuBarTitle = ""

    var isRunning: Bool { state != nil }

    private let defaults: UserDefaults
    private let key = "breakCycle.v1"
    private let configKey = "breakCycle.config.v1"
    private let clock: @MainActor () -> Date
    /// Announce a moment at the notch; nil puts it away.
    private let notice: @MainActor (NoticeContent?) -> Void
    /// The running timer for the notch's small countdown; nil = none.
    private let ambient: @MainActor (BreakCycleState?) -> Void

    private var timer: Timer?
    private var timerEnabled = false
    private var sleepStart: Date?
    private var observers: [NSObjectProtocol] = []
    private var shown: Set<BreakCycleState.Milestone> = []

    init(
        defaults: UserDefaults = .standard,
        now: (@MainActor () -> Date)? = nil,
        notice: (@MainActor (NoticeContent?) -> Void)? = nil,
        ambient: (@MainActor (BreakCycleState?) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.clock = now ?? { Date.now }
        self.notice = notice ?? { content in
            if let content {
                BreakIslandController.shared.show(content)
            } else {
                BreakIslandController.shared.hide()
            }
        }
        self.ambient = ambient ?? { BreakIslandController.shared.setAmbient($0) }
        if let data = defaults.data(forKey: configKey),
           let saved = try? JSONDecoder().decode(BreakCycleConfig.self, from: data) {
            config = saved
        }
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(BreakCycleState.self, from: data) {
            state = saved
            config = config ?? saved.config
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
        ambient(state)
        tick()
    }

    /// Begins a fresh cycle (replacing any running one) with the work phase.
    func startCycle(_ config: BreakCycleConfig) {
        sleepStart = nil
        shown = []
        let now = clock()
        let fresh = BreakCycleState.started(config, at: now)
        state = fresh
        self.config = config
        persist()
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: configKey) }
        menuBarTitle = fresh.menuBarTitle(at: now)
        if timerEnabled { startTimer() }
        ambient(fresh)
        notice(Self.workStartNotice(for: fresh, afterBreak: false))
    }

    /// Turns the saved timer back on, from the start of a work stretch.
    func resume() {
        guard let config else { return }
        startCycle(config)
    }

    /// Turns it off and forgets it: gone from the list too.
    func remove() {
        stop()
        config = nil
        defaults.removeObject(forKey: configKey)
    }

    /// Turns it off; it stays in the list, greyed out.
    func stop() {
        state = nil
        sleepStart = nil
        shown = []
        menuBarTitle = ""
        timer?.invalidate()
        timer = nil
        defaults.removeObject(forKey: key)
        ambient(nil)
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
            ambient(current)
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

    /// "Work" on the left, the countdown on the right, for a few seconds.
    static func workStartNotice(for state: BreakCycleState, afterBreak: Bool) -> NoticeContent {
        NoticeContent(
            title: afterBreak ? "Back to work" : "Work",
            countdownTo: state.phaseEnd,
            face: afterBreak ? .happy : .smug,
            duration: 5
        )
    }

    /// "Time for a break" on the left, "Rest for 5 minutes." on the right.
    static func breakStartNotice(for state: BreakCycleState) -> NoticeContent {
        let rest = Item.durationString(TimeInterval(state.config.breakSeconds))
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
            return NoticeContent(title: "Last 10 minutes", countdownTo: state.phaseEnd, face: .owo, duration: 6)
        case .lastSeconds:
            // Stays out, counting to 0:00, until the next one replaces it.
            let title = state.phase == .work ? "Break in" : "Back to work in"
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
        ambient(current)
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
