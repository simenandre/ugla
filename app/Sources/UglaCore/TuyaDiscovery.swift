import Foundation

/// Camera discovery on the Mobile SDK path. Ported from
/// `discover_devices` in `login/tuya_client.py`: enumerate homes, then per home
/// try rooms → group list, with a flat list as fallback. Cameras report
/// category "sp"; if that filter yields nothing we return everything found.
extension TuyaClient {
    private static let maxItems = 256  // hard cap per list (Power of Ten: bounded)

    public func discoverDevices() async throws -> [Camera] {
        precondition(!currentSID.isEmpty, "must be logged in before discovery")
        var seen = Set<String>()
        var all: [Camera] = []

        let homes = (try? await getHomes()) ?? []
        for home in homes.prefix(Self.maxItems) {
            guard let gid = str(home["gid"]) else { continue }
            for cam in try await devices(inHome: gid) where !seen.contains(cam.id) {
                seen.insert(cam.id)
                all.append(cam)
            }
        }
        if all.isEmpty { all = try await flatDeviceList(seen: &seen) }

        let cameras = all.filter { $0.category == "sp" }
        assert(cameras.count <= all.count, "filter cannot grow the set")
        return cameras.isEmpty ? all : cameras
    }

    private func getHomes() async throws -> [[String: Any]] {
        let result = try await call("m.life.home.space.list")
        return (result as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private func devices(inHome gid: String) async throws -> [Camera] {
        precondition(!gid.isEmpty, "gid required")
        // Strategy 1: rooms -> deviceList (API v2.0, then v1.0).
        for version in ["2.0", "1.0"] {
            let rooms = try? await call("tuya.m.location.get", version,
                                        post: ["gid": gid], extra: ["gid": gid])
            let cams = camerasFromRooms(rooms)
            if !cams.isEmpty { return cams }
        }
        // Strategy 2: group device list.
        let group = try? await call("tuya.m.my.group.device.list", extra: ["gid": gid])
        if let arr = group as? [Any] {
            return arr.prefix(Self.maxItems).compactMap { ($0 as? [String: Any]).flatMap(deviceToCamera) }
        }
        return []
    }

    private func camerasFromRooms(_ rooms: Any?) -> [Camera] {
        guard let roomArray = rooms as? [Any] else { return [] }
        var cams: [Camera] = []
        for entry in roomArray.prefix(Self.maxItems) {
            guard let room = entry as? [String: Any],
                  let list = room["deviceList"] as? [Any] else { continue }
            for dev in list.prefix(Self.maxItems) {
                if let d = dev as? [String: Any], let cam = deviceToCamera(d) { cams.append(cam) }
            }
        }
        return cams
    }

    private func flatDeviceList(seen: inout Set<String>) async throws -> [Camera] {
        let result = try? await call("tuya.m.device.list.get")
        guard let arr = result as? [Any] else { return [] }
        var cams: [Camera] = []
        for item in arr.prefix(Self.maxItems) {
            guard let d = item as? [String: Any], let cam = deviceToCamera(d),
                  !seen.contains(cam.id) else { continue }
            seen.insert(cam.id)
            cams.append(cam)
        }
        return cams
    }

    private func deviceToCamera(_ d: [String: Any]) -> Camera? {
        guard let id = str(d["devId"]) ?? str(d["deviceId"]) ?? str(d["id"]),
              !id.isEmpty else { return nil }
        let name = str(d["name"]) ?? str(d["deviceName"]) ?? "Camera"
        return Camera(id: id, name: name, category: str(d["category"]) ?? "")
    }
}
