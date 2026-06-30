import Foundation
import UglaCore

// Vectors generated from the proven Python impl (login/tuya_client.py) and from
// OpenSSL. If the Swift port drifts from the Python signing, these fail.
func runCryptoChecks(_ h: Harness) {
    h.equal(TuyaCrypto.md5Hex("hello"),
            "5d41402abc4b2a76b9719d911017c592", "md5Hex(hello)")

    h.equal(TuyaCrypto.swap("0123456789abcdeffedcba9876543210"),
            "89abcdef0123456776543210fedcba98", "swap 32-char")
    h.equal(TuyaCrypto.swap("short"), "short", "swap passthrough non-32")

    let params: [String: String] = [
        "a": "x.y.z", "v": "1.0", "time": "1700000000",
        "clientId": TuyaConst.appKey, "deviceId": "dev123", "sid": "",
        "postData": "{\"k\":1}", "requestId": "NOTSIGNED", "junk": "NOPE",
    ]
    h.equal(TuyaCrypto.sign(params, signingKey: TuyaConst.signingKey),
            "b4f1d57438e987190020721ea82de642e9054aacf7a8c78d9b6915e6c8e8a098",
            "sign(fixed params)")

    runRSAChecks(h)
}

private let spkiB64 =
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC8ucy3kyljEgv8xzSrYDd66apwuR5ZLJD+wYLCkZfYeHdHLPY3VZNWKveAUTsSG40JSuQuHQwQ3/1jIYejeTa28K9F8BRSG2262CqI/jXof/5cguidlkTcla6T9fAHX57jfeJTfPtd9NutfkvdIvHwljBPZT6Nv4JPDpM5SgIMPwIDAQAB"
private let pkcs1B64 =
    "MIGJAoGBALy5zLeTKWMSC/zHNKtgN3rpqnC5HlkskP7BgsKRl9h4d0cs9jdVk1Yq94BROxIbjQlK5C4dDBDf/WMhh6N5Nrbwr0XwFFIbbbrYKoj+Neh//lyC6J2WRNyVrpP18AdfnuN94lN8+130261+S90i8fCWME9lPo2/gk8OkzlKAgw/AgMBAAE="

private func runRSAChecks(_ h: Harness) {
    guard let spki = Data(base64Encoded: spkiB64),
          let expectedPKCS1 = Data(base64Encoded: pkcs1B64) else {
        h.check(false, "RSA vectors decode"); return
    }
    do {
        let pkcs1 = try TuyaCrypto.spkiToPKCS1(spki)
        h.equal(pkcs1, expectedPKCS1, "SPKI -> PKCS#1 unwrap")
    } catch {
        h.check(false, "spkiToPKCS1 threw: \(error)")
    }
    // Import + encrypt a 32-byte payload; a 1024-bit key yields 128-byte cipher.
    do {
        let cipher = try TuyaCrypto.rsaEncryptPKCS1(Data(repeating: 7, count: 32),
                                                    pbKeyBase64: spkiB64)
        h.equal(cipher.count, 128, "RSA-1024 PKCS1 cipher length")
    } catch {
        h.check(false, "rsaEncryptPKCS1 threw: \(error)")
    }
}
