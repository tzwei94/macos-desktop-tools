#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" != "v$version" ]]; then
    echo 'Release tag must match VERSION.' >&2; exit 1
fi
mkdir -p "$root/dist"
stage="$(mktemp -d "${TMPDIR:-/tmp}/desktop-tools-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
/usr/bin/xcrun clang -fobjc-arc -Wall -Wextra -Werror -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.0 -framework Cocoa "$root/tools/Launcher.m" \
    "$root/apps/displaylink-toggle/src/DisplayLinkController.m" -o "$stage/launcher"
for architecture in arm64 x86_64; do
    /usr/bin/xcrun swiftc -O -warnings-as-errors -target "$architecture-apple-macos13.0" \
        "$root/apps/display-mode-toggle/src/DisplayPlan.swift" \
        "$root/apps/display-mode-toggle/src/DisplayMode.swift" -o "$stage/display-mode-$architecture"
done
/usr/bin/lipo -create "$stage/display-mode-arm64" "$stage/display-mode-x86_64" -output "$stage/display-mode"
while IFS='|' read -r slug name script identifier; do
    app="$stage/$name.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Scripts"
    cp "$stage/launcher" "$app/Contents/MacOS/applet"
    if [[ "$script" != - ]]; then
        /usr/bin/osacompile -o "$app/Contents/Resources/Scripts/main.scpt" "$root/apps/$slug/src/$script"
    fi
    cp "$root/assets/icons/$slug/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    cp "$root/assets/icons/$slug/AppIcon.ico" "$app/Contents/Resources/AppIcon.ico"
    if [[ "$slug" == display-mode-toggle ]]; then
        cp "$stage/display-mode" "$app/Contents/Resources/display-mode"
        /usr/bin/codesign --force --sign - --timestamp=none --identifier "$identifier.helper" "$app/Contents/Resources/display-mode"
    fi
    python3 - "$app/Contents/Info.plist" "$name" "$identifier" "$version" "$slug" <<'PY'
import plistlib, sys
path, name, identifier, version, slug = sys.argv[1:]
info = dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=identifier,
            CFBundleExecutable='applet', CFBundlePackageType='APPL', CFBundleInfoDictionaryVersion='6.0',
            CFBundleShortVersionString=version, CFBundleVersion=version, CFBundleIconFile='AppIcon.icns',
            LSMinimumSystemVersion='13.0', LSMultipleInstancesProhibited=True,
            NSHumanReadableCopyright='macOS Desktop Tools contributors')
if slug == 'displaylink-toggle':
    info['LSUIElement'] = True
with open(path, 'wb') as output:
    plistlib.dump(info, output)
PY
    /usr/bin/codesign --force --sign - --timestamp=none --identifier "$identifier" "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
    destination="$root/dist/$name.app"
    if [[ -e "$destination" ]]; then rm -rf "$destination"; fi
    /usr/bin/ditto --norsrc --noextattr "$app" "$destination"
    /usr/bin/ditto -c -k --keepParent --norsrc "$app" "$root/dist/$slug-$version.zip"
done <<'APPS'
menu-bar-spacing|Menu Bar Spacing|MenuBarSpacing.applescript|io.github.tzwei94.MenuBarSpacing
displaylink-toggle|DisplayLink Toggle|-|io.github.tzwei94.DisplayLinkToggle
display-mode-toggle|Toggle Display Mode|DisplayModeToggle.applescript|io.github.tzwei94.DisplayModeToggle
APPS
(
    cd "$root/dist"
    /usr/bin/shasum -a 256 "menu-bar-spacing-$version.zip" "displaylink-toggle-$version.zip" "display-mode-toggle-$version.zip" > "SHA256SUMS"
)
echo "Built all three apps and ZIP downloads ($version)."
