import Foundation
import XCTest
@testable import FilterKit

final class FilterConverterTests: XCTestCase {
    private func rules(_ lines: String...) -> [SafariRule] {
        FilterConverter.convert([lines.joined(separator: "\n")]).rules
    }

    private func matches(_ filter: String?, _ url: String) -> Bool {
        guard let filter, let regex = try? NSRegularExpression(pattern: filter) else { return false }
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    // MARK: URL patterns

    func testHostAnchor() {
        let f = FilterConverter.urlFilter(fromPattern: "||ads.example.com^")
        XCTAssertTrue(matches(f, "https://ads.example.com/x.js"))
        XCTAssertTrue(matches(f, "https://cdn.ads.example.com/"))
        XCTAssertTrue(matches(f, "http://ads.example.com:8080/"))
        XCTAssertFalse(matches(f, "https://ads.example.com.evil.net/"))
        XCTAssertFalse(matches(f, "https://badads.example.com/"))
        XCTAssertFalse(matches(f, "https://site.com/?u=ads.example.com"))
    }

    func testTrailingSeparatorInPath() {
        let f = FilterConverter.urlFilter(fromPattern: "/banner/ad.js^")
        XCTAssertTrue(matches(f, "https://x.com/banner/ad.js"))
        XCTAssertTrue(matches(f, "https://x.com/banner/ad.js?v=1"))
        XCTAssertFalse(matches(f, "https://x.com/banner/ad.jsx"))
    }

    func testWildcardsEscapingAndAnchors() {
        XCTAssertEqual(FilterConverter.urlFilter(fromPattern: "/ads/*.gif?"), #"/ads/.*\.gif\?"#)
        XCTAssertEqual(FilterConverter.urlFilter(fromPattern: "|https://x.com/a|"), #"^https://x\.com/a$"#)
    }

    func testRejectsRegexAndUnicode() {
        XCTAssertNil(FilterConverter.urlFilter(fromPattern: "/ba(n|d)ner/"))
        XCTAssertNil(FilterConverter.urlFilter(fromPattern: "||reklama.żółw.pl^"))
        XCTAssertFalse(FilterConverter.isSafariRegex("a|b"))
        XCTAssertFalse(FilterConverter.isSafariRegex("a{2}"))
        XCTAssertTrue(FilterConverter.isSafariRegex(#"a\|b"#))
    }

    func testPunycodeDomains() {
        XCTAssertEqual(FilterConverter.asciiDomain("żółw.pl"), "xn--w-uga1v8h.pl")
        XCTAssertEqual(FilterConverter.asciiDomain("bücher.de"), "xn--bcher-kva.de")
        XCTAssertNil(FilterConverter.asciiDomain("example.*"))
        XCTAssertNil(FilterConverter.asciiDomain(".example.com"))
    }

    // MARK: Rules

    func testOptions() throws {
        let rule = try XCTUnwrap(rules("||tracker.com^$script,third-party,domain=a.com|b.com").first)
        XCTAssertEqual(rule.trigger.resourceType, ["script"])
        XCTAssertEqual(rule.trigger.loadType, ["third-party"])
        XCTAssertEqual(rule.trigger.ifDomain, ["*a.com", "*b.com"])
    }

    func testNegatedType() throws {
        let rule = try XCTUnwrap(rules("||x.com^$~script").first)
        XCTAssertFalse(rule.trigger.resourceType?.contains("script") ?? true)
        XCTAssertTrue(rule.trigger.resourceType?.contains("image") ?? false)
    }

    func testUnsupportedOptionsAreSkipped() {
        XCTAssertTrue(rules("||x.com/a.js$script,redirect=noopjs").isEmpty)
        XCTAssertTrue(rules("||x.com^$csp=script-src 'none'").isEmpty)
    }

    func testExceptionOrder() {
        let result = rules("@@||good.com^", "||good.com^", "||evil.com^$important")
        XCTAssertEqual(result.map(\.action.type), ["block", "ignore-previous-rules", "block"])
        XCTAssertTrue(result.last?.trigger.urlFilter.contains("evil") ?? false)
    }

    func testPageAllowlist() throws {
        let rule = try XCTUnwrap(rules("@@||bank.pl^$document").first)
        XCTAssertEqual(rule.trigger.urlFilter, ".*")
        XCTAssertEqual(rule.trigger.ifDomain, ["*bank.pl"])
        XCTAssertNil(rule.trigger.resourceType)
    }

    func testBadfilter() {
        XCTAssertTrue(rules("||x.com^$script", "||x.com^$script,badfilter").isEmpty)
    }

    func testCosmeticBatching() {
        let result = rules("##.ad", "##.banner", "###sponsor")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.action.selector, ".ad, .banner, #sponsor")
    }

    func testCosmeticSpecificAndExceptions() {
        let result = rules("a.com,b.com##.promo", "b.com#@#.promo", "##.ad", "c.com#@#.ad")
        let bySelector = Dictionary(uniqueKeysWithValues: result.map { ($0.action.selector ?? "", $0.trigger) })
        XCTAssertEqual(bySelector[".promo"]?.ifDomain, ["*a.com"])
        XCTAssertEqual(bySelector[".ad"]?.unlessDomain, ["*c.com"])
    }

    func testProceduralCosmeticsSkipped() {
        XCTAssertTrue(rules(
            "x.com##div:has-text(Sponsored)", "x.com##+js(set-constant, a, 1)",
            "x.com#?#.ad", "x.com##.a:style(display:none)"
        ).isEmpty)
    }

    func testHasIsKept() {
        XCTAssertEqual(rules("x.com##div:has(> .ad)").first?.action.selector, "div:has(> .ad)")
    }

    func testCommentsIgnored() {
        XCTAssertTrue(rules("! comment", "[Adblock Plus 2.0]", "# hosts comment").isEmpty)
    }

    func testReportsRulesOverLimit() {
        let lines = (0..<(FilterConverter.maxRules + 10)).map { "||ad\($0).example.com^" }
        let (rules, stats) = FilterConverter.convert([lines.joined(separator: "\n")])
        XCTAssertEqual(rules.count, FilterConverter.maxRules)
        XCTAssertEqual(stats.droppedForLimit, 10)
    }

    func testEncodingOmitsEmptyFields() throws {
        let data = try SafariRule.encode(rules("||x.com^"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("null"))
        XCTAssertTrue(json.contains(#""url-filter""#))
    }
}
