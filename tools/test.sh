#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"
# Launch Services may exclude app fixtures inside macOS's private temp folders.
temporary="$(mktemp -d "$root/build/desktop-tools-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
python3 -m unittest discover -s "$root/apps/menu-bar-spacing/tests" -v
/usr/bin/xcrun swiftc -warnings-as-errors "$root/apps/display-mode-toggle/src/DisplayPlan.swift" "$root/tests/display-plan-tests.swift" -o "$temporary/planning-tests"
"$temporary/planning-tests"
for source in "$root/apps/display-mode-toggle/src/DisplayModeToggle.applescript"; do
    /usr/bin/osacompile -o "$temporary/$(basename "$source").scpt" "$source"
done
bash "$root/tools/test-displaylink.sh"
echo 'Preference, display planning, script compilation, and app lifecycle checks passed.'
