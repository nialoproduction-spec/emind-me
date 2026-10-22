import Foundation
import ServiceManagement

/// Opens Remind Me when the Mac starts, and brings it back if it crashes, so
/// reminders keep firing after a restart. It's a launch agent rather than a
/// plain login item, because launchd can restart a crashed agent. A normal
/// Quit exits cleanly, so the app stays quit until you open it again.
/// On by default: turned on at the first launch; after that it follows the
/// switch in Settings (and System Settings → Login Items).
@MainActor
enum LoginItem {
    static let agentPlist = "com.anshukc.remindme.keepalive.plist"
    private static var agent: SMAppService { SMAppService.agent(plistName: agentPlist) }

    static var status: SMAppService.Status { agent.status }

    static var isOn: Bool { status == .enabled || status == .requiresApproval }

    /// macOS wants a yes in System Settings → General → Login Items.
    static var needsApproval: Bool { status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                retireOldLoginItem()
                guard status != .enabled else { return true }
                try agent.register()
            } else {
                retireOldLoginItem()
                guard status != .notRegistered else { return true }
                try agent.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// Versions before this one opened the app directly at login. Remove that
    /// entry, so the app doesn't start twice (once from it, once from the agent).
    private static func retireOldLoginItem() {
        guard SMAppService.mainApp.status != .notRegistered else { return }
        try? SMAppService.mainApp.unregister()
    }

    /// At launch: the first time, turn it on (the default); later, show the
    /// real state, so turning it off anywhere sticks.
    static func applyAtLaunch(_ store: PersistedSettings<LoginSettings>? = nil) {
        let settings = store ?? AppSettings.login
        if !settings.value.registeredOnce {
            settings.value.registeredOnce = true
            if settings.value.openAtLogin { set(true) }
        }
        // Upgrading from the old login item: move it over to the agent, once.
        if SMAppService.mainApp.status != .notRegistered {
            let wasOn = SMAppService.mainApp.status == .enabled
            retireOldLoginItem()
            if wasOn { set(true) }
        }
        settings.value.openAtLogin = isOn
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
