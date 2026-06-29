import SwiftUI
import BabyMonitorCore

/// Drives the first-run login: password → email MFA code → discover cameras →
/// persist session. Owns a TuyaClient for the duration of the flow. UI state is
/// the `phase`; the actual networking lives in `BabyMonitorCore`.
@MainActor
final class SetupModel: ObservableObject {
    enum Phase: Equatable { case credentials, code, working, done, failed(String) }

    @Published var email = ""
    @Published var password = ""
    @Published var country = TuyaConst.defaultCountryCode
    @Published var code = ""
    @Published private(set) var phase: Phase = .credentials

    private let deviceID: String
    private var client: TuyaClient?
    private var creds: Credentials?

    init() {
        // Reuse the existing install's device id across re-auth if we have one.
        deviceID = SessionStore.load()?.deviceID ?? SessionStore.newDeviceID()
    }

    /// Step 1: validate credentials and request the emailed MFA code.
    func sendCode(into appState: AppState) {
        let creds = Credentials(email: email.trimmingCharacters(in: .whitespaces),
                                password: password, countryCode: country)
        guard !creds.email.isEmpty, !creds.password.isEmpty else {
            phase = .failed("Email and password are required"); return
        }
        self.creds = creds
        let client = TuyaClient(deviceID: deviceID)
        self.client = client
        phase = .working
        Task { await requestCode(client: client, creds: creds, appState: appState) }
    }

    private func requestCode(client: TuyaClient, creds: Credentials, appState: AppState) async {
        do {
            let auth = try await client.login(creds, mfaCode: "")  // usually throws needsMFA
            await complete(auth: auth, client: client, appState: appState)  // rare: no MFA
        } catch let e as TuyaError where e.needsMFA {
            do { try await client.triggerMFA(creds); phase = .code }
            catch { phase = .failed(message(for: error)) }
        } catch let e as TuyaError where e.isBadAuth {
            phase = .failed("Wrong email or password")
        } catch {
            phase = .failed(message(for: error))
        }
    }

    /// Step 2: submit the 6-digit code, then discover + persist.
    func verify(into appState: AppState) {
        guard let client, let creds else { phase = .failed("Please start over"); return }
        guard code.trimmingCharacters(in: .whitespaces).count >= 4 else {
            phase = .failed("Enter the 6-digit code"); return
        }
        phase = .working
        Task {
            do {
                let auth = try await client.login(creds, mfaCode: code.trimmingCharacters(in: .whitespaces))
                await complete(auth: auth, client: client, appState: appState)
            } catch {
                phase = .failed(message(for: error))
            }
        }
    }

    private func complete(auth: (sid: String, ecode: String, partner: String),
                          client: TuyaClient, appState: AppState) async {
        do {
            let cameras = try await client.discoverDevices()
            let session = Session(sid: auth.sid, ecode: auth.ecode, partner: auth.partner,
                                  deviceID: deviceID, cameras: cameras)
            try SessionStore.save(session)
            appState.markConfigured()
            appState.setCameras(cameras)
            phase = .done
        } catch {
            phase = .failed(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        if let e = error as? TuyaError { return "\(e.message) (\(e.code))" }
        return "Something went wrong. Please try again."
    }
}
