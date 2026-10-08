import Foundation

/// Application Support state directory for TokenTown files.
/// `PTB_STATE_DIR` overrides the default for development/QA isolation.
enum AppStatePaths {
    /// TokenTown's QA override is state storage, not a usage-log location.
    static func cityDirectory() -> URL {
        let override = (ProcessInfo.processInfo.environment["TOKENTOWN_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenTown", isDirectory: true)
    }

    static func directory() -> URL {
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir: URL
        if !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TokenTown")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
