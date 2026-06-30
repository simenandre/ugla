import Foundation

/// Finds the bundled helper executables (the Go bridge and ffmpeg) at runtime.
/// In a packaged app they live in `Contents/Resources/Helpers`; during
/// development `BABYMON_HELPERS_DIR` (set by `scripts/build-helpers.sh` output)
/// points at `app/helpers`.
public enum HelperLocator {
    public enum Helper: String, CaseIterable {
        case bridge = "avent-webrtc-bridge"
        case ffmpeg = "ffmpeg"
    }

    public enum LocatorError: Error { case notFound(Helper) }

    /// Resolve a helper or throw if it is missing/non-executable.
    public static func require(_ helper: Helper, bundle: Bundle = .main) throws -> URL {
        if let url = url(for: helper, bundle: bundle) { return url }
        throw LocatorError.notFound(helper)
    }

    public static func url(for helper: Helper, bundle: Bundle = .main) -> URL? {
        let fm = FileManager.default
        // 1. Explicit dev override.
        if let dir = ProcessInfo.processInfo.environment["BABYMON_HELPERS_DIR"] {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(helper.rawValue)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        // 2. Inside the app bundle.
        if let resources = bundle.resourceURL {
            let candidate = resources.appendingPathComponent("Helpers")
                .appendingPathComponent(helper.rawValue)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
