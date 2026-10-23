import Foundation

/// One Safari content blocker extension. Each holds one group of filter lists.
public enum Blocker: String, CaseIterable, Identifiable, Sendable {
    case ads
    case privacy

    public var id: String { rawValue }

    /// SwiftPM product name, which xtool also uses as the last part of the bundle ID.
    public var productName: String {
        switch self {
        case .ads: "uKiviAds"
        case .privacy: "uKiviPrivacy"
        }
    }

    public var title: String {
        switch self {
        case .ads: "Ads"
        case .privacy: "Trackers"
        }
    }

    public var summary: String {
        switch self {
        case .ads: "Ads, pop-ups and cookie banners"
        case .privacy: "Analytics and tracking scripts"
        }
    }

    public var symbol: String {
        switch self {
        case .ads: "rectangle.slash"
        case .privacy: "eye.slash"
        }
    }

    /// Name of the rules file bundled inside the extension (`ads.json`, ...).
    public var rulesFileName: String { rawValue }
}

/// Works out bundle and App Group IDs at runtime.
///
/// xtool prefixes IDs with your team ID when signing (com.you.ukivi becomes
/// XTL-ABCD.com.you.ukivi), so nothing is hardcoded here.
public enum AppIdentity {
    /// The containing app's bundle ID, whether we're running in the app or an extension.
    public static var appBundleID: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard Bundle.main.bundlePath.hasSuffix(".appex") else { return id }
        return id.split(separator: ".").dropLast().joined(separator: ".")
    }

    public static var appGroupID: String { "group." + appBundleID }

    public static func extensionID(for blocker: Blocker) -> String {
        appBundleID + "." + blocker.productName
    }
}
