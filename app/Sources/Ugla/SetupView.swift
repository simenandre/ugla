import SwiftUI

/// First-run login UI shown in the popover until a session exists.
struct SetupView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = SetupModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to Baby Monitor+").font(.headline)
            Text("Use your Philips Baby Monitor+ account.")
                .font(.caption).foregroundStyle(.secondary)

            switch model.phase {
            case .credentials, .failed, .working:
                credentialsForm
            case .code:
                codeForm
            case .done:
                Text("Signed in.").foregroundStyle(.secondary)
            }

            if case .failed(let msg) = model.phase {
                Text(msg).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var isWorking: Bool { model.phase == .working }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Email", text: $model.email)
                .textContentType(.username).disableAutocorrection(true)
            SecureField("Password", text: $model.password)
                .textContentType(.password)
            HStack {
                Text("Country code").font(.caption).foregroundStyle(.secondary)
                TextField("47", text: $model.country).frame(width: 50)
            }
            Button(isWorking ? "Working…" : "Send code") { model.sendCode(into: appState) }
                .disabled(isWorking)
                .keyboardShortcut(.defaultAction)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var codeForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enter the 6-digit code emailed to you.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("123456", text: $model.code)
                .textFieldStyle(.roundedBorder)
            Button("Sign in") { model.verify(into: appState) }
                .keyboardShortcut(.defaultAction)
        }
    }
}
