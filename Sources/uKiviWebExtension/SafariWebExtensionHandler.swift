import Foundation
import SafariServices
import uKiviShared

/// Receives messages from the web extension's JavaScript (browser.runtime.sendNativeMessage)
/// so the popup can read and change the shared allowlist.
///
/// Messages:
///   { "type": "getGlobal" } -> { "blockingPaused": Bool }   (main switch in the app)
///   { "type": "getSite", "host": "example.com" } -> { "paused": Bool, "blockingPaused": Bool }
///   { "type": "setPaused", "host": "example.com", "paused": Bool } -> { "paused": Bool, "applied": Bool }
///
/// The @objc name must match NSExtensionPrincipalClass in Support/uKiviWebExtension-Info.plist.
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        Task {
            let reply = await Self.handle(message)
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func handle(_ message: [String: Any]) async -> [String: Any] {
        let type = message["type"] as? String
        if type == "getGlobal" {
            return ["blockingPaused": SharedSettings.blockingPaused]
        }
        guard let host = message["host"] as? String,
              let domain = SharedSettings.normalizeDomain(host) else {
            return ["error": "Missing or invalid host"]
        }

        switch type {
        case "getSite":
            return ["paused": SharedSettings.isAllowlisted(domain), "blockingPaused": SharedSettings.blockingPaused]

        case "setPaused":
            let paused = message["paused"] as? Bool ?? false
            var list = SharedSettings.allowlist
            if paused {
                list.append(domain)
            } else {
                // Also remove parent domains, otherwise the site would stay paused.
                list.removeAll { domain == $0 || domain.hasSuffix("." + $0) }
            }
            SharedSettings.allowlist = list

            // Try to apply right away. If Safari refuses to let an extension reload
            // the blockers, needsReload stays set and the app does it on next launch.
            let errors = await BlockerManager.reloadAll()
            return ["paused": paused, "applied": errors.isEmpty]

        default:
            return ["error": "Unknown message type"]
        }
    }
}
