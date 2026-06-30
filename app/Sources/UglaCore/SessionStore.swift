import Foundation
import Security

/// Persists the `Session` (sid/ecode/partner/device_id + cameras) in the
/// macOS Keychain as a single JSON generic-password item. Only session tokens
/// live here — never the password. The device id is generated once and reused
/// across re-auth so the account keeps seeing the same "phone".
public enum SessionStore {
    public static let service = "com.simenandre.babymonitor"
    public static let account = "session"

    public enum StoreError: Error { case keychain(OSStatus), encoding }

    public static func load() -> Session? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public static func save(_ session: Session) throws {
        precondition(session.isValid, "refusing to persist an invalid session")
        guard let data = try? JSONEncoder().encode(session) else { throw StoreError.encoding }
        assert(!data.isEmpty, "encoded session is non-empty")
        SecItemDelete(baseQuery() as CFDictionary)  // replace any existing item
        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    public static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    /// A stable per-install phone device id: 20 random bytes as 40 hex chars.
    public static func newDeviceID() -> String {
        var bytes = [UInt8](repeating: 0, count: 20)
        let ok = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(ok == errSecSuccess, "secure RNG must succeed")
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        assert(hex.count == 40, "device id is 40 hex chars")
        return hex
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
