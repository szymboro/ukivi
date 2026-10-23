import Foundation

/// Counts of what was converted and why other filters were skipped.
public struct ConversionStats: Sendable {
    public var converted = 0
    public var skipped = 0
    public var reasons: [String: Int] = [:]
    /// Rules left out because the list went over Safari's 150,000 limit.
    public var droppedForLimit = 0

    mutating func skip(_ reason: String) {
        skipped += 1
        reasons[reason, default: 0] += 1
    }
}

/// Converts uBlock Origin / Adblock Plus filter lists into Safari content blocker rules.
///
/// This is a Swift port of Tools/convert_filters.py and produces the same rules
/// (checked by Tools/compare_converters.sh). If you change one, change the other.
///
/// Safari's rules are much simpler than uBlock's, so some filters are skipped:
/// regex filters, scriptlets (##+js), procedural cosmetics (:has-text, :upward, ...),
/// $redirect, $csp, $removeparam and similar.
public enum FilterConverter {
    /// Safari's per-blocker limit (iOS 15+).
    public static let maxRules = 150_000

    /// Generic cosmetic selectors are batched to save rules.
    static let selectorsPerRule = 50

    static let allTypes = ["document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]

    static let typeOptions: [String: [String]] = [
        "script": ["script"],
        "image": ["image"],
        "stylesheet": ["style-sheet"],
        "css": ["style-sheet"],
        "font": ["font"],
        "media": ["media"],
        "xmlhttprequest": ["raw"],
        "xhr": ["raw"],
        "websocket": ["raw"],
        "ping": ["raw"],
        "beacon": ["raw"],
        "other": ["raw"],
        "object": ["raw"],
        "popup": ["popup"],
        "subdocument": ["document"],
        "frame": ["document"],
    ]

    /// Options that change how a rule behaves in ways Safari can't express.
    static let unsupportedOptions: Set<String> = [
        "redirect", "redirect-rule", "rewrite", "csp", "removeparam", "queryprune", "header",
        "permissions", "replace", "denyallow", "to", "method", "strict1p", "strict3p",
        "elemhide", "ehide", "generichide", "ghide", "specifichide", "shide", "genericblock",
        "empty", "mp4", "inline-script", "inline-font", "cname", "urlskip", "uritransform",
        "jsonprune", "network", "content", "webrtc", "ipaddress", "reason",
    ]

    /// Cosmetic syntaxes Safari can't do (procedural, scriptlets, HTML filters, CSS injection).
    static let unsupportedCosmeticSeparators = ["#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#", "#$?#", "#@$?#"]

    static let unsupportedSelectorParts = [
        ":has-text(", ":-abp-", ":contains(", ":upward(", ":xpath(", ":matches-css", ":matches-attr(",
        ":matches-path(", ":matches-prop(", ":min-text-length(", ":watch-attr(", ":remove(", ":remove-attr(",
        ":remove-class(", ":style(", ":others(", ":if(", ":if-not(", ":nth-ancestor(", ":shadow(",
        ":matches-media(", ":spath(",
    ]

    static let separatorClass = "[^a-zA-Z0-9_.%-]"

    // MARK: - Entry point

    /// Converts the given filter list texts into one ordered list of Safari rules.
    public static func convert(_ texts: [String]) -> (rules: [SafariRule], stats: ConversionStats) {
        var stats = ConversionStats()
        var state = State()

        var lines: [String] = []
        for text in texts {
            for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // First pass: $badfilter cancels the filter it names.
        var badfilters = Set<String>()
        for line in lines where line.contains("$") && line.contains("badfilter") {
            guard let dollar = line.lastIndex(of: "$") else { continue }
            let body = line[..<dollar]
            let rest = line[line.index(after: dollar)...]
                .split(separator: ",", omittingEmptySubsequences: false)
                .filter { $0 != "badfilter" }
            badfilters.insert(String(body) + (rest.isEmpty ? "" : "$" + rest.joined(separator: ",")))
        }

        for line in lines {
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") || badfilters.contains(line) {
                continue
            }
            if line.hasPrefix("#") && !["##", "#@#", "#?#", "#$#"].contains(where: line.hasPrefix) {
                continue // hosts-file style comments
            }
            if hasCosmeticSeparator(line) && !(line.hasPrefix("/") || line.hasPrefix("|") || line.hasPrefix("@@")) {
                convertCosmetic(line, into: &state, stats: &stats)
            } else {
                convertNetwork(line, into: &state, stats: &stats)
            }
        }
        let (rules, dropped) = buildRules(&state)
        stats.droppedForLimit = dropped
        return (rules, stats)
    }

    // MARK: - State

    struct State {
        var blocks: [SafariRule] = []
        var important: [SafariRule] = []
        var exceptions: [SafariRule] = []
        var genericSelectors: [String] = []
        var genericWithExclusions: [String: Set<String>] = [:]
        var specificSelectors: [String: [String]] = [:]
        var specificOrder: [String] = []
        var cosmeticExceptions: [String: Set<String>] = [:]
    }

    // MARK: - Network filters

    static func convertNetwork(_ line: String, into state: inout State, stats: inout ConversionStats) {
        let exception = line.hasPrefix("@@")
        let body = exception ? String(line.dropFirst(2)) : line

        var pattern = body
        var options: [Substring] = []
        if !(body.hasPrefix("/") && body.hasSuffix("/")), let start = optionsStart(in: body) {
            pattern = String(body[..<start])
            options = body[body.index(after: start)...].split(separator: ",", omittingEmptySubsequences: false)
        }

        var trigger = SafariRule.Trigger(urlFilter: "")
        var types: [String] = []
        var negatedTypes: [String] = []
        var important = false
        var pageAllowlist = false
        var domains: (include: [String], exclude: [String])?

        for raw in options where !raw.isEmpty {
            let negated = raw.hasPrefix("~")
            let stripped = raw.drop(while: { $0 == "~" })
            let name: String
            let value: Substring
            if let eq = stripped.firstIndex(of: "=") {
                name = stripped[..<eq].lowercased()
                value = stripped[stripped.index(after: eq)...]
            } else {
                name = stripped.lowercased()
                value = ""
            }

            switch name {
            case "third-party", "3p":
                trigger.loadType = [negated ? "first-party" : "third-party"]
            case "first-party", "1p":
                trigger.loadType = [negated ? "third-party" : "first-party"]
            case "domain", "from":
                guard let parsed = parseDomains(value.split(separator: "|", omittingEmptySubsequences: false)) else {
                    return stats.skip("unsupported domain option")
                }
                domains = parsed
            case "match-case":
                trigger.urlFilterIsCaseSensitive = true
            case "important":
                important = true
            case "document", "doc":
                if exception {
                    pageAllowlist = true
                } else {
                    types.append("document")
                }
            case "all":
                break
            case "badfilter":
                return // handled in the first pass
            default:
                if let mapped = typeOptions[name] {
                    if negated {
                        negatedTypes += mapped
                    } else {
                        types += mapped
                        if name == "subdocument" || name == "frame" {
                            trigger.loadContext = ["child-frame"]
                        }
                    }
                } else if unsupportedOptions.contains(name) {
                    return stats.skip("$\(name)")
                } else {
                    return stats.skip("unknown option")
                }
            }
        }

        guard let urlFilter = urlFilter(fromPattern: pattern) else {
            return stats.skip("url pattern")
        }

        let hasConstraint = !(domains?.include.isEmpty ?? true) || pageAllowlist
        if urlFilter == ".*" && !hasConstraint && types.isEmpty {
            return stats.skip("matches everything")
        }

        trigger.urlFilter = urlFilter
        if !types.isEmpty {
            trigger.resourceType = Array(Set(types)).sorted()
        } else if !negatedTypes.isEmpty {
            trigger.resourceType = allTypes.filter { !negatedTypes.contains($0) }
        } else if exception && !pageAllowlist {
            // A plain @@ rule shouldn't switch off cosmetic filtering for the whole page.
            trigger.resourceType = allTypes.filter { $0 != "document" }
        }

        if let domains {
            if !domains.include.isEmpty {
                trigger.ifDomain = domains.include
            } else if !domains.exclude.isEmpty {
                trigger.unlessDomain = domains.exclude
            }
        }

        if pageAllowlist {
            // @@||site.com^$document turns all blocking off on that site.
            var allow = SafariRule.Trigger(urlFilter: ".*")
            if let ifDomain = trigger.ifDomain {
                allow.ifDomain = ifDomain
            } else {
                guard let host = pageAllowlistHost(pattern.lowercased()) else {
                    return stats.skip("page allowlist without domain")
                }
                allow.ifDomain = ["*" + host]
            }
            trigger = allow
        }

        if exception && trigger.loadContext != nil && trigger.resourceType != ["document"] {
            trigger.loadContext = nil
        }

        let rule = SafariRule(trigger: trigger, action: .init(type: exception ? "ignore-previous-rules" : "block"))
        if exception {
            state.exceptions.append(rule)
        } else if important {
            state.important.append(rule)
        } else {
            state.blocks.append(rule)
        }
        stats.converted += 1
    }

    /// Options start at the first "$" followed by an option name, e.g. "$third-party" or "$domain=".
    /// (Option values like $urlskip=/...$/ can contain "$" too.)
    static func optionsStart(in body: String) -> String.Index? {
        var index = body.startIndex
        while let dollar = body[index...].firstIndex(of: "$") {
            var i = body.index(after: dollar)
            if i < body.endIndex && body[i] == "~" { i = body.index(after: i) }
            let nameStart = i
            while i < body.endIndex, let ascii = body[i].asciiValue,
                  isAlphanumeric(ascii) || ascii == UInt8(ascii: "-") {
                i = body.index(after: i)
            }
            if i > nameStart && (i == body.endIndex || body[i] == "=" || body[i] == ",") {
                return dollar
            }
            index = body.index(after: dollar)
        }
        return nil
    }

    /// "||example.com^" -> "example.com"
    static func pageAllowlistHost(_ pattern: String) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        var host = pattern.dropFirst(2)
        if host.hasSuffix("^") { host = host.dropLast() }
        guard !host.isEmpty, host.utf8.allSatisfy({ byte in
            isLowerAlphanumeric(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
        }) else { return nil }
        return String(host)
    }

    // MARK: - URL patterns

    /// Translates an ABP URL pattern into Safari's restricted regex dialect.
    static func urlFilter(fromPattern input: String) -> String? {
        guard input.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        if input.count > 2 && input.hasPrefix("/") && input.hasSuffix("/") {
            return nil // raw regex filters: Safari's regex subset is too different
        }

        var pattern = Substring(input)
        var prefix = ""
        var hostAnchor = false
        if pattern.hasPrefix("||") {
            pattern = pattern.dropFirst(2)
            prefix = #"^[^:]+://+([^:/]+\.)?"#
            hostAnchor = true
        } else if pattern.hasPrefix("|") {
            pattern = pattern.dropFirst()
            prefix = "^"
        }

        var suffix = ""
        if pattern.hasSuffix("|") {
            pattern = pattern.dropLast()
            suffix = "$"
        }

        if prefix.isEmpty { pattern = pattern.drop(while: { $0 == "*" }) }
        if suffix.isEmpty { while pattern.hasSuffix("*") { pattern = pattern.dropLast() } }

        let chars = Array(pattern)
        var out: [String] = []
        var inHost = hostAnchor
        for (i, ch) in chars.enumerated() {
            let last = i == chars.count - 1
            if ch == "/" || ch == "?" { inHost = false }
            switch ch {
            case "*":
                if out.last != ".*" { out.append(".*") }
            case "^":
                if inHost {
                    out.append("[/:]") // a URL always has / or :port after the host
                    inHost = false
                } else if last && suffix.isEmpty {
                    out.append("(\(separatorClass).*)?$") // separator or end of URL
                } else {
                    out.append(separatorClass)
                }
            default:
                out.append(".+?()[]{}\\$|".contains(ch) ? "\\\(ch)" : String(ch))
            }
        }

        let body = out.joined()
        if body.isEmpty && prefix.isEmpty {
            return ".*"
        }
        let result = prefix + body + suffix
        return isSafariRegex(result) ? result : nil
    }

    /// Safari rejects the whole list if a single url-filter is invalid, so be strict.
    static func isSafariRegex(_ regex: String) -> Bool {
        let bytes = Array(regex.utf8)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b >= 0x80 { return false }
            if b == UInt8(ascii: "\\") {
                i += 2
                continue
            }
            if b == UInt8(ascii: "|") || b == UInt8(ascii: "{") || b == UInt8(ascii: "}") {
                return false
            }
            i += 1
        }
        return (try? NSRegularExpression(pattern: regex)) != nil
    }

