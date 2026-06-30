import Foundation

/// A camera (one child's monitor) on the account. Immutable value.
public struct Camera: Identifiable, Equatable, Codable {
    public let id: String       // Tuya device id (devId)
    public let name: String     // display name, e.g. "Herman"
    public let category: String // Tuya category; "sp" for smart cameras

    public init(id: String, name: String, category: String) {
        self.id = id
        self.name = name
        self.category = category
    }
}

/// A zoom region for the stream, used to bake digital zoom into the transcoded
/// video so it carries into the (system-rendered) PiP window. `px`/`py` are the
/// normalized pan position of the crop window (0…1; 0.5 = centered).
public struct CropRegion: Equatable {
    public let zoom: Double
    public let px: Double
    public let py: Double

    public init(zoom: Double, px: Double, py: Double) {
        precondition(zoom >= 1, "zoom must be >= 1")
        self.zoom = zoom
        self.px = min(1, max(0, px))
        self.py = min(1, max(0, py))
    }
}

/// User-entered login inputs. Held only transiently during setup; never stored.
public struct Credentials: Equatable {
    public let email: String
    public let password: String
    public let countryCode: String  // e.g. "47" (Norway)

    public init(email: String, password: String, countryCode: String) {
        self.email = email
        self.password = password
        self.countryCode = countryCode
    }
}

/// A persisted Tuya Mobile SDK session plus the discovered cameras. This is what
/// the bridge needs (sid/ecode/partner/device_id) to stream. Stored in Keychain.
/// The static app keys (signing key, app key, package) live in `TuyaConst`, not
/// here, since they are not secret and not user-specific.
public struct Session: Equatable, Codable {
    public let sid: String
    public let ecode: String
    public let partner: String
    public let deviceID: String     // stable per install; reused across re-auth
    public let cameras: [Camera]

    public init(sid: String, ecode: String, partner: String, deviceID: String, cameras: [Camera]) {
        self.sid = sid
        self.ecode = ecode
        self.partner = partner
        self.deviceID = deviceID
        self.cameras = cameras
    }

    public var isValid: Bool { !sid.isEmpty && !ecode.isEmpty && !deviceID.isEmpty }
}
