#!/usr/bin/env python3
"""Tests for convert_filters.py. Run: python3 Tools/test_convert_filters.py"""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from convert_filters import convert_lists, is_safari_regex, pattern_to_url_filter  # noqa: E402


def rules_for(*lines):
    rules, _ = convert_lists(["\n".join(lines)])
    return rules


def matches(url_filter, url):
    return re.search(url_filter, url) is not None


class PatternTests(unittest.TestCase):
    def test_host_anchor(self):
        f = pattern_to_url_filter("||ads.example.com^")
        self.assertTrue(matches(f, "https://ads.example.com/x.js"))
        self.assertTrue(matches(f, "https://cdn.ads.example.com/"))
        self.assertTrue(matches(f, "http://ads.example.com:8080/"))
        self.assertFalse(matches(f, "https://ads.example.com.evil.net/"))
        self.assertFalse(matches(f, "https://badads.example.com/"))
        self.assertFalse(matches(f, "https://site.com/?u=ads.example.com"))

    def test_trailing_separator_in_path(self):
        f = pattern_to_url_filter("/banner/ad.js^")
        self.assertTrue(matches(f, "https://x.com/banner/ad.js"))
        self.assertTrue(matches(f, "https://x.com/banner/ad.js?v=1"))
        self.assertFalse(matches(f, "https://x.com/banner/ad.jsx"))

    def test_wildcards_and_escaping(self):
        f = pattern_to_url_filter("/ads/*.gif?")
        self.assertEqual(f, r"/ads/.*\.gif\?")

    def test_anchors(self):
        self.assertEqual(pattern_to_url_filter("|https://x.com/a|"), r"^https://x\.com/a$")

    def test_rejects_regex_and_unicode(self):
        self.assertIsNone(pattern_to_url_filter("/ba(n|d)ner/"))
        self.assertIsNone(pattern_to_url_filter("||reklama.żółw.pl^"))

    def test_safari_regex_check(self):
        self.assertFalse(is_safari_regex("a|b"))
        self.assertFalse(is_safari_regex("a{2}"))
        self.assertTrue(is_safari_regex(r"a\|b"))


class RuleTests(unittest.TestCase):
    def test_options(self):
        [rule] = rules_for("||tracker.com^$script,third-party,domain=a.com|b.com")
        t = rule["trigger"]
        self.assertEqual(t["resource-type"], ["script"])
        self.assertEqual(t["load-type"], ["third-party"])
        self.assertEqual(t["if-domain"], ["*a.com", "*b.com"])

    def test_negated_type(self):
        [rule] = rules_for("||x.com^$~script")
        self.assertNotIn("script", rule["trigger"]["resource-type"])
        self.assertIn("image", rule["trigger"]["resource-type"])

    def test_unsupported_options_are_skipped(self):
        self.assertEqual(rules_for("||x.com/a.js$script,redirect=noopjs"), [])
        self.assertEqual(rules_for("||x.com^$csp=script-src 'none'"), [])

    def test_exception_order(self):
        rules = rules_for("@@||good.com^", "||good.com^", "||evil.com^$important")
        self.assertEqual([r["action"]["type"] for r in rules], ["block", "ignore-previous-rules", "block"])
        self.assertIn("evil", rules[-1]["trigger"]["url-filter"])

    def test_page_allowlist(self):
        [rule] = rules_for("@@||bank.pl^$document")
        self.assertEqual(rule["trigger"], {"url-filter": ".*", "if-domain": ["*bank.pl"]})

    def test_badfilter(self):
        self.assertEqual(rules_for("||x.com^$script", "||x.com^$script,badfilter"), [])

    def test_cosmetic_generic_batching(self):
        rules = rules_for("##.ad", "##.banner", "###sponsor")
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0]["action"]["selector"], ".ad, .banner, #sponsor")

    def test_cosmetic_specific_and_exception(self):
        rules = rules_for("a.com,b.com##.promo", "b.com#@#.promo", "##.ad", "c.com#@#.ad")
        by_sel = {r["action"]["selector"]: r["trigger"] for r in rules}
        self.assertEqual(by_sel[".promo"]["if-domain"], ["*a.com"])
        self.assertEqual(by_sel[".ad"]["unless-domain"], ["*c.com"])

    def test_procedural_cosmetics_skipped(self):
        self.assertEqual(rules_for("x.com##div:has-text(Sponsored)", "x.com##+js(set-constant, a, 1)",
                                   "x.com#?#.ad", "x.com##.a:style(display:none)"), [])

    def test_has_is_kept(self):
        [rule] = rules_for("x.com##div:has(> .ad)")
        self.assertEqual(rule["action"]["selector"], "div:has(> .ad)")

    def test_comments_ignored(self):
        self.assertEqual(rules_for("! comment", "[Adblock Plus 2.0]", "# hosts comment"), [])


if __name__ == "__main__":
    unittest.main()
