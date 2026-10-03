"""Exercise the shipped AppleScript against unique current-host test domains."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPACING = "NSStatusItemSpacing"
PADDING = "NSStatusItemSelectionPadding"


class PreferencesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = ROOT / "src/MenuBarSpacing.applescript"
        if not source.exists():
            raise AssertionError("Missing Menu Bar Spacing implementation")
        cls.build = tempfile.TemporaryDirectory(prefix="menu bar spacing tests ")
        cls.script = Path(cls.build.name) / "preferences.scpt"
        subprocess.run(["/usr/bin/osacompile", "-o", str(cls.script), str(source)],
                       check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.domain = "io.github.tzwei94.MenuBarSpacing.test." + uuid.uuid4().hex
        self.scratch = tempfile.TemporaryDirectory(prefix="spacing failure ")
        self.executable = "/usr/bin/defaults"

    def tearDown(self):
        self.defaults("delete", self.domain, check=False)
        self.scratch.cleanup()

    def defaults(self, *args, check=True):
        return subprocess.run(["/usr/bin/defaults", "-currentHost", *args],
                              capture_output=True, text=True, check=check)

    def write(self, key, kind, value):
        self.defaults("write", self.domain, key, "-" + kind, str(value))

    def value(self, key):
        result = self.defaults("read", self.domain, key, check=False)
        return result.stdout.rstrip("\n") if result.returncode == 0 else None

    def call(self, operation, value="", check=True):
        result = subprocess.run([
            "/usr/bin/osascript", str(ROOT / "tests/invoke.applescript"),
            str(self.script), self.domain, self.executable, operation, value,
        ], capture_output=True, text=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def fail_defaults(self, *, persistent=False, operation="write", key=PADDING):
        # Real defaults still performs every successful operation. Only the
        # selected mutation fails, allowing the actual rollback to be exercised.
        directory = Path(self.scratch.name)
        wrapper = directory / "defaults"
        marker = directory / "already failed"
        import shlex
        marker_text = shlex.quote(str(marker))
        wrapper.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            f"marker={marker_text}\n"
            f'if [[ "$2" == "{operation}" && "$4" == "{key}" ]]; then\n'
            + ("  if true; then\n" if persistent else '  if [[ ! -e "$marker" ]]; then\n')
            + '    touch "$marker"\n'
            + '    echo "simulated preference failure" >&2\n'
            + '    exit 1\n  fi\nfi\nexec /usr/bin/defaults "$@"\n'
        )
        if persistent:
            wrapper.write_text(wrapper.read_text().replace(
                'exec /usr/bin/defaults "$@"',
                f'if [[ "$2" == "write" && "$4" == "{SPACING}" && -e "$marker" ]]; then\n'
                '  echo "simulated rollback failure" >&2\n  exit 1\nfi\n'
                'exec /usr/bin/defaults "$@"'))
        wrapper.chmod(0o700)
        self.executable = str(wrapper)

    def test_accepts_integer_boundaries(self):
        for text, expected in [("0", "0"), ("3", "3"), ("32", "32"), ("03", "3")]:
            with self.subTest(text=text):
                self.assertEqual(self.call("validate", text).stdout.strip(), expected)

    def test_invalid_input_never_changes_settings(self):
        self.write(SPACING, "int", 8)
        self.write(PADDING, "int", 10)
        sentinel = Path(self.scratch.name) / "injected"
        for text in ["", "-1", "33", "3.0", "three", " 3 ", "3\n", "3e0",
                     f"3; touch '{sentinel}'", "9" * 100]:
            with self.subTest(text=text):
                self.assertNotEqual(self.call("apply", text, check=False).returncode, 0)
                self.assertEqual(self.value(SPACING), "8")
                self.assertEqual(self.value(PADDING), "10")
        self.assertFalse(sentinel.exists())

    def test_apply_sets_both_keys_as_integers(self):
        self.call("apply", "3")
        for key in (SPACING, PADDING):
            self.assertEqual(self.call("read", key).stdout.strip(), "integer:3")

    def test_restore_removes_overrides_and_is_idempotent(self):
        self.write(SPACING, "int", 3)
        self.write(PADDING, "int", 3)
        self.call("restore")
        self.call("restore")
        self.assertIsNone(self.value(SPACING))
        self.assertIsNone(self.value(PADDING))

    def test_apply_and_restore_preserve_unrelated_preferences(self):
        self.write("OtherSetting", "string", "keep me")
        self.call("apply", "0")
        self.assertEqual(self.value("OtherSetting"), "keep me")
        self.call("restore")
        self.assertEqual(self.value("OtherSetting"), "keep me")

    def test_partial_apply_recovers_values_and_types(self):
        self.write(SPACING, "string", "original 'quoted' value\nsecond line")
        self.write(PADDING, "float", "4.5")
        self.fail_defaults()
        result = self.call("apply", "3", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("restored", result.stderr.lower())
        self.assertEqual(self.call("read", SPACING).stdout.rstrip("\n"),
                         "string:original 'quoted' value\nsecond line")
        self.assertEqual(self.call("read", PADDING).stdout.strip(), "float:4.5")

    def test_partial_apply_recovers_missing_keys(self):
        self.fail_defaults()
        result = self.call("apply", "3", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(self.value(SPACING))
        self.assertIsNone(self.value(PADDING))

    def test_partial_restore_recovers_original_values(self):
        self.write(SPACING, "int", 7)
        self.write(PADDING, "bool", "true")
        self.fail_defaults(operation="delete")
        self.assertNotEqual(self.call("restore", check=False).returncode, 0)
        self.assertEqual(self.call("read", SPACING).stdout.strip(), "integer:7")
        self.assertEqual(self.call("read", PADDING).stdout.strip(), "boolean:1")

    def test_rollback_preserves_compound_preference_types(self):
        for arguments, expected_type in [
            (("-array", "first", "second"), "array"),
            (("-dict", "original", "value"), "dictionary"),
            (("-data", "0102ff"), "data"),
        ]:
            with self.subTest(kind=expected_type):
                self.defaults("write", self.domain, SPACING, *arguments)
                original = self.value(SPACING)
                self.fail_defaults()
                self.assertNotEqual(self.call("apply", "3", check=False).returncode, 0)
                self.assertEqual(self.value(SPACING), original)
                self.assertIn(expected_type, self.defaults("read-type", self.domain, SPACING).stdout)
                (Path(self.scratch.name) / "already failed").unlink(missing_ok=True)

    def test_failed_rollback_is_reported(self):
        self.write(SPACING, "int", 8)
        self.write(PADDING, "int", 10)
        self.fail_defaults(persistent=True)
        result = self.call("apply", "3", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rollback", result.stderr.lower())
        self.assertNotIn("previous settings were restored", result.stderr.lower())

    def test_rollback_preserves_types_inside_arrays(self):
        self.defaults("write", self.domain, SPACING, "-array", "-int", "2", "-bool", "true")
        self.fail_defaults()
        self.assertNotEqual(self.call("apply", "3", check=False).returncode, 0)
        restored = plistlib.loads(self.defaults("export", self.domain, "-").stdout.encode())[SPACING]
        self.assertEqual(restored, [2, True])
        self.assertIs(type(restored[0]), int)
        self.assertIs(type(restored[1]), bool)

    def test_rollback_preserves_nested_dictionary_types(self):
        expected = {"values": [2, True, 1.5, b"\x01\x02"],
                    "nested": {"count": 4, "enabled": False}}
        encoded = plistlib.dumps(expected).decode()
        self.defaults("write", self.domain, SPACING, encoded)
        self.fail_defaults()
        self.assertNotEqual(self.call("apply", "3", check=False).returncode, 0)
        restored = plistlib.loads(self.defaults("export", self.domain, "-").stdout.encode())[SPACING]
        self.assertEqual(restored, expected)
        self.assertIs(type(restored["values"][1]), bool)
        self.assertIs(type(restored["values"][2]), float)
        self.assertIs(type(restored["nested"]["count"]), int)

    def test_read_failures_are_not_treated_as_missing_values(self):
        wrapper = Path(self.scratch.name) / "unreadable defaults"
        wrapper.write_text('#!/bin/bash\necho "permission denied" >&2\nexit 1\n')
        wrapper.chmod(0o700)
        self.executable = str(wrapper)
        result = self.call("apply", "3", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("permission denied", result.stderr.lower())
        self.assertIsNone(self.value(SPACING))


if __name__ == "__main__":
    unittest.main()
