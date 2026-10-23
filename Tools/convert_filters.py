#!/usr/bin/env python3
"""Convert Adblock Plus / uBlock Origin filter lists into Safari content blocker JSON.

Usage:
    python3 Tools/convert_filters.py            # download lists and convert
    python3 Tools/convert_filters.py --offline  # reuse lists cached in Tools/.cache

Writes Generated/<group>.json (one per content blocker) and Generated/metadata.json.

Safari rules are much simpler than uBlock's, so some filters can't be converted
and are skipped: regex filters, scriptlets (##+js), procedural cosmetics
(:has-text, :upward, ...), redirects, $csp, $removeparam and similar.
Scriptlets are handled by the Safari Web Extension instead.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Tools" / "filters.json"
CACHE = ROOT / "Tools" / ".cache"
OUT = ROOT / "Generated"

MAX_RULES = 150_000          # Safari's per-blocker limit (iOS 15+)
SELECTORS_PER_RULE = 50      # generic cosmetic selectors are batched to save rules

ALL_TYPES = ["document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]

TYPE_OPTIONS = {
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
}

# Options that change how a rule behaves in ways Safari can't express.
UNSUPPORTED_OPTIONS = {
    "redirect", "redirect-rule", "rewrite", "csp", "removeparam", "queryprune", "header",
    "permissions", "replace", "denyallow", "to", "method", "strict1p", "strict3p",
    "elemhide", "ehide", "generichide", "ghide", "specifichide", "shide", "genericblock",
    "empty", "mp4", "inline-script", "inline-font", "cname", "urlskip", "uritransform",
    "jsonprune", "network", "content", "webrtc", "ipaddress", "reason",
}

# Cosmetic syntaxes Safari can't do (procedural, scriptlets, HTML filters, CSS injection).
UNSUPPORTED_COSMETIC_SEPARATORS = ("#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#", "#$?#", "#@$?#")
UNSUPPORTED_SELECTOR_PARTS = (
    ":has-text(", ":-abp-", ":contains(", ":upward(", ":xpath(", ":matches-css", ":matches-attr(",
    ":matches-path(", ":matches-prop(", ":min-text-length(", ":watch-attr(", ":remove(", ":remove-attr(",
    ":remove-class(", ":style(", ":others(", ":if(", ":if-not(", ":nth-ancestor(", ":shadow(",
    ":matches-media(", ":spath(",
)

SEPARATOR_CLASS = "[^a-zA-Z0-9_.%-]"


@dataclass
class Stats:
    converted: int = 0
    skipped: int = 0
    reasons: dict = field(default_factory=lambda: defaultdict(int))

    def skip(self, reason: str) -> None:
        self.skipped += 1
        self.reasons[reason] += 1


# ---------------------------------------------------------------- helpers

def to_ascii_domain(domain: str) -> str | None:
    domain = domain.strip().lower()
    if not domain or "*" in domain or "/" in domain or domain.endswith("."):
        return None  # entity wildcards (example.*) and regex domains aren't supported
    try:
        return domain.encode("idna").decode("ascii")
    except UnicodeError:
        return None


def parse_domains(items: list[str]) -> tuple[list[str], list[str]] | None:
    """Split 'a.com', '~b.com' into Safari if-domain / unless-domain lists."""
    include, exclude = [], []
    for item in items:
        item = item.strip()
        if not item:
            continue
        negated = item.startswith("~")
        domain = to_ascii_domain(item.lstrip("~"))
        if domain is None:
            return None
        (exclude if negated else include).append("*" + domain)
    return sorted(set(include)), sorted(set(exclude))


def escape_regex_char(ch: str) -> str:
    return "\\" + ch if ch in ".+?()[]{}\\$|" else ch


def pattern_to_url_filter(pattern: str) -> str | None:
    """Translate an ABP URL pattern into Safari's restricted regex dialect."""
    if not pattern.isascii():
        return None
    if len(pattern) > 2 and pattern.startswith("/") and pattern.endswith("/"):
        return None  # raw regex filters: Safari's regex subset is too different

    prefix = ""
    host_anchor = False
    if pattern.startswith("||"):
        pattern = pattern[2:]
        prefix = r"^[^:]+://+([^:/]+\.)?"
        host_anchor = True
    elif pattern.startswith("|"):
        pattern = pattern[1:]
        prefix = "^"

    suffix = ""
    if pattern.endswith("|"):
        pattern = pattern[:-1]
        suffix = "$"

    pattern = pattern.lstrip("*") if not prefix else pattern
    pattern = pattern.rstrip("*") if not suffix else pattern

    out = []
    in_host = host_anchor
    for i, ch in enumerate(pattern):
        last = i == len(pattern) - 1
        if ch in "/?":
            in_host = False
        if ch == "*":
            if not out or out[-1] != ".*":
                out.append(".*")
        elif ch == "^":
            if in_host:
                out.append("[/:]")  # a URL always has / or :port after the host
                in_host = False
            elif last and not suffix:
                out.append(f"({SEPARATOR_CLASS}.*)?$")  # separator or end of URL
            else:
                out.append(SEPARATOR_CLASS)
        else:
            out.append(escape_regex_char(ch))

    body = "".join(out)
    if not body and not prefix:
        return ".*"
    result = prefix + body + suffix
    return result if is_safari_regex(result) else None


