import Foundation
import BabyMonitorCore

// Self-tests for BabyMonitorCore. Run with: swift run SelfTest
// More checks (TuyaCrypto vectors, discovery parsing) are added per phase.

let h = Harness()

// Camera round-trips through Codable unchanged.
do {
    let cam = Camera(id: "bf457e", name: "Herman", category: "sp")
    let data = try JSONEncoder().encode(cam)
    let back = try JSONDecoder().decode(Camera.self, from: data)
    h.equal(back, cam, "Camera Codable round-trip")
} catch {
    h.check(false, "Camera Codable round-trip threw: \(error)")
}

// Session validity reflects required fields.
do {
    let full = Session(sid: "s", ecode: "e", partner: "p", deviceID: "d", cameras: [])
    h.check(full.isValid, "Session.isValid true when complete")
    let empty = Session(sid: "", ecode: "e", partner: "p", deviceID: "d", cameras: [])
    h.check(!empty.isValid, "Session.isValid false when sid missing")

    let data = try JSONEncoder().encode(full)
    let back = try JSONDecoder().decode(Session.self, from: data)
    h.equal(back, full, "Session Codable round-trip")
} catch {
    h.check(false, "Session Codable round-trip threw: \(error)")
}

runCryptoChecks(h)

h.finish()
