#!/usr/bin/env bash
# Builds uKivi and installs it on the connected iPhone.
#   ./run.sh           build + install
#   ./run.sh --lists   also re-download and convert the filter lists first
set -euo pipefail
cd "$(dirname "$0")"

# The iOS SDK opens thousands of files during a build; the default limit (1024) is too low.
ulimit -n "$(ulimit -Hn)"

# Make `swift` available if it was installed with swiftly.
if ! command -v swift >/dev/null && [ -f "$HOME/.local/share/swiftly/env.sh" ]; then
  . "$HOME/.local/share/swiftly/env.sh"
fi

if [[ "${1:-}" == "--lists" || ! -f Generated/ads.json ]]; then
  python3 Tools/convert_filters.py
fi

# Prefer the patched xtool that enables App Groups on free accounts
# (needed for filter updates, the on/off switch and allowed sites). See README.
XTOOL="${XTOOL:-$HOME/Development/xtool-patched/.build/release/xtool}"
[[ -x "$XTOOL" ]] || XTOOL=xtool
echo "Using $XTOOL"

"$XTOOL" dev
