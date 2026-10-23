import Foundation

/// Settings shared by the app and its extensions through the App Group.
public enum SharedSettings {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupID) ?? .standard
    }

    /// Sites where nothing is blocked (domains like "example.com", subdomains included).
    public static var allowlist: [String] {
        get { defaults.stringArray(forKey: "allowlist") ?? [] }
        set { defaults.set(Array(Set(newValue)).sorted(), forKey: "allowlist") }
    }

    /// Set when the allowlist changed but the content blockers couldn't be reloaded
    /// (for example from the web extension). The app reloads them next time it opens.
    public static var needsReload: Bool {
        get { defaults.bool(forKey: "needsReload") }
        set { defaults.set(newValue, forKey: "needsReload") }
    }

    /// The main switch. When true, the content blockers hand Safari an empty rule list.
    public static var blockingPaused: Bool {
        get { defaults.bool(forKey: "blockingPaused") }
        set { defaults.set(newValue, forKey: "blockingPaused") }
    }

    /// Extra filter list URLs the user added (uBlock / AdBlock Plus syntax).
    public static var customListURLs: [String] {
        get { defaults.stringArray(forKey: "customListURLs") ?? [] }
        set { defaults.set(newValue, forKey: "customListURLs") }
    }

    /// The user's own filters, one per line, e.g. "||ads.example.com^" or "example.com##.banner".
    public static var customFilters: String {
        get { defaults.string(forKey: "customFilters") ?? "" }
        set { defaults.set(newValue, forKey: "customFilters") }
    }

    /// When the filter lists were last downloaded on the phone (nil = still using bundled rules).
    public static var lastFilterUpdate: Date? {
        get { defaults.object(forKey: "lastFilterUpdate") as? Date }
        set { defaults.set(newValue, forKey: "lastFilterUpdate") }
    }

    /// Rule counts from the last on-device update, keyed by blocker ("ads", "privacy").
    public static var ruleCounts: [String: Int] {
        get { defaults.dictionary(forKey: "ruleCounts") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "ruleCounts") }
    }

    public static func isAllowlisted(_ host: String) -> Bool {
        guard let domain = normalizeDomain(host) else { return false }
        return allowlist.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    /// Turns user input ("https://www.Example.com/page") into a bare domain ("example.com").
    /// Returns nil if it doesn't look like a domain. Non-ASCII domains must be entered in
    /// punycode form, because Safari's rules only accept ASCII.
    public static func normalizeDomain(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") {
            text = String(text[range.upperBound...])
        }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        if text.hasPrefix("www.") {
            text.removeFirst(4)
        }
        let pattern = #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return text
    }
}
