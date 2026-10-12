import AppKit
import Foundation

/// Best-effort checks for whether the panel should stay quiet right now.
///
/// Full-screen detection is solid: it reads the on-screen window list
/// through the public `CGWindowListCopyWindowInfo` API (no special
/// entitlement) and checks whether the frontmost window covers an entire
/// display — the same technique used to detect Mission Control's overview
/// window.
///
/// Do Not Disturb / Focus has no public API for a third-party app to read on
/// macOS 14. This reads the same local, undocumented assertions store other
/// menu-bar utilities have historically used — it is NOT a supported API,
/// and Apple can change its format or remove it on any OS update with no
/// notice. Any failure to read it (missing file, changed shape, sandboxing)
/// is treated as "Focus is off," never as "suppress" — a reminder app that
/// can fail silent is worse than one that occasionally pops during Focus.
enum FocusGuard {
    static func shouldSuppress() -> Bool {
        isFullScreenAppActive() || isDoNotDisturbActive()
    }

    static func isFullScreenAppActive() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        guard let screen = NSScreen.main?.frame else { return false }

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { continue }
            if width >= screen.width - 1 && height >= screen.height - 1 { return true }
        }
        return false
    }

    static func isDoNotDisturbActive() -> Bool {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = json["storeAssertionRecords"] as? [[String: Any]] else {
            return false
        }
        return !records.isEmpty
    }
}
