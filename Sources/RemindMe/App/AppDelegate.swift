import AppKit
import Combine
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var modelContainer: ModelContainer!
    private let menuBarFace = MenuBarFace()
    private var cancellables = Set<AnyCancellable>()
    private var backupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // belt-and-suspenders alongside LSUIElement

        modelContainer = PersistenceController.makeContainer()

        Task { @MainActor in
            ReminderPanelController.shared.configure(modelContainer: modelContainer)
            NotificationService.shared.requestAuthorizationIfNeeded()
            ReminderScheduler.shared.start(modelContext: modelContainer.mainContext)
            GlobalHotkeys.shared.start()
            BreakCycleManager.shared.activate()
            LoginItem.applyAtLaunch()
            RenderWatcher.shared.start()
            self.startDailyBackups()
        }

        setUpStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A copy of everything, once a day, in Application Support (last 7 kept).
    private func startDailyBackups() {
        let save = { [weak self] in
            guard let context = self?.modelContainer?.mainContext else { return }
            Backup.autoSave(from: context)
        }
        save()
        let timer = Timer(timeInterval: 3 * 3600, repeats: true) { _ in
            Task { @MainActor in save() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        backupTimer = timer
    }

    private func setUpStatusItem() {
        // The —ω— logo; wider than a square glyph, so variable length. It
        // reacts when hovered and shows a waiting reminder's mood.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            menuBarFace.attach(to: button)
            button.toolTip = "Remind Me"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // The break timer counts down at the notch (BreakIsland), not here:
        // the menu bar keeps just the face.
        // For "under the menu bar icon" placement.
        ReminderPanelController.shared.statusItemFrame = { [weak self] in
            self?.statusItem.button?.window?.frame
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            Task { @MainActor in
                ReminderPanelController.shared.toggleVisibility()
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if let action = UndoCenter.shared.available {
            menu.addItem(withTitle: "Undo \(action.label)", action: #selector(undoLast), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Weekly Summary", action: #selector(showWeeklySummary), keyEquivalent: "").target = self
        if BreakCycleManager.shared.isRunning {
            let keep = NSMenuItem(title: "Keep Work Countdown at Notch", action: #selector(toggleKeepCountdown), keyEquivalent: "")
            keep.target = self
            keep.state = AppSettings.breakTimer.value.keepWorkCountdown ? .on : .off
            menu.addItem(keep)
            menu.addItem(withTitle: "Stop Break Timer", action: #selector(stopBreakTimer), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Remind Me", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach so left-click goes back to toggling the panel
    }

    @objc private func undoLast() {
        UndoCenter.shared.undoLast()
    }

    @objc private func showWeeklySummary() {
        ReminderScheduler.shared.presentWeeklySummary()
    }

    @objc private func toggleKeepCountdown() {
        AppSettings.breakTimer.value.keepWorkCountdown.toggle()
    }

    @objc private func stopBreakTimer() {
        BreakCycleManager.shared.stop()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
