import CryptoKit
import Foundation

/// Extra Claude Code config folders (`CLAUDE_CONFIG_DIR` logins) whose official limits are shown
/// next to the default account.
///
/// Folders are detected (`discovered`) and can be completed from Settings (`roots(from:)`), for
/// logins stored outside the detected places. People often set `CLAUDE_CONFIG_DIR` only inside a
/// shell alias, which the app never sees, hence the folder scan.
enum ClaudeAccountRoots {
    static let defaultsKey = "additionalClaudeConfigDirs"

    /// Comma/newline separated, tilde expanded, standardized. Keeps existing directories only,
    /// drops the default roots (they belong to the primary account) and folds duplicates.
    static func roots(
        from raw: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL]
    {
        guard let raw else { return [] }
        let excluded = defaultRootPaths(home: home)
        var seen = Set<String>()
        var out: [URL] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let expanded = trimmed == "~" || trimmed.hasPrefix("~/")
                ? home.path + trimmed.dropFirst()
                : NSString(string: trimmed).expandingTildeInPath
            guard expanded.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !excluded.contains(url.path),
                  seen.insert(url.path).inserted
            else { continue }
            out.append(url)
        }
        return out
    }

    /// Folders found without any setting: the `CLAUDE_CONFIG_DIR` entries the login shell exports,
    /// then the `~/.claude-*` and `~/.claude_*` folders Claude Code is logged in to. Default roots
    /// are never returned, they are the primary account.
    static func discovered(home: URL, configDirValue: String?) -> [URL] {
        let excluded = defaultRootPaths(home: home)
        var seen = Set<String>()
        var out = roots(from: configDirValue, home: home).filter { seen.insert($0.path).inserted }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        for name in names.sorted() where name.hasPrefix(".claude-") || name.hasPrefix(".claude_") {
            let url = home.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            guard !excluded.contains(url.path), hasLogin(url), seen.insert(url.path).inserted else { continue }
            out.append(url)
        }
        return out
    }

    /// The folder holds a `.claude.json` with an `oauthAccount` object, as every config folder
    /// Claude Code is logged in to does. A logged-out or foreign folder is skipped.
    static func hasLogin(_ root: URL) -> Bool {
        savedLogins.login(file: root.appendingPathComponent(".claude.json")) != nil
    }

    /// Email and organization Claude Code saved for this folder's login. Used when the profile
    /// endpoint gives nothing, typically because the token expired. Local read, no network.
    static func savedIdentity(in root: URL) -> AccountIdentity? {
        savedIdentity(file: root.appendingPathComponent(".claude.json"))
    }

    /// Login saved for the default folder (`~/.claude.json`), to name its tab before its limits load.
    /// App only, like `installedDiscovery`: tests must not read the developer's own login.
    static func installedDefaultIdentity(
        isBundledApp: Bool = AppEnv.isBundledApp,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AccountIdentity?
    {
        guard isBundledApp else { return nil }
        return savedIdentity(file: home.appendingPathComponent(".claude.json"))
    }

    static func savedIdentity(file: URL) -> AccountIdentity? {
        savedLogins.login(file: file)?.identity
    }

    /// Organization of this folder's login, to pick the same one among a session key's organizations.
    static func savedOrganizationID(in root: URL) -> String? {
        savedLogins.login(file: root.appendingPathComponent(".claude.json"))?.organizationID
    }

    private struct SavedLogin {
        let identity: AccountIdentity?
        var organizationID: String? = nil
    }

    private static let savedLogins = SavedLoginCache()

    /// `.claude.json` also keeps per-project state and grows with use, while only its `oauthAccount`
    /// matters here: the file is parsed again only when it changed.
    private final class SavedLoginCache: @unchecked Sendable {
        private struct Hit {
            let mtime: Date
            let size: Int
            let login: SavedLogin?
        }

        private let lock = NSLock()
        private var hits: [String: Hit] = [:]

        func login(file: URL) -> SavedLogin? {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate else { return nil }
            let size = values.fileSize ?? 0
            lock.lock()
            let hit = hits[file.path]
            lock.unlock()
            if let hit, hit.mtime == mtime, hit.size == size { return hit.login }
            let login = Self.read(file)
            lock.lock()
            hits[file.path] = Hit(mtime: mtime, size: size, login: login)
            lock.unlock()
            return login
        }

        private static func read(_ file: URL) -> SavedLogin? {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["oauthAccount"] as? [String: Any]
            else { return nil }
            guard let email = account["emailAddress"] as? String, !email.isEmpty else {
                return SavedLogin(identity: nil)
            }
            let org = (account["organizationName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let orgID = (account["organizationUuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return SavedLogin(identity: AccountIdentity(email: email, organizationName: org), organizationID: orgID)
        }
    }

    /// Detection for the running app only. `swift test` and raw `swift build` binaries get nothing:
    /// another login's folder can lead to a Keychain prompt on a manual refresh, which must never
    /// happen inside the test suite (same rule as the other `AppEnv.isBundledApp` guards).
    static func installedDiscovery(
        isBundledApp: Bool = AppEnv.isBundledApp,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configDirValue: () -> String? = { LocalUsageReader.shellAwareClaudeConfigDir() }) -> [URL]
    {
        guard isBundledApp else { return [] }
        return discovered(home: home, configDirValue: configDirValue())
    }

    /// Every additional folder the running app follows, for the usage scan (see `installedDiscovery`).
    static func installedAccountRoots(defaults: UserDefaults = .standard) -> [URL] {
        merged(detected: installedDiscovery(), setting: defaults.string(forKey: defaultsKey))
    }

    /// Detected folders first, then the Settings extras, without duplicates.
    static func merged(detected: [URL], setting: String?,
                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var seen = Set<String>()
        return (detected + roots(from: setting, home: home)).filter { seen.insert($0.path).inserted }
    }

    private static func defaultRootPaths(home: URL) -> Set<String> {
        [
            home.appendingPathComponent(".claude").standardizedFileURL.path,
            home.appendingPathComponent(".config/claude").standardizedFileURL.path,
        ]
    }

    /// Keychain services Claude Code may use for a folder set through `CLAUDE_CONFIG_DIR`:
    /// the default service name plus the first 8 hex characters of the SHA-256 of the variable's
    /// raw value (`/Users/example/.claude-work` → `-dd1118a7`). Claude Code does not normalize that
    /// value (checked with 2.1.274: the same folder with a trailing slash is logged out), so the
    /// folder is also tried the way shell completion writes it, with a trailing slash.
    /// First 8 hex characters of the SHA-256 of the folder path. Also the folder's stable id for
    /// tab selection and alert/candy keys, so no path ends up in the save file.
    static func pathKey(for root: URL) -> String {
        hashPrefix(root.standardizedFileURL.path)
    }

    private static func hashPrefix(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    static func credentialsFileURL(for root: URL) -> URL {
        root.appendingPathComponent(".credentials.json")
    }

    /// The default login's config folder (Claude Code without `CLAUDE_CONFIG_DIR`).
    static func defaultConfigDir(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// When this login last received a prompt: Claude Code appends one line per prompt to the
    /// folder's own `history.jsonl`, which is never shared between logins. Metadata only.
    static func lastPromptDate(configDir: URL) -> Date? {
        let file = configDir.appendingPathComponent("history.jsonl")
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// App only, like `installedDiscovery`: tests must not read the developer's own history.
    static func installedLastPromptDate(configDir: URL, isBundledApp: Bool = AppEnv.isBundledApp) -> Date? {
        isBundledApp ? lastPromptDate(configDir: configDir) : nil
    }
}


struct AccountIdentity: Equatable, Sendable { let email: String; let organizationName: String? }
