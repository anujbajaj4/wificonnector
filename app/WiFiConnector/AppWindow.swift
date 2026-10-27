import AppKit
import SwiftUI

/// A window made with AppKit around a SwiftUI view: the welcome window and
/// Settings. SwiftUI's Window scene didn't open at launch in this menu-bar
/// app, and keeping it shut at launch needs macOS 15; an NSWindow opens
/// exactly when asked, on every macOS the app supports.
final class AppWindow {
    static let welcome = AppWindow(title: "Welcome to WiFiConnector")
    static let settings = AppWindow(title: "WiFiConnector Settings")

    private let title: String
    private var window: NSWindow?

    init(title: String) {
        self.title = title
    }

    /// Shows the window, making it from `content` unless it's already open.
    /// `content` gets a function that closes the window.
    func show<Content: View>(_ content: (_ close: @escaping () -> Void) -> Content) {
        // A closed window is replaced, so it starts afresh: Set Up… shows the
        // form again rather than the last finish screen.
        if window?.isVisible != true {
            let hosting = NSHostingController(rootView: content { [weak self] in self?.window?.close() })
            // The window follows the view's size, as the welcome window
            // switches between the form and the finish screen.
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable]
            // This object owns the window; AppKit mustn't free it on close.
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu-bar app isn't the active app on its own, and since macOS 14
        // it can't make itself active while you're using another app, such as
        // Terminal running the installer. orderFrontRegardless puts the
        // window on top either way.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Opens the welcome window once launch has finished, if nothing will log in
/// automatically yet.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = StatusModel.shared
        if model.needsSetup {
            AppWindow.welcome.show { close in WelcomeView(model: model, close: close) }
        }
    }
}
