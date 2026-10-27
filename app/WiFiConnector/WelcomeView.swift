import AppKit
import SwiftUI

/// Opens by itself on the first launch, and from "Set Up…" in the menu (see
/// AppWindow, which hosts it). One form and one button replace the three
/// menu steps (Settings, Install Background Agent, Start at Login), then it
/// shows where the icon lives, because a menu-bar app has no window or Dock
/// icon to find it by.
struct WelcomeView: View {
    @ObservedObject var model: StatusModel
    /// Closes the window it's in.
    let close: () -> Void

    @State private var user = ""
    @State private var password = ""
    /// The step running now; nil before Save and Turn On, and after it.
    @State private var current: SetupStep?
    @State private var outcome: SetupOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let outcome, outcome.failedStep == nil {
                finished(outcome)
            } else {
                form
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { user = model.info.user }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to WiFiConnector")
                    .font(.title2.weight(.semibold))
                Text("It logs you in to VIT hostel Wi-Fi by itself, every time you connect.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Before and during setup

    private var running: Bool { current != nil }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Registration number")
                        .gridColumnAlignment(.trailing)
                    TextField("Registration number", text: $user, prompt: Text("26BCE0000"))
                        .labelsHidden()
                }
                GridRow {
                    Text("Wi-Fi password")
                    SecureField("Wi-Fi password", text: $password)
                        .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(running)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SetupStep.allCases) { step in
                    stepRow(step)
                }
            }

            if let outcome, let failed = outcome.failedStep {
                Text("\(failed.title) didn't work: \(outcome.message)")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Your password goes straight into your login Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save and Turn On") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(user.isEmpty || password.isEmpty || running)
            }
        }
    }

    private func stepRow(_ step: SetupStep) -> some View {
        HStack(spacing: 8) {
            Group {
                switch status(of: step) {
                case .waiting:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 16, height: 16)
            Text(step.title)
                .foregroundStyle(status(of: step) == .waiting ? Color.secondary : Color.primary)
        }
    }

    private enum StepStatus { case waiting, running, done, failed }

    private func status(of step: SetupStep) -> StepStatus {
        if let current {
            if step == current { return .running }
            return step.rawValue < current.rawValue ? .done : .waiting
        }
        if let failed = outcome?.failedStep {
            if step == failed { return .failed }
            return step.rawValue < failed.rawValue ? .done : .waiting
        }
        return .waiting
    }

    private func start() {
        outcome = nil
        current = .credentials
        model.setUp(user: user, password: password) { step in
            current = step
        } completion: { result in
            current = nil
            password = ""
            outcome = result
        }
    }

    // MARK: After setup

    private func finished(_ outcome: SetupOutcome) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if outcome.loggedIn {
                Label("You're all set, and you're online.", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if outcome.message.contains("refused") {
                Label("VIT Wi-Fi refused that password.", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Check it and save it again. Everything else is set up.")
                    .foregroundStyle(.secondary)
            } else {
                Label("You're all set.", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("It couldn't log in just now (\(outcome.message)). That's expected when you aren't on VIT hostel Wi-Fi; it logs in by itself as soon as you join.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MenuBarPicture(symbol: model.symbol)
            Text("WiFiConnector lives in the menu bar at the top right of your screen. Click its icon to log in or out, or to pause it. If you can't see it, the notch may be hiding it: quit an app with a menu-bar icon to make room.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if !outcome.loggedIn && outcome.message.contains("refused") {
                    Button("Change Password") { self.outcome = nil }
                }
                Spacer()
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A drawing of the right end of the menu bar with WiFiConnector's icon
/// circled, so people know what to look for.
private struct MenuBarPicture: View {
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "battery.75percent")
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 30, height: 30)
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
            }
            Image(systemName: "magnifyingglass")
            Image(systemName: "switch.2")
            Text("Mon 9:41")
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
