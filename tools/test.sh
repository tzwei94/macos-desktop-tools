#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/desktop-tools-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
python3 -m unittest discover -s "$root/apps/menu-bar-spacing/tests" -v
/usr/bin/xcrun swiftc -warnings-as-errors "$root/apps/display-mode-toggle/src/DisplayPlan.swift" "$root/tests/display-plan-tests.swift" -o "$temporary/planning-tests"
"$temporary/planning-tests"
for source in "$root/apps/displaylink-toggle/src/DisplayLinkToggle.applescript" "$root/apps/display-mode-toggle/src/DisplayModeToggle.applescript"; do
    /usr/bin/osacompile -o "$temporary/$(basename "$source").scpt" "$source"
done
echo 'Preference, display planning, and script compilation checks passed.'
