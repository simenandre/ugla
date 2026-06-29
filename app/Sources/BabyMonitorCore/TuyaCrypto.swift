import Foundation
import CryptoKit
import Security

/// Pure cryptographic helpers for the Tuya Mobile SDK API. Ported from
/// `login/tuya_client.py` (`_sign`, `_swap`, `_encrypt_password`). No state, no
/// I/O — each function maps inputs to outputs and is validated by SelfTest
/// against vectors generated from the Python implementation and OpenSSL.
public enum TuyaCrypto {

    /// Request params that participate in the HMAC signature. Anything else
    /// (e.g. `gid`) may be sent but is not signed. Matches the Python whitelist.
    static let signWhitelist: Set<String> = [
        "a", "v", "lat", "lon", "lang", "deviceId", "appVersion", "ttid",
        "isH5", "h5Token", "os", "clientId", "postData", "time", "requestId",
        "et", "n4h5", "sid", "chKey", "sp",
    ]

    /// Lowercase hex MD5 of a UTF-8 string.
    public static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Rearrange the four 8-char blocks of a 32-char hex string:
    /// [A][B][C][D] -> [B][A][D][C]. Non-32-char input is returned unchanged
    /// (matches Python behaviour).
    public static func swap(_ input: String) -> String {
        guard input.count == 32 else { return input }
        let c = Array(input)
        assert(c.count == 32, "swap precondition: 32 chars")
        let block = { (lo: Int) in String(c[lo ..< lo + 8]) }
        return block(8) + block(0) + block(24) + block(16)
    }

    /// HMAC-SHA256 signature over the whitelisted, sorted params, joined by
    /// `||`. `postData` is replaced by `swap(md5(postData))` before signing.
    public static func sign(_ params: [String: String], signingKey: String) -> String {
        precondition(!signingKey.isEmpty, "signing key required")
        var filtered = params.filter { signWhitelist.contains($0.key) && !$0.value.isEmpty }
        if let post = filtered["postData"], !post.isEmpty {
            filtered["postData"] = swap(md5Hex(post))
        }
        assert(filtered.values.allSatisfy { !$0.isEmpty }, "no empty signed values")
        let message = filtered.keys.sorted()
            .compactMap { key in filtered[key].map { "\(key)=\($0)" } }
            .joined(separator: "||")
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8), using: SymmetricKey(data: Data(signingKey.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public enum CryptoError: Error, Equatable {
        case malformedSPKI
        case keyImportFailed
        case algorithmUnsupported
        case encryptFailed
    }

    /// RSA/PKCS1v1.5-encrypt `message` with a Tuya `pbKey` (base64 SubjectPublic
    /// KeyInfo DER, as returned by the token endpoint). Returns the ciphertext.
    public static func rsaEncryptPKCS1(_ message: Data, pbKeyBase64: String) throws -> Data {
        precondition(!pbKeyBase64.isEmpty, "pbKey required")
        guard let spki = Data(base64Encoded: pbKeyBase64) else { throw CryptoError.malformedSPKI }
        let pkcs1 = try spkiToPKCS1(spki)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &err) else {
            throw CryptoError.keyImportFailed
        }
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
            throw CryptoError.algorithmUnsupported
        }
        guard let cipher = SecKeyCreateEncryptedData(
            key, .rsaEncryptionPKCS1, message as CFData, &err) else {
            throw CryptoError.encryptFailed
        }
        return cipher as Data
    }

    /// Encrypt a password the way the app does: RSA(md5hex(password)) -> hex.
    public static func encryptPassword(_ password: String, pbKeyBase64: String) throws -> String {
        precondition(!password.isEmpty, "password required")
        let payload = Data(md5Hex(password).utf8)
        assert(payload.count == 32, "md5 hex is 32 bytes")
        let cipher = try rsaEncryptPKCS1(payload, pbKeyBase64: pbKeyBase64)
        return cipher.map { String(format: "%02x", $0) }.joined()
    }

    /// Extract the PKCS#1 `RSAPublicKey` DER from a SubjectPublicKeyInfo DER.
    /// SecKey on Apple platforms imports PKCS#1 for RSA, not SPKI, so we unwrap:
    /// SPKI = SEQUENCE { AlgorithmIdentifier, BIT STRING { RSAPublicKey } }.
    public static func spkiToPKCS1(_ spki: Data) throws -> Data {
        let bytes = [UInt8](spki)
        var i = 0
        guard try readTag(bytes, &i) == 0x30 else { throw CryptoError.malformedSPKI } // outer SEQ
        _ = try readLength(bytes, &i)
        guard try readTag(bytes, &i) == 0x30 else { throw CryptoError.malformedSPKI } // AlgId SEQ
        let algLen = try readLength(bytes, &i)
        i += algLen                                                                    // skip AlgId
        guard i <= bytes.count, try readTag(bytes, &i) == 0x03 else {                   // BIT STRING
            throw CryptoError.malformedSPKI
        }
        let bitLen = try readLength(bytes, &i)
        guard bitLen >= 1, i < bytes.count, bytes[i] == 0x00 else { throw CryptoError.malformedSPKI }
        i += 1                                                                          // unused-bits byte
        let end = i + (bitLen - 1)
        guard end <= bytes.count else { throw CryptoError.malformedSPKI }
        return Data(bytes[i ..< end])
    }

    private static func readTag(_ b: [UInt8], _ i: inout Int) throws -> UInt8 {
        guard i < b.count else { throw CryptoError.malformedSPKI }
        let t = b[i]; i += 1
        return t
    }

    /// DER definite-length. Bounded: a length spans at most 1 + 4 bytes.
    private static func readLength(_ b: [UInt8], _ i: inout Int) throws -> Int {
        guard i < b.count else { throw CryptoError.malformedSPKI }
        let first = b[i]; i += 1
        if first < 0x80 { return Int(first) }
        let count = Int(first & 0x7f)
        guard count >= 1, count <= 4, i + count <= b.count else { throw CryptoError.malformedSPKI }
        var len = 0
        for _ in 0 ..< count {       // bounded by count (<= 4)
            len = (len << 8) | Int(b[i]); i += 1
        }
        return len
    }
}
