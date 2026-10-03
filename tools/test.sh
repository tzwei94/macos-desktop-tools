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
/usr/bin/xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Cocoa -framework CoreServices \
    "$root/tests/displaylink-lifecycle-tests.m" "$root/apps/displaylink-toggle/src/DisplayLinkController.m" \
    -o "$temporary/lifecycle-tests"
fixture="$temporary/Test DisplayLink Manager.app"
mkdir -p "$fixture/Contents/MacOS"
cp "$temporary/lifecycle-tests" "$fixture/Contents/MacOS/fixture"
python3 - "$fixture/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(dict(CFBundleIdentifier='io.github.tzwei94.DisplayLinkLifecycleFixture',
        CFBundleName='Test DisplayLink Manager', CFBundleExecutable='fixture', CFBundlePackageType='APPL', LSUIElement=True,
        LifecycleLogPath=str(Path(sys.argv[1]).parents[2] / 'lifecycle.log')), output)
PY
/usr/bin/codesign --force --sign - --timestamp=none "$fixture"
"$temporary/lifecycle-tests" "$fixture"
echo 'Preference, display planning, script compilation, and app lifecycle checks passed.'
