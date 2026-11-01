"""Run installer source and launcher setup in disposable homes and Git repos."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ShellInstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="shell-install-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "user home"
        self.home.mkdir()
        self.source = self.base / "remote"
        self.target = self.home / "source shell"
        self.bin = self.home / ".local/bin"
        self.env = dict(os.environ, HOME=str(self.home),
                        REBOS_SHELL_REPO_URL=str(self.source),
                        REBOS_SHELL_INSTALL_PATH=str(self.target),
                        REBOS_SHELL_BIN_DIR=str(self.bin),
                        XDG_CONFIG_HOME=str(self.home / ".config"),
                        XDG_STATE_HOME=str(self.home / ".local/state"),
                        XDG_DATA_HOME=str(self.home / ".local/share"),
                        XDG_CACHE_HOME=str(self.home / ".cache"))
        self.git("init", "-b", "release", self.source)
        (self.source / "config").mkdir()
        (self.source / "config/Config.qml").write_text("config code")
        (self.source / "shell.qml").write_text("initial shell")
        cli = self.source / "cli.sh"
        cli.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@"\n')
        cli.chmod(0o755)
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *map(str, args)], stderr=subprocess.DEVNULL)

    def commit(self):
        self.git("-C", self.source, "add", "-A")
        self.git("-C", self.source, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "-m", "fixture")

    def run_setup(self, action):
        return subprocess.run(["bash", "-c", 'source "$1"; DISTRO=arch; ' + action,
                               "installer-test", str(ROOT / "install.sh")], env=self.env,
                              capture_output=True, text=True)

    def test_clone_follows_remote_default_branch(self):
        result = self.run_setup("setup_repo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("-C", self.target, "branch", "--show-current").strip(), b"release")

    def test_existing_non_checkout_is_preserved(self):
        self.target.mkdir()
        keep = self.target / "personal"
        keep.write_text("keep me")
        result = self.run_setup("setup_repo")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(keep.read_text(), "keep me")

    def test_update_backs_up_local_changes_on_non_main_default(self):
        self.assertEqual(self.run_setup("setup_repo").returncode, 0)
        (self.target / "shell.qml").write_text("local edits")
        (self.source / "shell.qml").write_text("new shell")
        self.commit()
        result = self.run_setup("setup_repo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "shell.qml").read_text(), "new shell")
        backup = next((self.home / ".local/state/rebos_shell/backups").glob("update-*"))
        self.assertEqual((backup / "files/shell.qml").read_text(), "local edits")

    def test_user_launcher_preserves_arguments_and_handles_spaces(self):
        self.assertEqual(self.run_setup("setup_repo; setup_launcher").returncode, 0)
        result = subprocess.run([str(self.bin / "rebos_shell"), "run", "two words", "literal $value"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["run", "two words", "literal $value"])
        entry = self.home / ".local/share/applications/rebos-shell-settings.desktop"
        self.assertIn(f'Exec="{self.bin}/rebos_shell" run settings', entry.read_text())

    def test_linked_launcher_is_preserved(self):
        self.bin.mkdir(parents=True)
        external = self.base / "external"
        external.write_text("personal launcher")
        (self.bin / "rebos_shell").symlink_to(external)
        result = self.run_setup("setup_launcher")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.bin / "rebos_shell").is_symlink())
        self.assertEqual(external.read_text(), "personal launcher")

    def test_dependency_filter_accepts_unmapped_packages_under_strict_mode(self):
        result = self.run_setup("filter_packages not-a-mapped-package")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "not-a-mapped-package")


if __name__ == "__main__":
    unittest.main()