    // MARK: - Cosmetic filters

    static func convertCosmetic(_ line: String, into state: inout State, stats: inout ConversionStats) {
        if unsupportedCosmeticSeparators.contains(where: { line.contains($0) }) {
            return stats.skip("procedural / scriptlet")
        }
        let exception = line.contains("#@#")
        let separator = exception ? "#@#" : "##"

        let domainsPart: Substring
        let selector: String
        if let range = line.range(of: separator) {
            domainsPart = line[..<range.lowerBound]
            selector = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            domainsPart = Substring(line)
            selector = ""
        }
        guard !selector.isEmpty, selectorIsSupported(selector) else {
            return stats.skip("selector")
        }

        let parsed: (include: [String], exclude: [String])? = domainsPart.isEmpty
            ? (include: [], exclude: [])
            : parseDomains(domainsPart.split(separator: ",", omittingEmptySubsequences: false))
        guard let parsed else {
            return stats.skip("unsupported domain option")
        }
        let (include, exclude) = parsed

        if exception {
            state.cosmeticExceptions[selector, default: []].formUnion(include.isEmpty ? ["*"] : include)
            stats.converted += 1
            return
        }

        if !include.isEmpty {
            if state.specificSelectors[selector] == nil { state.specificOrder.append(selector) }
            state.specificSelectors[selector, default: []] += include
        } else if !exclude.isEmpty {
            state.genericWithExclusions[selector, default: []].formUnion(exclude)
        } else {
            state.genericSelectors.append(selector)
        }
        stats.converted += 1
    }

