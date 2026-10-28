"""Check default-agent pairing without changing any host Bluetooth devices."""
import importlib.util
from pathlib import Path
import unittest

from gi.repository import GLib

spec = importlib.util.spec_from_file_location(
    "bluetooth_pair", Path(__file__).resolve().parents[2] / "scripts/bluetooth_pair.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
ADDRESS = "AA:BB:CC:DD:EE:FF"
DEVICE = "/org/bluez/hci2/dev_AA_BB_CC_DD_EE_FF"


class Bus:
    def __init__(self, objects=None, fail_pair=False):
        self.objects = objects or {}
        self.calls = []
        self.fail_pair = fail_pair

    def call_sync(self, *args):
        self.calls.append(args)
        if args[3] == "GetManagedObjects":
            return GLib.Variant("(a{oa{sa{sv}}})", (self.objects,))
        if args[3] == "Pair" and self.fail_pair:
            raise GLib.Error("Pairing timed out")


class PairTest(unittest.TestCase):
    def device_bus(self, paired=False, fail=False):
        return Bus({DEVICE: {"org.bluez.Device1": {
            "Address": GLib.Variant("s", ADDRESS),
            "Paired": GLib.Variant("b", paired),
        }}}, fail)

    def test_default_agent_and_adapter_resolution(self):
        system, session = self.device_bus(), Bus()
        helper.pair(ADDRESS.lower(), system, session)
        self.assertEqual(session.calls[0][3], "StartServiceByName")
        self.assertEqual(system.calls[-1][1:4], (DEVICE, "org.bluez.Device1", "Pair"))
        self.assertFalse(any(call[3] == "RegisterAgent" for call in system.calls))

    def test_paired_device_not_paired_again(self):
        system = self.device_bus(paired=True)
        helper.pair(ADDRESS, system, Bus())
        self.assertEqual([call[3] for call in system.calls], ["GetManagedObjects"])

    def test_missing_device_and_invalid_address(self):
        with self.assertRaisesRegex(ValueError, "no longer available"):
            helper.pair(ADDRESS, Bus(), Bus())
        system = Bus()
        with self.assertRaisesRegex(ValueError, "Invalid"):
            helper.pair("bad", system, Bus())
        self.assertFalse(system.calls)

    def test_timeout_cancels_pairing(self):
        system = self.device_bus(fail=True)
        with self.assertRaises(GLib.Error):
            helper.pair(ADDRESS, system, Bus())
        self.assertEqual(system.calls[-1][3], "CancelPairing")


if __name__ == "__main__":
    unittest.main()
