#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"
temporary="$(mktemp -d "$root/build/desktop-tools-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
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
