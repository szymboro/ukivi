import Foundation

/// Hands Safari the rules for one content blocker.
///
/// Safari calls this when the user enables the blocker or the app asks for a reload.
/// The rules JSON (downloaded or bundled) is passed through as-is, plus one extra rule at the end that
/// switches blocking off on allowlisted sites.
public enum ContentBlockerResponder {
    public static func respond(to context: NSExtensionContext, blocker: Blocker) {
        let item = NSExtensionItem()
        if let url = rulesURL(for: blocker), let provider = NSItemProvider(contentsOf: url) {
            item.attachments = [provider]
        }
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }

    static func rulesURL(for blocker: Blocker) -> URL? {
        if SharedSettings.blockingPaused {
            return pausedRulesURL()
        }
        guard let bundled = RulesStore.currentRulesURL(for: blocker) else {
            return nil
        }
        let allowlist = SharedSettings.allowlist
        guard !allowlist.isEmpty else { return bundled }

        do {
            // Splice the allowlist rule in before the closing "]" instead of parsing
            // the whole file: the lists are several MB and extensions have little memory.
            let data = try Data(contentsOf: bundled, options: .mappedIfSafe)
            guard let close = data.lastIndex(of: UInt8(ascii: "]")) else { return bundled }
            let hasRules = data.firstIndex(of: UInt8(ascii: "{")) != nil

            var combined = Data(data[..<close])
            if hasRules { combined.append(UInt8(ascii: ",")) }
            combined.append(try allowlistRule(allowlist))
            combined.append(UInt8(ascii: "]"))

            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(blocker.rulesFileName)-with-allowlist.json")
            try combined.write(to: output, options: .atomic)
            return output
        } catch {
            return bundled
        }
    }

    /// Safari won't accept an empty list, so "off" is one rule that can never match.
    static func pausedRulesURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paused-rules.json")
        let json = #"[{"trigger":{"url-filter":"^ukivi-paused:"},"action":{"type":"block"}}]"#
        do {
            try Data(json.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// `ignore-previous-rules` cancels every rule above it for pages on these domains.
    static func allowlistRule(_ domains: [String]) throws -> Data {
        let rule: [String: Any] = [
            "trigger": [
                "url-filter": ".*",
                "if-domain": domains.map { "*" + $0 },
            ],
            "action": ["type": "ignore-previous-rules"],
        ]
        return try JSONSerialization.data(withJSONObject: rule)
    }
}
