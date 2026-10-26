import AppKit
import Combine
import ServiceManagement

/// The app's state, refreshed from `wificonnector info` every few seconds.
///
/// SwiftUI watches the @Published properties and redraws the menu-bar icon and
/// the menu whenever they change. Script calls block, so they run on a
/// background queue and publish their results back on the main queue.
final class StatusModel: ObservableObject {
    @Published private(set) var info = EngineInfo()
    /// A login, logout or install is running.
    @Published private(set) var busy = false
    /// The outcome of the last action, shown in the menu until the next one.
    @Published private(set) var lastAction = ""

    private var timer: Timer?
    private var refreshing = false

    init() {
        // Read once right away, so the app knows before its windows open
        // whether to show the welcome window. `info` only reads files, so
        // this is quick.
        info = EngineInfo(parsing: Engine.run(["info"]).output)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    var symbol: String { info.symbol(busy: busy) }

    /// Nothing will log in automatically until both of these are done.
    var needsSetup: Bool { !info.credentials || !info.agent }

    // MARK: Reading the state

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let parsed = EngineInfo(parsing: Engine.run(["info"]).output)
            DispatchQueue.main.async {
                self.refreshing = false
                if parsed != self.info { self.info = parsed }
            }
        }
    }

    // MARK: Actions

    func logIn() { perform(["login"]) }

    func logOut() { perform(["logout"]) }

    func togglePause() { perform([info.paused ? "resume" : "pause"]) }

    func installAgent() { perform(["install"]) }

    /// The password reaches the script on stdin, never as an argument.
    func saveCredentials(user: String, password: String, completion: @escaping (Engine.Result) -> Void) {
        perform(["set-credentials", user], input: password + "\n", completion: completion)
    }

    /// The welcome window's one button: everything the menu would otherwise
    /// need, in order. Stops at the first step that fails, except the login,
    /// which can't work until you're on VIT hostel Wi-Fi.
    func setUp(user: String, password: String,
               progress: @escaping (SetupStep) -> Void,
               completion: @escaping (SetupOutcome) -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.runSetup(user: user, password: password) { step in
                DispatchQueue.main.async { progress(step) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.lastAction = outcome.message
                completion(outcome)
                // Start at Login isn't @Published, so say it may have changed.
                self.objectWillChange.send()
                self.refresh()
            }
        }
    }

    private static func runSetup(user: String, password: String,
                                 progress: (SetupStep) -> Void) -> SetupOutcome {
        progress(.credentials)
        let saved = Engine.run(["set-credentials", user], input: password + "\n")
        guard saved.succeeded else { return SetupOutcome(failed: .credentials, saved) }

        progress(.agent)
        let installed = Engine.run(["install"])
        guard installed.succeeded else { return SetupOutcome(failed: .agent, installed) }

        progress(.startAtLogin)
        do {
            try SMAppService.mainApp.register()
        } catch {
            return SetupOutcome(failedStep: .startAtLogin, loggedIn: false,
                                message: "Couldn't turn on Start at Login: \(error.localizedDescription)")
        }

        // The agent starts checking as soon as it's installed and may be
        // logging in already, holding the lock; then wait for it.
        progress(.login)
        var login = Engine.run(["login"])
        var tries = 1
        while !login.succeeded && login.output.contains("in progress") && tries < 6 {
            Thread.sleep(forTimeInterval: 2)
            login = Engine.run(["login"])
            tries += 1
        }
        return SetupOutcome(failedStep: nil, loggedIn: login.succeeded,
                            message: LogLine.message(of: login.lastLine))
    }

    private func perform(_ arguments: [String], input: String? = nil,
                         completion: ((Engine.Result) -> Void)? = nil) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Engine.run(arguments, input: input)
            DispatchQueue.main.async {
                self.busy = false
                self.lastAction = LogLine.message(of: result.lastLine)
                completion?(result)
                self.refresh()
            }
        }
    }

    // MARK: The app itself

    func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/wificonnector.log")
        NSWorkspace.shared.open(log)
    }

    var startsAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastAction = "Couldn't change Start at Login: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }
}

/// The steps the welcome window runs, in order.
enum SetupStep: Int, CaseIterable, Identifiable {
    case credentials, agent, startAtLogin, login

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .credentials: return "Save your password in the Keychain"
        case .agent: return "Turn on automatic login"
        case .startAtLogin: return "Start WiFiConnector when your Mac starts"
        case .login: return "Log in now"
        }
    }
}

struct SetupOutcome {
    /// nil when every step up to the login worked.
    let failedStep: SetupStep?
    let loggedIn: Bool
    /// The last step's own words: an error, or how the login went.
    let message: String

    init(failedStep: SetupStep?, loggedIn: Bool, message: String) {
        self.failedStep = failedStep
        self.loggedIn = loggedIn
        self.message = message
    }

    init(failed step: SetupStep, _ result: Engine.Result) {
        self.init(failedStep: step, loggedIn: false, message: LogLine.message(of: result.lastLine))
    }
}
