"""Exercise display persistence with real Niri validation and isolated files."""
from pathlib import Path
import tempfile
import unittest

from display_settings import save


class DisplaySettingsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="display-settings-test-")
        self.addCleanup(temporary.cleanup)
        self.config = Path(temporary.name)
        (self.config / "niri").mkdir()
        self.path = self.config / "niri/config.kdl"
        self.original = '''output "eDP-1" {
    // Preserve manual settings and comments.
    mode "1920x1080@144.000"
    scale 1
    transform "normal"
    position x=0 y=0
    variable-refresh-rate
}
'''
        self.path.write_text(self.original)
        self.outputs = {"eDP-1": {"current_mode": 0, "modes": [
            {"width": 1920, "height": 1080, "refresh_rate": 144000}]}}
        self.request = {"name": "eDP-1", "mode": "1920x1080@144.000", "scale": 1.25,
                        "transform": "90", "x": 1920, "y": 0}

    def test_preserves_other_settings_and_backs_up(self):
        self.assertTrue(save(self.request, self.config, self.outputs)["ok"])
        text = self.path.read_text()
        self.assertIn("variable-refresh-rate", text)
        self.assertIn("// Preserve manual settings and comments.", text)
        self.assertIn("scale 1.25", text)
        self.assertEqual(text.count("scale "), 1)
        self.assertIn("position x=1920 y=0", text)
        backups = list(self.path.parent.glob(".window-rules-backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), self.original)

    def test_rejects_invalid_and_disconnected_outputs_without_writing(self):
        for key, value in (("mode", "1x1@1"), ("name", "missing"), ("scale", float("nan")),
                           ("scale", 0.1), ("transform", "invalid"), ("x", 100001)):
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    save(dict(self.request, **{key: value}), self.config, self.outputs)
                self.assertEqual(self.path.read_text(), self.original)

    def test_adds_new_output(self):
        self.path.write_text("")
        save(self.request, self.config, self.outputs)
        self.assertIn('output "eDP-1"', self.path.read_text())

    def test_rejects_ambiguous_output_configuration(self):
        self.path.write_text(self.original * 2)
        with self.assertRaises(ValueError):
            save(self.request, self.config, self.outputs)
        self.assertEqual(self.path.read_text(), self.original * 2)

    def test_updates_included_symlink_target(self):
        profile = self.path.parent / "profile.kdl"
        profile.write_text(self.original)
        link = self.path.parent / "active.kdl"
        link.symlink_to(profile)
        main = 'include "active.kdl"\n'
        self.path.write_text(main)
        save(self.request, self.config, self.outputs)
        self.assertTrue(link.is_symlink())
        self.assertIn("scale 1.25", profile.read_text())
        self.assertEqual(self.path.read_text(), main)

    def test_niri_rejects_invalid_config_without_writing(self):
        self.path.write_text(self.original + "invalid-niri-setting\n")
        with self.assertRaises(ValueError):
            save(self.request, self.config, self.outputs)
        self.assertEqual(self.path.read_text(), self.original + "invalid-niri-setting\n")


if __name__ == "__main__":
    unittest.main()
