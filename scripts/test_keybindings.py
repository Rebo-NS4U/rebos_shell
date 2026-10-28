#!/usr/bin/env python3
"""Exercise editing against temporary configs; never signal the desktop."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from edit_keybinding import save
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


if __name__ == "__main__":
    unittest.main()
