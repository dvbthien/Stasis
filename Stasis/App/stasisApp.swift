import SwiftUI

@main
struct StasisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A Settings scene rather than Window: it is never presented or
        // restored at launch and closing it never quits the app, which is
        // exactly the lifecycle a menu-bar app needs. Its chrome (hidden
        // title, compact toolbar) is applied in SettingsSceneController, since
        // the Settings scene ignores `.windowStyle(.hiddenTitleBar)`.
        Settings {
            SettingsRootView()
        }
    }
}