    static func selectorIsSupported(_ selector: String) -> Bool {
        if unsupportedSelectorParts.contains(where: { selector.contains($0) }) {
            return false
        }
        if selector.hasPrefix("+js(") || selector.hasPrefix("^") || selector.hasPrefix("//") {
            return false
        }
        // Cheap sanity check: brackets, parens and quotes must balance.
        var stack: [Character] = []
        var quote: Character?
        for ch in selector {
            if let q = quote {
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'": quote = ch
            case "(", "[": stack.append(ch)
            case ")": if stack.popLast() != "(" { return false }
            case "]": if stack.popLast() != "[" { return false }
            default: break
            }
        }
        return stack.isEmpty && quote == nil
    }

    /// Matches the regex `#[@?$%]*#`, which marks cosmetic filters.
    static func hasCosmeticSeparator(_ line: String) -> Bool {
        let bytes = Array(line.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "#") {
                var j = i + 1
                scan: while j < bytes.count {
                    switch bytes[j] {
                    case UInt8(ascii: "@"), UInt8(ascii: "?"), UInt8(ascii: "$"), UInt8(ascii: "%"): j += 1
                    default: break scan
                    }
                }
                if j < bytes.count && bytes[j] == UInt8(ascii: "#") { return true }
            }
            i += 1
        }
        return false
    }

    // MARK: - Domains

    /// Splits "a.com", "~b.com" into Safari if-domain / unless-domain lists.
    static func parseDomains<S: StringProtocol>(_ items: [S]) -> (include: [String], exclude: [String])? {
        var include = Set<String>()
        var exclude = Set<String>()
        for raw in items {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { continue }
            let negated = item.hasPrefix("~")
            guard let domain = asciiDomain(String(item.drop(while: { $0 == "~" }))) else {
                return nil
            }
            if negated {
                exclude.insert("*" + domain)
            } else {
                include.insert("*" + domain)
            }
        }
        return (include.sorted(), exclude.sorted())
    }

    static func asciiDomain(_ input: String) -> String? {
        let domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.isEmpty || domain.contains("*") || domain.contains("/") || domain.hasSuffix(".") {
            return nil // entity wildcards (example.*) and regex domains aren't supported
        }
        return IDNA.toASCII(domain)
    }

    // MARK: - Assembling the final list

    static func buildRules(_ state: inout State) -> (rules: [SafariRule], dropped: Int) {
        var cosmetic: [SafariRule] = []
        let exc = state.cosmeticExceptions

        // Generic selectors, batched. Selectors with exceptions get their own rule.
        var seen = Set<String>()
        var batch: [String] = []
        for selector in state.genericSelectors where seen.insert(selector).inserted {
            if let exceptions = exc[selector] {
                if exceptions.contains("*") { continue }
                state.genericWithExclusions[selector, default: []].formUnion(exceptions)
                continue
            }
            batch.append(selector)
        }
        for chunk in chunked(batch, size: selectorsPerRule) {
            cosmetic.append(cssRule(selector: chunk.joined(separator: ", ")))
        }
        for (selector, unless) in state.genericWithExclusions.sorted(by: { $0.key < $1.key }) {
            var rule = cssRule(selector: selector)
            rule.trigger.unlessDomain = unless.sorted()
            cosmetic.append(rule)
        }

        // Site-specific selectors, grouped by identical domain lists.
        var byDomains: [[String]: [String]] = [:]
        for selector in state.specificOrder {
            let exceptions = exc[selector] ?? []
            if exceptions.contains("*") { continue }
            let remaining = Set(state.specificSelectors[selector] ?? []).subtracting(exceptions).sorted()
            if !remaining.isEmpty {
                byDomains[remaining, default: []].append(selector)
            }
        }
        for (domains, selectors) in byDomains.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
            for chunk in chunked(selectors, size: selectorsPerRule) {
                var rule = cssRule(selector: chunk.joined(separator: ", "))
                rule.trigger.ifDomain = domains
                cosmetic.append(rule)
            }
        }

        // Order matters: ignore-previous-rules only cancels rules above it.
        var head = dedupe(state.blocks + cosmetic)
        let tail = dedupe(state.exceptions) + dedupe(state.important)
        let room = max(maxRules - tail.count, 0)
        var dropped = 0
        if head.count > room {
            dropped = head.count - room
            head = Array(head.prefix(room))
        }
        return (head + tail, dropped)
    }

    static func cssRule(selector: String) -> SafariRule {
        SafariRule(trigger: .init(urlFilter: ".*"), action: .init(type: "css-display-none", selector: selector))
    }

    static func dedupe(_ rules: [SafariRule]) -> [SafariRule] {
        var seen = Set<SafariRule>()
        return rules.filter { seen.insert($0).inserted }
    }

    static func chunked<T>(_ items: [T], size: Int) -> [ArraySlice<T>] {
        stride(from: 0, to: items.count, by: size).map { items[$0..<min($0 + size, items.count)] }
    }

    static func isAlphanumeric(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }

    static func isLowerAlphanumeric(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x7A)
    }
}
