import Foundation
import ServiceManagement

/// Opens Remind Me when the Mac starts, so reminders keep firing after a
/// restart. On by default: turned on at the first launch; after that it
/// follows the switch in Settings (and System Settings → Login Items).
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isOn: Bool { status == .enabled || status == .requiresApproval }

    /// macOS wants a yes in System Settings → General → Login Items.
    static var needsApproval: Bool { status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                guard status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard status != .notRegistered else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// At launch: the first time, turn it on (the default); later, show the
    /// real state, so turning it off anywhere sticks.
    static func applyAtLaunch(_ store: PersistedSettings<LoginSettings>? = nil) {
        let settings = store ?? AppSettings.login
        if !settings.value.registeredOnce {
            settings.value.registeredOnce = true
            if settings.value.openAtLogin { set(true) }
        }
        settings.value.openAtLogin = isOn
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
