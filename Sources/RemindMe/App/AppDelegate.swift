import AppKit
import Combine
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var modelContainer: ModelContainer!
    private let menuBarFace = MenuBarFace()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // belt-and-suspenders alongside LSUIElement

        modelContainer = PersistenceController.makeContainer()

        Task { @MainActor in
            ReminderPanelController.shared.configure(modelContainer: modelContainer)
            NotificationService.shared.requestAuthorizationIfNeeded()
            ReminderScheduler.shared.start(modelContext: modelContainer.mainContext)
            GlobalHotkeys.shared.start()
            BreakCycleManager.shared.activate()
        }

        setUpStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        // The break timer's countdown, next to the icon while a cycle runs.
        BreakCycleManager.shared.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in self?.showBreakTitle(title) }
            .store(in: &cancellables)
        // For "under the menu bar icon" placement.
        ReminderPanelController.shared.statusItemFrame = { [weak self] in
            self?.statusItem.button?.window?.frame
        }
    }

    private func showBreakTitle(_ title: String) {
        guard let button = statusItem?.button else { return }
        if title.isEmpty {
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = " " + title
            button.imagePosition = .imageLeft
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
        menu.addItem(withTitle: "Weekly Summary", action: #selector(showWeeklySummary), keyEquivalent: "").target = self
        if BreakCycleManager.shared.isRunning {
            menu.addItem(withTitle: "Stop Break Timer", action: #selector(stopBreakTimer), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Remind Me", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach so left-click goes back to toggling the panel
    }

    @objc private func showWeeklySummary() {
        ReminderScheduler.shared.presentWeeklySummary()
    }

    @objc private func stopBreakTimer() {
        BreakCycleManager.shared.stop()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
