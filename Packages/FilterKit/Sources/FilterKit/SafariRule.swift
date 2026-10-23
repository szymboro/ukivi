import Foundation

/// One rule in Safari's content blocker JSON format.
public struct SafariRule: Codable, Hashable, Sendable {
    public struct Trigger: Codable, Hashable, Sendable {
        public var urlFilter: String
        public var urlFilterIsCaseSensitive: Bool?
        public var resourceType: [String]?
        public var loadType: [String]?
        public var loadContext: [String]?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?

        public init(urlFilter: String) {
            self.urlFilter = urlFilter
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case loadContext = "load-context"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    public struct Action: Codable, Hashable, Sendable {
        public var type: String
        public var selector: String?

        public init(type: String, selector: String? = nil) {
            self.type = type
            self.selector = selector
        }
    }

    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }

    /// Encodes rules the way Safari wants them: a compact JSON array.
    public static func encode(_ rules: [SafariRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(rules)
    }
}
