#!/usr/bin/env python3
"""Verify distributable bundles without changing preferences or displays."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = (ROOT / 'VERSION').read_text().strip()
APPS = (
    ('menu-bar-spacing', 'Menu Bar Spacing', 'MenuBarSpacing'),
    ('displaylink-toggle', 'DisplayLink Toggle', 'DisplayLinkToggle'),
    ('display-mode-toggle', 'Toggle Display Mode', 'DisplayModeToggle'),
)


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def verify_binary(path):
    assert set(run('/usr/bin/lipo', '-archs', str(path)).split()) == {'arm64', 'x86_64'}, path
    for architecture in ('arm64', 'x86_64'):
        load_commands = run('/usr/bin/otool', '-arch', architecture, '-l', str(path))
        assert 'minos 13.0' in load_commands or 'version 13.0' in load_commands, path


def verify_icons(resources, slug):
    for suffix in ('icns', 'ico'):
        data = (resources / f'AppIcon.{suffix}').read_bytes()
        assert data == (ROOT / 'assets/icons' / slug / f'AppIcon.{suffix}').read_bytes()
        if suffix == 'icns':
            assert data[:4] == b'icns' and struct.unpack('>I', data[4:8])[0] == len(data)
        else:
            assert struct.unpack('<HHH', data[:6]) == (0, 1, 6)
            for index, size in enumerate((16, 32, 48, 64, 128, 256)):
                width, height, _, _, _, _, length, offset = struct.unpack_from('<BBBBHHII', data, 6 + index * 16)
                assert (width or 256, height or 256) == (size, size)
                payload = data[offset:offset + length]
                assert len(payload) == length and payload[:8] == b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II', payload[16:24]) == (size, size)


def verify_app(app, slug, identifier):
    with (app / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    assert info['CFBundleIdentifier'] == 'io.github.tzwei94.' + identifier
    assert info['CFBundleName'] == app.stem
    assert info['CFBundleShortVersionString'] == VERSION
    assert info['LSMinimumSystemVersion'] == '13.0'
    assert info['CFBundleIconFile'] == 'AppIcon.icns'
    assert not {key for key in info if key.endswith('UsageDescription')}
    assert not any(path.name == 'Icon\r' for path in app.rglob('*'))
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    verify_binary(app / 'Contents/MacOS' / info['CFBundleExecutable'])
    resources = app / 'Contents/Resources'
    verify_icons(resources, slug)
    assert (resources / 'Scripts/main.scpt').is_file() == (slug != 'displaylink-toggle')
    if slug == 'display-mode-toggle':
        helper = resources / 'display-mode'
        verify_binary(helper)
        run('/usr/bin/codesign', '--verify', '--strict', str(helper))
        invalid = subprocess.run([str(helper), 'invalid-command'], capture_output=True, text=True)
        assert invalid.returncode != 0 and 'Usage:' in invalid.stderr


def main():
    assert not list((ROOT / 'dist').glob('*.dmg'))
    checksums = {}
    for line in (ROOT / 'dist/SHA256SUMS').read_text().splitlines():
        digest, filename = line.split(maxsplit=1)
        checksums[filename] = digest
    expected = {f'{slug}-{VERSION}.zip' for slug, _, _ in APPS}
    assert set(checksums) == expected
    for slug, name, identifier in APPS:
        app_name = name + '.app'
        verify_app(ROOT / 'dist' / app_name, slug, identifier)
        archive = ROOT / 'dist' / f'{slug}-{VERSION}.zip'
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == checksums[archive.name]
        with tempfile.TemporaryDirectory(prefix='desktop tools package ') as folder:
            run('/usr/bin/ditto', '-x', '-k', str(archive), folder)
            assert {path.name for path in Path(folder).iterdir()} == {app_name}
            verify_app(Path(folder) / app_name, slug, identifier)
        print(f'Verified {app_name}, embedded icons, universal binaries, signature, ZIP and checksum.')
    with tempfile.TemporaryDirectory(prefix='display resource check ') as folder:
        app = Path(folder) / 'Resource Check.app'
        shutil.copytree(ROOT / 'dist/Toggle Display Mode.app', app)
        executable = app / 'Contents/MacOS/applet'
        run('/usr/bin/xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
            '-framework', 'Cocoa', str(ROOT / 'tests/resource-path-probe.m'), '-o', str(executable))
        run('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(app))
        probe = subprocess.run([str(executable)], capture_output=True, text=True, check=True)
        helper = Path(probe.stdout.strip())
        expected_helper = (app / 'Contents/Resources/display-mode').resolve()
        assert helper.resolve() == expected_helper, (str(helper), str(expected_helper))
        assert helper.is_file()
        print('Verified production AppleScript locates its helper inside a relocated bundle.')


if __name__ == '__main__':
    main()
