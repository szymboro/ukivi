#!/usr/bin/env python3
"""Checks that the Swift converter (FilterKit, used on the phone) produces exactly the
same rules as convert_filters.py, using the lists cached by convert_filters.py.

Usage: python3 Tools/compare_converters.py   (needs Swift; run convert_filters.py once first)
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from convert_filters import CACHE, CONFIG, ROOT, convert_lists  # noqa: E402

PACKAGE = ROOT / "Packages" / "FilterKit"


def main() -> int:
    subprocess.run(["swift", "build", "-c", "release", "--package-path", str(PACKAGE)], check=True)
    cli = PACKAGE / ".build" / "release" / "filterkit"

    config = json.loads(CONFIG.read_text())
    failed = False
    for group, lists in config["groups"].items():
        paths = [CACHE / re.sub(r"[^\w.-]", "_", entry["url"]) for entry in lists]
        missing = [p for p in paths if not p.exists()]
        if missing:
            print(f"{group}: missing cached lists, run Tools/convert_filters.py first")
            return 1

        texts = [p.read_text(encoding="utf-8", errors="replace") for p in paths]
        python_rules, _ = convert_lists(texts)

        with tempfile.NamedTemporaryFile(suffix=".json") as out:
            result = subprocess.run([str(cli), out.name, *map(str, paths)], check=True, capture_output=True, text=True)
            swift_rules = json.loads(Path(out.name).read_text())

        if python_rules == swift_rules:
            print(f"{group}: identical ({len(swift_rules)} rules) - swift: {result.stdout.strip()}")
            continue

        failed = True
        print(f"{group}: DIFFERENT (python {len(python_rules)}, swift {len(swift_rules)})")
        for i, (a, b) in enumerate(zip(python_rules, swift_rules)):
            if a != b:
                print(f"  first difference at rule {i}:\n    python: {a}\n    swift:  {b}")
                break
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
