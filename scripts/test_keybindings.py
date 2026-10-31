#!/usr/bin/env python3
"""Exercise editing against temporary configs; never signal the desktop."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from edit_keybinding import add, save
from list_keybindings import collect


class KeybindingEdits(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rebos_shell-keybinding-test-")
        self.root = Path(self.temp.name)
        (self.root / "niri").mkdir()
        (self.root / "kitty").mkdir()
        self.profile = self.root / "niri/profile.kdl"
        self.original = '// Keep comments and actions unchanged.\nbinds {\n    Mod+A hotkey-overlay-title="Launcher" { spawn "qs" "ipc" "call" "rebos_shell" "run" "launcher"; }\n    Mod+Shift+F { fullscreen-window; }\n}\n'
        self.profile.write_text(self.original)
        (self.root / "niri/config.kdl").symlink_to(self.profile)
        (self.root / "kitty/kitty.conf").write_text("map ctrl+shift+f search_scrollback\nmap ctrl+shift+c copy_to_clipboard\n")

    def tearDown(self):
        self.temp.cleanup()

    def edit(self, key, index=0):
        row = collect(self.root)["bindings"][index]
        return save({"binding": row, "key": key}, self.root)

    def test_niri_save_preserves_action_symlink_and_backup(self):
        result = self.edit("Super+Shift+A")
        self.assertTrue(result["ok"])
        self.assertTrue((self.root / "niri/config.kdl").is_symlink())
        self.assertEqual(self.profile.read_text(), self.original.replace("Mod+A", "Shift+Mod+A", 1))
        self.assertEqual(Path(result["backup"]).read_text(), self.original)

    def test_reordered_modifiers_conflict(self):
        with self.assertRaisesRegex(ValueError, "already assigned"):
            self.edit("Shift+Super+F")
        self.assertEqual(self.profile.read_text(), self.original)

    def test_invalid_niri_key_does_not_write(self):
        with self.assertRaisesRegex(ValueError, "not valid"):
            self.edit("Super+NonexistentKeyboardKey")
        self.assertEqual(self.profile.read_text(), self.original)
        self.assertFalse(list(self.profile.parent.glob(".*keybindings-backup*")))
        self.assertFalse(list(self.profile.parent.glob(".keybinding-check-*")))

    def test_stale_selection_does_not_overwrite(self):
        row = collect(self.root)["bindings"][0]
        self.profile.write_text(self.original + "// another change\n")
        with self.assertRaisesRegex(ValueError, "configuration changed"):
            save({"binding": row, "key": "Super+Shift+A"}, self.root)
        self.assertTrue(self.profile.read_text().endswith("// another change\n"))

    def test_unchanged_shortcut_does_not_write(self):
        self.assertEqual(self.edit("Super+A")["message"], "Shortcut unchanged.")
        self.assertEqual(self.profile.read_text(), self.original)

    def test_injection_is_rejected(self):
        for key in ['Super+A; quit', 'Super+A\nquit', 'Super+"A', 'Super+Ctrl+Ctrl+A']:
            with self.assertRaises(ValueError):
                self.edit(key)
        self.assertEqual(self.profile.read_text(), self.original)

    def test_kitty_save_uses_native_parser_and_lowercase_letter(self):
        native_run = subprocess.run
        def run(args, **kwargs):
            if args[0] == "pkill":
                return subprocess.CompletedProcess(args, 1)
            return native_run(args, **kwargs)
        with patch("edit_keybinding.subprocess.run", side_effect=run):
            result = self.edit("Ctrl+Alt+F", index=2)
        self.assertTrue(result["ok"])
        self.assertIn("map Alt+Ctrl+f search_scrollback", (self.root / "kitty/kitty.conf").read_text())

    def test_invalid_kitty_key_does_not_write(self):
        path = self.root / "kitty/kitty.conf"
        original = path.read_text()
        with self.assertRaisesRegex(ValueError, "not valid"):
            self.edit("Ctrl+NonexistentKeyboardKey", index=2)
        self.assertEqual(path.read_text(), original)

    def test_add_preserves_config_symlink_and_command_without_running_it(self):
        marker = self.root / "must-not-run"
        command = 'printf "%s" "hello world" > ' + str(marker)
        result = add({"key": "Super+Shift+K", "command": command,
                      "name": 'My "terminal" · launch'}, self.root)
        self.assertTrue(result["ok"])
        self.assertFalse(marker.exists())
        self.assertTrue((self.root / "niri/config.kdl").is_symlink())
        for line in self.original.splitlines():
            self.assertIn(line, self.profile.read_text().splitlines())
        self.assertEqual(Path(result["backup"]).read_text(), self.original)
        row = next(r for r in collect(self.root)["bindings"] if r["rawKey"] == "Shift+Mod+K")
        self.assertEqual(row["action"], 'My "terminal" · launch')
        self.assertTrue(row["editable"])
        self.assertTrue(save({"binding": row, "key": "Super+Shift+J"}, self.root)["ok"])

    def test_add_rejects_existing_key_in_included_profile(self):
        main = self.root / "niri/config.kdl"
        main.unlink()
        main.write_text('include "profile.kdl"\n')
        with self.assertRaisesRegex(ValueError, "already assigned"):
            add({"key": "Shift+Super+F", "command": "kitty"}, self.root)
        self.assertEqual(main.read_text(), 'include "profile.kdl"\n')

    def test_add_creates_local_binds_beside_included_profile(self):
        main = self.root / "niri/config.kdl"
        main.unlink()
        original = 'include "profile.kdl"\n// Preserve profile settings.\n'
        main.write_text(original)
        result = add({"key": "Super+K", "command": "kitty"}, self.root)
        self.assertTrue(result["ok"])
        self.assertTrue(main.read_text().startswith(original))
        self.assertEqual(self.profile.read_text(), self.original)
        rows = collect(self.root)["bindings"]
        self.assertTrue(any(row["rawKey"] == "Mod+K" and row["action"] == "Run custom command" for row in rows))

    def test_add_invalid_input_never_changes_config(self):
        for request in [
            {"key": "Super+NonexistentKeyboardKey", "command": "kitty"},
            {"key": "Super+K", "command": ""},
            {"key": "Super+K", "command": "kitty\nquit"},
            {"key": "Super+K", "command": "kitty", "name": "name\nquit"},
            {"key": "Super+K; quit", "command": "kitty"},
        ]:
            with self.assertRaises(ValueError):
                add(request, self.root)
            self.assertEqual(self.profile.read_text(), self.original)
        self.assertFalse(list(self.profile.parent.glob(".*keybindings-backup*")))
        self.assertFalse(list(self.profile.parent.glob(".keybinding-check-*")))

    def test_add_concurrent_edit_is_preserved(self):
        native_run = subprocess.run
        def run(args, **kwargs):
            result = native_run(args, **kwargs)
            self.profile.write_text(self.original + "// concurrent edit\n")
            return result
        with patch("edit_keybinding.subprocess.run", side_effect=run):
            with self.assertRaisesRegex(ValueError, "changed while saving"):
                add({"key": "Super+K", "command": "kitty"}, self.root)
        self.assertEqual(self.profile.read_text(), self.original + "// concurrent edit\n")


if __name__ == "__main__":
    unittest.main()