def is_safari_regex(regex: str) -> bool:
    """Safari rejects the whole list if a single url-filter is invalid, so be strict."""
    if not regex.isascii():
        return False
    i = 0
    while i < len(regex):
        ch = regex[i]
        if ch == "\\":
            i += 2
            continue
        if ch in "|{}":
            return False
        i += 1
    try:
        re.compile(regex)
    except re.error:
        return False
    return True


def selector_is_supported(selector: str) -> bool:
    if any(part in selector for part in UNSUPPORTED_SELECTOR_PARTS):
        return False
    if selector.startswith("+js(") or selector.startswith("^") or selector.startswith("//"):
        return False
    # Cheap sanity check: brackets, parens and quotes must balance.
    stack = []
    pairs = {")": "(", "]": "["}
    quote = None
    for ch in selector:
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([":
            stack.append(ch)
        elif ch in ")]":
            if not stack or stack.pop() != pairs[ch]:
                return False
    return not stack and quote is None


# ---------------------------------------------------------------- conversion

@dataclass
class Converted:
    blocks: list = field(default_factory=list)
    important: list = field(default_factory=list)
    exceptions: list = field(default_factory=list)
    generic_selectors: list = field(default_factory=list)
    generic_with_exclusions: dict = field(default_factory=lambda: defaultdict(set))
    specific_selectors: dict = field(default_factory=lambda: defaultdict(list))
    cosmetic_exceptions: dict = field(default_factory=lambda: defaultdict(set))


def convert_network(line: str, out: Converted, stats: Stats) -> None:
    exception = line.startswith("@@")
    body = line[2:] if exception else line

    pattern, options = body, []
    if not (body.startswith("/") and body.endswith("/")):
        # Options start at the first "$" followed by an option name.
        # (Option values like $urlskip=/...$/ can contain "$" too.)
        for m in re.finditer(r"\$(?=~?[a-z0-9-]+(=|,|$))", body, re.IGNORECASE):
            pattern, options = body[:m.start()], body[m.end():].split(",")
            break

    trigger: dict = {}
    types: list[str] = []
    negated_types: list[str] = []
    important = False
    page_allowlist = False
    domains = None

    for raw in options:
        if not raw:
            continue
        negated = raw.startswith("~")
        name, _, value = raw.lstrip("~").partition("=")
        name = name.lower()
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["first-party" if negated else "third-party"]
        elif name in ("first-party", "1p"):
            trigger["load-type"] = ["third-party" if negated else "first-party"]
        elif name in ("domain", "from"):
            domains = parse_domains(value.split("|"))
            if domains is None:
                return stats.skip("unsupported domain option")
        elif name == "match-case":
            trigger["url-filter-is-case-sensitive"] = True
        elif name == "important":
            important = True
        elif name in ("document", "doc"):
            if exception:
                page_allowlist = True
            else:
                types.append("document")
        elif name == "all":
            pass
        elif name in TYPE_OPTIONS:
            (negated_types if negated else types).extend(TYPE_OPTIONS[name])
            if name in ("subdocument", "frame") and not negated:
                trigger["load-context"] = ["child-frame"]
        elif name == "badfilter":
            return  # handled in the first pass
        elif name in UNSUPPORTED_OPTIONS:
            return stats.skip(f"${name}")
        else:
            return stats.skip("unknown option")

    url_filter = pattern_to_url_filter(pattern)
    if url_filter is None:
        return stats.skip("url pattern")

    has_constraint = bool(domains and domains[0]) or page_allowlist
    if url_filter == ".*" and not has_constraint and not types:
        return stats.skip("matches everything")

    trigger["url-filter"] = url_filter
    if types:
        trigger["resource-type"] = sorted(set(types))
    elif negated_types:
        trigger["resource-type"] = [t for t in ALL_TYPES if t not in negated_types]
    elif exception and not page_allowlist:
        # A plain @@ rule shouldn't switch off cosmetic filtering for the whole page.
        trigger["resource-type"] = [t for t in ALL_TYPES if t != "document"]

    if domains:
        include, exclude = domains
        if include:
            trigger["if-domain"] = include
        elif exclude:
            trigger["unless-domain"] = exclude

    if page_allowlist:
        # @@||site.com^$document turns all blocking off on that site.
        if "if-domain" not in trigger:
            host = re.match(r"^\|\|([a-z0-9.-]+)\^?$", pattern.lower())
            if not host:
                return stats.skip("page allowlist without domain")
            trigger = {"url-filter": ".*", "if-domain": ["*" + host.group(1)]}
        else:
            trigger = {"url-filter": ".*", "if-domain": trigger["if-domain"]}

    if exception and "load-context" in trigger and trigger.get("resource-type") != ["document"]:
        del trigger["load-context"]

    rule = {"trigger": trigger, "action": {"type": "ignore-previous-rules" if exception else "block"}}
    (out.exceptions if exception else out.important if important else out.blocks).append(rule)
    stats.converted += 1


def convert_cosmetic(line: str, out: Converted, stats: Stats) -> None:
    if any(sep in line for sep in UNSUPPORTED_COSMETIC_SEPARATORS):
        return stats.skip("procedural / scriptlet")
    exception = "#@#" in line
    domains_part, _, selector = line.partition("#@#" if exception else "##")
    selector = selector.strip()
    if not selector or not selector_is_supported(selector):
        return stats.skip("selector")

    domains = parse_domains(domains_part.split(",")) if domains_part else ([], [])
    if domains is None:
        return stats.skip("unsupported domain option")
    include, exclude = domains

    if exception:
        for d in include:
            out.cosmetic_exceptions[selector].add(d)
        if not include:
            out.cosmetic_exceptions[selector].add("*")
        stats.converted += 1
        return

    if include:
        out.specific_selectors[selector].extend(include)
    elif exclude:
        out.generic_with_exclusions[selector].update(exclude)
    else:
        out.generic_selectors.append(selector)
    stats.converted += 1


def build_rules(out: Converted) -> list[dict]:
    cosmetic: list[dict] = []
    exc = out.cosmetic_exceptions

    # Generic selectors, batched. Selectors with exceptions get their own rule.
    batch = []
    for selector in dict.fromkeys(out.generic_selectors):
        if "*" in exc.get(selector, ()):
            continue
        if selector in exc:
            out.generic_with_exclusions[selector].update(exc[selector])
            continue
        batch.append(selector)
    for i in range(0, len(batch), SELECTORS_PER_RULE):
        cosmetic.append({
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ", ".join(batch[i:i + SELECTORS_PER_RULE])},
        })
    for selector, unless in sorted(out.generic_with_exclusions.items()):
        cosmetic.append({
            "trigger": {"url-filter": ".*", "unless-domain": sorted(unless)},
            "action": {"type": "css-display-none", "selector": selector},
        })

    # Site-specific selectors, grouped by identical domain lists.
    by_domains: dict[tuple, list[str]] = defaultdict(list)
    for selector, domains in out.specific_selectors.items():
        if "*" in exc.get(selector, ()):
            continue
        remaining = sorted(set(domains) - exc.get(selector, set()))
        if remaining:
            by_domains[tuple(remaining)].append(selector)
    for domains, selectors in sorted(by_domains.items()):
        for i in range(0, len(selectors), SELECTORS_PER_RULE):
            cosmetic.append({
                "trigger": {"url-filter": ".*", "if-domain": list(domains)},
                "action": {"type": "css-display-none", "selector": ", ".join(selectors[i:i + SELECTORS_PER_RULE])},
            })

    # Order matters: ignore-previous-rules only cancels rules above it.
    head = dedupe(out.blocks + cosmetic)
    tail = dedupe(out.exceptions) + dedupe(out.important)
    room = MAX_RULES - len(tail)
    if len(head) > room:
        print(f"  ! {len(head) + len(tail)} rules is over Safari's limit, dropping {len(head) - room}", file=sys.stderr)
        head = head[:room]
    return head + tail


def dedupe(rules: list[dict]) -> list[dict]:
    seen, result = set(), []
    for rule in rules:
        key = json.dumps(rule, sort_keys=True)
        if key not in seen:
            seen.add(key)
            result.append(rule)
    return result


def convert_lists(texts: list[str]) -> tuple[list[dict], Stats]:
    stats = Stats()
    out = Converted()
    lines = [l.strip() for text in texts for l in text.splitlines()]

    badfilters = set()
    for line in lines:
        if "$" in line and "badfilter" in line:
            body, _, opts = line.rpartition("$")
            rest = [o for o in opts.split(",") if o != "badfilter"]
            badfilters.add(body + ("$" + ",".join(rest) if rest else ""))

    for line in lines:
        if not line or line.startswith(("!", "[")) or line in badfilters:
            continue
        if line.startswith("#") and not line.startswith(("##", "#@#", "#?#", "#$#")):
            continue  # hosts-file style comments
        if re.search(r"#[@?$%]*#", line) and not line.startswith(("/", "|", "@@")):
            convert_cosmetic(line, out, stats)
        else:
            convert_network(line, out, stats)
    return build_rules(out), stats


# ---------------------------------------------------------------- I/O

def fetch(url: str, offline: bool) -> str:
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / re.sub(r"[^\w.-]", "_", url)
    if not offline:
        request = urllib.request.Request(url, headers={"User-Agent": "uKivi filter converter"})
        with urllib.request.urlopen(request, timeout=60) as response:
            cached.write_bytes(response.read())
    if not cached.exists():
        raise SystemExit(f"No cached copy of {url}; run without --offline first.")
    return cached.read_text(encoding="utf-8", errors="replace")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--offline", action="store_true", help="use cached lists instead of downloading")
    args = parser.parse_args()

    config = json.loads(CONFIG.read_text())
    OUT.mkdir(exist_ok=True)
    metadata = {"generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"), "groups": {}}

    for group, lists in config["groups"].items():
        print(f"{group}:")
        texts = []
        for entry in lists:
            print(f"  fetching {entry['name']}")
            texts.append(fetch(entry["url"], args.offline))
        rules, stats = convert_lists(texts)
        (OUT / f"{group}.json").write_text(json.dumps(rules, separators=(",", ":")))
        top = ", ".join(f"{k} {v}" for k, v in sorted(stats.reasons.items(), key=lambda kv: -kv[1])[:4])
        print(f"  {stats.converted} filters converted into {len(rules)} Safari rules; skipped {stats.skipped} ({top})")
        metadata["groups"][group] = {"rules": len(rules), "lists": [e["name"] for e in lists]}

    (OUT / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
