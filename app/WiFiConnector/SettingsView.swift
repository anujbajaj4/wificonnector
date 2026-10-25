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
        Form {
            Section {
                TextField("Registration number", text: $user, prompt: Text("22BCE1234"))
                SecureField("Wi-Fi password", text: $password)
            } footer: {
                Text("The password goes straight into your login Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
        .formStyle(.grouped)
        .frame(width: 400)
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
