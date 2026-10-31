"""Exercise the standalone updater against real disposable Git repositories."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


UPDATER = Path(__file__).resolve().parents[2] / "update.sh"


class ShellUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote"
        self.target = self.root / "installed shell"
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / ".config"),
                        XDG_STATE_HOME=str(self.home / ".local/state"),
                        XDG_DATA_HOME=str(self.home / ".local/share"),
                        XDG_CACHE_HOME=str(self.home / ".cache"),
                        GIT_AUTHOR_NAME="Updater Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Updater Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.git("init", "-b", "release", self.remote)
        for name, content in {"shell.qml": "old shell", "cli.sh": "old cli",
                              "config/Config.qml": "configuration code", "obsolete": "old feature",
                              "unchanged": "keep mtime"}.items():
            self.write(self.remote, name, content)
        self.commit()
        self.git("clone", self.remote, self.target)
        self.preferences = self.home / ".config/rebos_shell/config/bar.json"
        self.preferences.parent.mkdir(parents=True)
        self.preferences.write_text('{"custom": true}\n')
        self.write(self.remote, "shell.qml", "new shell")
        self.write(self.remote, "new-feature", "new feature")
        (self.remote / "obsolete").unlink()
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *map(str, args)], env=self.env, stderr=subprocess.DEVNULL)

    def write(self, root, name, content):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("-C", self.remote, "add", "-A")
        self.git("-C", self.remote, "commit", "-m", "fixture")

    def run_update(self, *args):
        return subprocess.run(["bash", str(UPDATER), "--path", str(self.target),
                               "--repo", str(self.remote), *args], env=self.env,
                              capture_output=True, text=True)

    def backups(self):
        return list((self.home / ".local/state/rebos_shell/backups").glob("update-*"))

    def test_updates_content_and_preserves_preferences_and_unrelated_files(self):
        self.write(self.target, "shell.qml", "local customization")
        self.write(self.target, "personal-note", "personal")
        before = (self.target / "unchanged").stat().st_mtime_ns
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "shell.qml").read_text(), "new shell")
        self.assertEqual((self.target / "new-feature").read_text(), "new feature")
        self.assertFalse((self.target / "obsolete").exists())
        self.assertEqual((self.target / "personal-note").read_text(), "personal")
        self.assertEqual(self.preferences.read_text(), '{"custom": true}\n')
        self.assertEqual((self.target / "unchanged").stat().st_mtime_ns, before)
        backup = self.backups()[0]
        self.assertEqual((backup / "files/shell.qml").read_text(), "local customization")
        self.assertEqual((backup / "files/obsolete").read_text(), "old feature")
        self.assertFalse((backup / "files/unchanged").exists())
        manifest = json.loads((backup / "manifest.json").read_text())
        self.assertIn("new-feature", manifest["added"])
        self.assertEqual(self.git("-C", self.target, "rev-parse", "HEAD"),
                         self.git("-C", self.remote, "rev-parse", "HEAD"))
        self.assertEqual(self.git("-C", self.target, "diff", "HEAD"), b"")
        self.assertEqual(self.run_update().returncode, 0)
        self.assertEqual(len(self.backups()), 1)

    def test_preview_does_not_write_shell_or_backup(self):
        old = self.git("-C", self.target, "rev-parse", "HEAD")
        result = self.run_update("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "shell.qml").read_text(), "old shell")
        self.assertEqual(self.git("-C", self.target, "rev-parse", "HEAD"), old)
        self.assertEqual(self.backups(), [])

    def test_backs_up_untracked_collision_and_staged_edit(self):
        self.write(self.target, "new-feature", "personal collision")
        self.write(self.target, "cli.sh", "staged customization")
        self.git("-C", self.target, "add", "cli.sh")
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        backup = self.backups()[0]
        self.assertEqual((backup / "files/new-feature").read_text(), "personal collision")
        self.assertEqual((backup / "files/cli.sh").read_text(), "staged customization")
        self.assertTrue((backup / "git-index").is_file())

    def test_does_not_follow_local_symlinks(self):
        external = self.root / "external"
        external.write_text("personal data")
        (self.target / "shell.qml").unlink()
        (self.target / "shell.qml").symlink_to(external)
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(external.read_text(), "personal data")
        self.assertTrue((self.backups()[0] / "files/shell.qml").is_symlink())

    def test_refuses_conflicting_directory_before_changing_files(self):
        (self.target / "shell.qml").unlink()
        (self.target / "shell.qml").mkdir()
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.target / "obsolete").exists())
        self.assertEqual(self.backups(), [])

    def test_fetch_failure_does_not_change_shell(self):
        result = self.run_update("--branch", "no-such-branch")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "shell.qml").read_text(), "old shell")
        self.assertEqual(self.backups(), [])


if __name__ == "__main__":
    unittest.main()
