import Foundation

/// An error returned by the Tuya API (`success: false`).
public struct TuyaError: Error, Equatable {
    public let code: String
    public let message: String
    /// The first login attempt is expected to fail with this — it means "we
    /// emailed (or will email) a 6-digit code; call login again with it".
    public var needsMFA: Bool { code.contains("MFA") || code.contains("CODE") }
    public var isBadAuth: Bool { code.contains("PASSWD") }
}

/// A thin failure for malformed responses (programming/transport errors).
public enum TuyaClientError: Error { case badResponse, badJSON, encodingFailed }

/// Tuya Mobile SDK API client: signs requests, logs in (password + email MFA),
/// and discovers cameras. Ported from `login/tuya_client.py`. Holds the session
/// id as mutable state (identity), so it is a class.
public final class TuyaClient {
    private let deviceID: String
    private var sid: String
    private let session: URLSession

    public init(deviceID: String, sid: String = "", session: URLSession = .shared) {
        precondition(!deviceID.isEmpty, "deviceID required")
        self.deviceID = deviceID
        self.sid = sid
        self.session = session
    }

    public var currentSID: String { sid }

    // MARK: Request building

    private func buildParams(_ action: String, _ version: String, postData: String?) -> [String: String] {
        precondition(!action.isEmpty, "action required")
        var p: [String: String] = [
            "a": action, "v": version,
            "time": String(Int(Date().timeIntervalSince1970)),
            "appVersion": "1.8.0", "appRnVersion": "5.92", "channel": "oem",
            "chKey": TuyaConst.chKey, "clientId": TuyaConst.appKey, "cp": "gzip",
            "deviceCoreVersion": "6.7.0", "deviceId": deviceID, "et": "0.0.1",
            "nd": "1", "lang": "en_US", "os": "Android", "osSystem": "14",
            "platform": "tuya_client", "requestId": UUID().uuidString,
            "sdkVersion": "6.7.0", "sid": sid, "timeZoneId": "Europe/Oslo",
            "ttid": "sdk_international@\(TuyaConst.appKey)",
        ]
        if let postData { p["postData"] = postData }
        p["sign"] = TuyaCrypto.sign(p, signingKey: TuyaConst.signingKey)
        assert(p["sign"]?.count == 64, "sign is 64 hex chars")
        return p
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let s = String(data: data, encoding: .utf8) else { throw TuyaClientError.encodingFailed }
        return s
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    // MARK: Core call

    /// Make one signed API call and return the `result` field (dict or array).
    /// `extra` params are appended after signing (e.g. `gid`, not in whitelist).
    @discardableResult
    func call(_ action: String, _ version: String = "1.0",
              post: [String: Any]? = nil, extra: [String: String]? = nil) async throws -> Any {
        var postString: String?
        if let post { postString = try Self.jsonString(post) }
        var params = buildParams(action, version, postData: postString)
        if let extra { params.merge(extra) { _, new in new } }

        var req = URLRequest(url: TuyaConst.apiURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Thing-UA=APP/Android/1.8.0/SDK/6.7.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = Self.formEncode(params)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TuyaClientError.badResponse
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaClientError.badJSON
        }
        if (root["success"] as? Bool) != true {
            throw TuyaError(code: str(root["errorCode"]) ?? "UNKNOWN",
                            message: str(root["errorMsg"]) ?? "Unknown error")
        }
        guard let result = root["result"] else { return [:] as [String: Any] }
        return result
    }

    // MARK: Authentication

    private func rsaToken(email: String, country: String) async throws -> (pbKey: String, token: String) {
        let result = try await call("thing.m.user.username.token.get", "2.0",
            post: ["countryCode": country, "username": email, "isUid": false])
        guard let dict = result as? [String: Any],
              let pbKey = str(dict["pbKey"]), let token = str(dict["token"]) else {
            throw TuyaClientError.badJSON
        }
        return (pbKey, token)
    }

    /// Password (+ optional MFA) login. Throws `TuyaError` with `needsMFA` when
    /// called with an empty code. On success, stores the session and returns the
    /// (sid, ecode, partner) triple the bridge needs.
    @discardableResult
    public func login(_ creds: Credentials, mfaCode: String) async throws
        -> (sid: String, ecode: String, partner: String) {
        precondition(!creds.email.isEmpty && !creds.password.isEmpty, "credentials required")
        let token = try await rsaToken(email: creds.email, country: creds.countryCode)
        let encrypted = try TuyaCrypto.encryptPassword(creds.password, pbKeyBase64: token.pbKey)
        let options = try Self.jsonString(["group": 1, "mfaCode": mfaCode])
        sid = ""  // login is unauthenticated
        let result = try await call("thing.m.user.email.password.login", "3.0", post: [
            "countryCode": creds.countryCode, "email": creds.email, "passwd": encrypted,
            "token": token.token, "ifencrypt": 1, "options": options,
        ])
        guard let dict = result as? [String: Any], let newSID = str(dict["sid"]) else {
            throw TuyaClientError.badJSON
        }
        sid = newSID
        assert(!sid.isEmpty, "sid set after login")
        return (newSID, str(dict["ecode"]) ?? "", str(dict["partnerIdentity"]) ?? "")
    }

    /// Ask Tuya to email a 6-digit MFA code.
    public func triggerMFA(_ creds: Credentials) async throws {
        precondition(!creds.email.isEmpty, "email required")
        let token = try await rsaToken(email: creds.email, country: creds.countryCode)
        let encrypted = try TuyaCrypto.encryptPassword(creds.password, pbKeyBase64: token.pbKey)
        let options = try Self.jsonString(["group": 1, "mfaCode": "null"])
        sid = ""
        try await call("thing.m.user.username.mfa.code.get", "1.0", post: [
            "countryCode": creds.countryCode, "username": creds.email, "passwd": encrypted,
            "token": token.token, "ifencrypt": 1, "options": options,
        ])
    }

    // MARK: helpers

    func str(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}
