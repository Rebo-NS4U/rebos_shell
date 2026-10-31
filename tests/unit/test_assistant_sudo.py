"""Exercise desktop discovery and administrator approval gates without sudo."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/assistant_sudo.py"
spec = importlib.util.spec_from_file_location("assistant_sudo", SCRIPT)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class AssistantSudoTest(unittest.TestCase):
    def test_login_environment_is_allowlisted(self):
        result = subprocess.CompletedProcess([], 0,
            "WAYLAND_DISPLAY=wayland-2\nDISPLAY=:1\nPATH=/untrusted\n"
            "SUDO_ASKPASS=/untrusted\nDBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus\n")
        with patch.dict(os.environ, {"PATH": "/original"}, clear=True), \
                patch.object(helper.subprocess, "run", return_value=result):
            environment = helper.desktop_environment()
        self.assertEqual(environment["WAYLAND_DISPLAY"], "wayland-2")
        self.assertEqual(environment["DISPLAY"], ":1")
        self.assertEqual(environment["PATH"], "/original")
        self.assertNotIn("SUDO_ASKPASS", environment)

    def test_denied_bus_preserves_inherited_display(self):
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-1"}, clear=True), \
                patch.object(helper.subprocess, "run", side_effect=PermissionError):
            self.assertEqual(helper.desktop_environment()["WAYLAND_DISPLAY"], "wayland-1")

    def invoke(self, codes):
        environment = {"WAYLAND_DISPLAY": "wayland-2"}
        with patch.object(helper, "desktop_environment", return_value=environment), \
                patch.object(helper.sys, "argv", [str(SCRIPT), "--reason", "test", "--", "/usr/bin/true"]), \
                patch.object(helper.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], code) for code in codes]) as run:
            result = helper.main()
        return result, run.call_args_list

    def test_cancel_never_runs_sudo(self):
        result, calls = self.invoke([1])
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 1)

    def test_display_failure_never_runs_sudo(self):
        result, calls = self.invoke([2])
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 1)

    def test_approval_passes_display_to_sudo_and_preserves_exit_code(self):
        result, calls = self.invoke([0, 7])
        self.assertEqual(result, 7)
        self.assertEqual(calls[1].args[0], ["/usr/bin/sudo", "-A", "-k", "--", "/usr/bin/true"])
        self.assertEqual(calls[0].kwargs["env"]["WAYLAND_DISPLAY"], "wayland-2")
        self.assertEqual(calls[1].kwargs["env"]["WAYLAND_DISPLAY"], "wayland-2")


if __name__ == "__main__":
    unittest.main()
