import SwiftUI

/// Where the registration number and password are entered, replacing
/// `wificonnector setup` in Terminal. The password is handed straight to the
/// script, which puts it in the login Keychain; the app keeps no copy.
struct SettingsView: View {
    @ObservedObject var model: StatusModel

    @State private var user = ""
    @State private var password = ""
    @State private var message = ""
    @State private var saving = false

    var body: some View {
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

            Text("The password goes straight into your login Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if saving {
                    ProgressView().controlSize(.small)
                }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(user.isEmpty || password.isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { user = model.info.user }
    }

    private func save() {
        saving = true
        message = ""
        model.saveCredentials(user: user, password: password) { result in
            saving = false
            password = ""
            message = result.succeeded
                ? "Saved. Choose “Log In Now” to try it."
                : LogLine.message(of: result.lastLine)
        }
    }
}
