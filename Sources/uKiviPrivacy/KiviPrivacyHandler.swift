import Foundation
import uKiviShared

/// Entry point Safari calls to get this blocker's rules.
/// The @objc name must match NSExtensionPrincipalClass in Support/uKiviPrivacy-Info.plist.
@objc(KiviPrivacyHandler)
final class KiviPrivacyHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        ContentBlockerResponder.respond(to: context, blocker: .privacy)
    }
}
