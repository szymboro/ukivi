import Foundation

/// Where each blocker's rules live.
///
/// The app downloads fresh rules into the App Group container (shared with the
/// extensions). Until the first update, the extensions use the rules bundled with them.
public enum RulesStore {
    public static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID)?
            .appendingPathComponent("Rules", isDirectory: true)
    }

    public static func downloadedRulesURL(for blocker: Blocker) -> URL? {
        directory?.appendingPathComponent("\(blocker.rulesFileName).json")
    }

    /// The rules a content blocker should hand Safari: downloaded if present, otherwise bundled.
    public static func currentRulesURL(for blocker: Blocker) -> URL? {
        if let downloaded = downloadedRulesURL(for: blocker),
           FileManager.default.fileExists(atPath: downloaded.path) {
            return downloaded
        }
        return Bundle.main.url(forResource: blocker.rulesFileName, withExtension: "json")
    }
}
