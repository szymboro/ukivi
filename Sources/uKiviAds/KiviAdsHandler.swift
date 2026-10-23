import Foundation
import uKiviShared

/// Entry point Safari calls to get this blocker's rules.
/// The @objc name must match NSExtensionPrincipalClass in Support/uKiviAds-Info.plist.
@objc(KiviAdsHandler)
final class KiviAdsHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        ContentBlockerResponder.respond(to: context, blocker: .ads)
    }
}
