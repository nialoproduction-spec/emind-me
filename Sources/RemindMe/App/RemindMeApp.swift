import SwiftUI

@main
struct RemindMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible window scenes — the app lives entirely in the status
        // item and the floating panel, both owned by AppDelegate. A Settings
        // scene is just here so SwiftUI's App protocol has a Scene to vend;
        // it's never shown (LSUIElement hides the app from the menu bar's
        // app menu entirely).
        Settings {
            EmptyView()
        }
    }
}
