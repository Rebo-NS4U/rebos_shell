#!/usr/bin/env python3
from pathlib import Path
import json
import re
import tempfile
import unittest

from window_rules import listing, update, render_rule, delete_existing


class WindowRulesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rebos_shell-rule-test-")
        self.root = Path(self.temp.name)
        (self.root / "niri").mkdir()
        self.original = 'window-rule {\n match app-id="existing"\n opacity 0.8\n}\n'
        (self.root / "niri/config.kdl").write_text(self.original)
        self.rule = {"name": "Kitty", "appId": "kitty", "floating": "true", "radius": "12"}

    def tearDown(self):
        self.temp.cleanup()

    def save(self, rule=None):
        return update({"op": "save", "rule": rule or self.rule,
                       "fingerprint": listing(self.root)["fingerprint"]}, self.root)

    def test_create_edit_disable_delete(self):
        created = self.save()
        self.assertEqual(len(created["rules"]), 2)
        rule = dict(created["rules"][0], opacity="0.9")
        edited = self.save(rule)
        self.assertIn("opacity 0.9", edited["rules"][0]["body"])
        self.save(dict(edited["rules"][0], enabled=False))
        path = self.root / "niri/rebos_shell-window-rules.kdl"
        self.assertNotIn("window-rule {", path.read_text())
        current = listing(self.root)
        removed = update({"op": "delete", "id": rule["id"], "fingerprint": current["fingerprint"]}, self.root)
        self.assertEqual(len(removed["rules"]), 1)
        self.assertEqual((self.root / "niri/config.kdl").read_text(), self.original)

    def test_global_rounding_is_persistent_clipped_and_last(self):
        created = self.save()
        rounded = update({"op": "rounding", "radius": 16, "fingerprint": created["fingerprint"]}, self.root)
        self.assertEqual(rounded["rounding"], 16)
        self.assertEqual(len(rounded["rules"]), len(created["rules"]))
        path = self.root / "niri/rebos_shell-window-rules.kdl"
        text = path.read_text()
        self.assertIn("clip-to-geometry true", text)
        self.assertIn("popups { geometry-corner-radius 16.0; }", text)
        self.assertTrue(text.rindex("geometry-corner-radius 16.0") > text.index("geometry-corner-radius 12.0"))
        self.save(dict(self.rule, appId="another", radius="24"))
        self.assertTrue(path.read_text().rindex("geometry-corner-radius 16.0") > path.read_text().index("geometry-corner-radius 24.0"))
        current = listing(self.root)
        update({"op": "rounding", "radius": 0, "fingerprint": current["fingerprint"]}, self.root)
        self.assertEqual(listing(self.root)["rounding"], 0)
        self.assertEqual((self.root / "niri/config.kdl").read_text(), self.original)

    def test_global_rounding_rejects_invalid_values_without_writes(self):
        for radius in [-1, 101, 1.5, True, "16", None]:
            with self.assertRaisesRegex(ValueError, "whole number"):
                update({"op": "rounding", "radius": radius, "fingerprint": listing(self.root)["fingerprint"]}, self.root)
        self.assertFalse((self.root / "niri/rebos_shell-window-rules.kdl").exists())

    def test_literal_match_escapes_regex_characters(self):
        result = self.save(dict(self.rule, appId="org.example.App", title="A (test)"))
        body = result["rules"][0]["body"]
        expression = json.loads(re.search(r'app-id=("(?:\\.|[^"\\])*")', body).group(1))
        self.assertIsNotNone(re.fullmatch(expression, "org.example.App"))
        self.assertIsNone(re.fullmatch(expression, "orgXexampleYApp"))


    def test_stale_write_is_rejected(self):
        stale = listing(self.root)["fingerprint"]
        self.save()
        with self.assertRaisesRegex(ValueError, "rules changed"):
            update({"op": "save", "fingerprint": stale, "rule": self.rule}, self.root)

    def test_invalid_regex_does_not_create_file(self):
        with self.assertRaisesRegex(ValueError, "Niri rejected"):
            self.save(dict(self.rule, appId="[", regex=True))
        self.assertFalse((self.root / "niri/rebos_shell-window-rules.kdl").exists())

    def test_no_global_unmatched_rule(self):
        with self.assertRaisesRegex(ValueError, "app ID or a title"):
            render_rule({"floating": "true"})

    def test_numeric_and_empty_settings_validation(self):
        for field, value in [("opacity", "nan"), ("opacity", "1.1"), ("radius", "-1"), ("width", "101")]:
            with self.assertRaises(ValueError):
                self.save(dict(self.rule, **{field: value}))
        with self.assertRaisesRegex(ValueError, "at least one"):
            render_rule({"appId": "kitty"})

    def test_manual_changes_are_not_overwritten(self):
        self.save()
        path = self.root / "niri/rebos_shell-window-rules.kdl"
        path.write_text(path.read_text().replace("geometry-corner-radius 12.0", "geometry-corner-radius 16.0"))
        with self.assertRaisesRegex(ValueError, "changed outside"):
            listing(self.root)
        self.assertIn("16.0", path.read_text())

    def test_disabled_rules_retain_settings(self):
        created = self.save()
        rule = dict(created["rules"][0], enabled=False)
        self.save(rule)
        self.assertFalse(listing(self.root)["rules"][0]["enabled"])
        enabled = self.save(dict(rule, enabled=True))
        self.assertIn("geometry-corner-radius 12.0", enabled["rules"][0]["body"])

    def test_delete_existing_rule_preserves_other_rules_and_symlink(self):
        config = self.root / "niri/config.kdl"
        profile = self.root / "niri/profile.kdl"
        original = self.original + '// Keep this second rule.\nwindow-rule {\n match app-id="other"\n open-floating true\n}\n'
        profile.write_text(original)
        config.unlink()
        config.symlink_to(profile)
        selected = listing(self.root)["rules"][0]
        result = delete_existing({"binding": selected}, self.root)
        self.assertTrue(config.is_symlink())
        self.assertNotIn('app-id="existing"', profile.read_text())
        self.assertIn('// Keep this second rule.\nwindow-rule', profile.read_text())
        self.assertEqual(len(result["rules"]), 1)
        backups = list(profile.parent.glob('.window-rules-backup-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)

    def test_delete_stale_existing_rule_is_rejected(self):
        selected = listing(self.root)["rules"][0]
        config = self.root / "niri/config.kdl"
        config.write_text(self.original + '// external change\n')
        with self.assertRaisesRegex(ValueError, "rule changed"):
            delete_existing({"binding": selected}, self.root)
        self.assertIn('app-id="existing"', config.read_text())


if __name__ == "__main__":
    unittest.main()
