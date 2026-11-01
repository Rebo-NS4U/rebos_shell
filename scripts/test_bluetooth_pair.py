"""Verify keyboard agent codes, callbacks and cleanup without pairing hardware."""
import contextlib
import io
import unittest
from unittest.mock import Mock, patch

from gi.repository import GLib
import bluetooth_pair as pairing


DEVICE = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"


class KeyboardPairingTests(unittest.TestCase):
    def invoke(self, method, signature, values, path=DEVICE):
        invocation = Mock()
        agent = pairing.KeyboardAgent(DEVICE, self.events.append)
        agent.pin = "001234"
        agent.handle(None, None, None, None, method,
                     GLib.Variant(signature, values), invocation)
        return invocation

    def setUp(self):
        self.events = []

    def test_detects_keyboard_metadata(self):
        for device in ({"Icon": "input-keyboard"}, {"Class": 0x2540},
                       {"Class": 0x05C0}, {"Appearance": 0x03C1}):
            self.assertTrue(pairing.is_keyboard(device))
        for device in ({}, {"Icon": "input-mouse", "Class": 0x2580},
                       {"Icon": "audio-headset"}):
            self.assertFalse(pairing.is_keyboard(device))

    def test_passkey_preserves_leading_zeros_and_progress(self):
        for entered in (0, 2, 6):
            call = self.invoke("DisplayPasskey", "(ouq)", (DEVICE, 1234, entered))
            call.return_value.assert_called_once_with(None)
            self.assertEqual(self.events[-1], {
                "event": "keyboard-code", "code": "001234", "entered": entered})

    def test_legacy_pin_is_displayed_and_returned(self):
        call = self.invoke("RequestPinCode", "(o)", (DEVICE,))
        self.assertEqual(call.return_value.call_args.args[0].unpack(), ("001234",))
        self.assertEqual(self.events[-1]["code"], "001234")
        self.invoke("DisplayPinCode", "(os)", (DEVICE, "000042"))
        self.assertEqual(self.events[-1]["code"], "000042")

    def test_requested_passkey_uses_numeric_reply(self):
        call = self.invoke("RequestPasskey", "(o)", (DEVICE,))
        self.assertEqual(call.return_value.call_args.args[0].unpack(), (1234,))
        self.assertEqual(self.events[-1]["code"], "001234")

    def test_unrelated_device_and_confirmation_are_rejected(self):
        call = self.invoke("DisplayPasskey", "(ouq)", (DEVICE + "_OTHER", 1234, 0))
        call.return_dbus_error.assert_called_once()
        self.assertEqual(self.events, [])
        call = self.invoke("RequestConfirmation", "(ou)", (DEVICE, 1234))
        call.return_dbus_error.assert_called_once()

    def test_cancel_clears_prompt(self):
        self.invoke("Cancel", "()", ())
        self.assertEqual(self.events, [{"event": "clear-code"}])

    def test_async_pair_dispatches_agent_and_unregisters(self):
        for fail in (False, True):
            bus = Mock()
            bus.register_object.return_value = 17
            if fail:
                bus.call_finish.side_effect = GLib.Error("Pairing failed")

            def start(*args):
                def complete():
                    handler = bus.register_object.call_args.args[2]
                    handler(bus, None, None, None, "DisplayPasskey",
                            GLib.Variant("(ouq)", (DEVICE, 42, 1)), Mock())
                    args[-2](bus, object(), None)
                    return False
                GLib.idle_add(complete)

            bus.call.side_effect = start
            with contextlib.redirect_stdout(io.StringIO()) as output:
                if fail:
                    with self.assertRaises(GLib.Error):
                        pairing.pair_keyboard(bus, DEVICE)
                else:
                    pairing.pair_keyboard(bus, DEVICE)
            self.assertIn('"code": "000042"', output.getvalue())
            self.assertIn('"event": "clear-code"', output.getvalue())
            bus.unregister_object.assert_called_once_with(17)
            methods = [call.args[3] for call in bus.call_sync.call_args_list]
            self.assertEqual(methods[-1], "UnregisterAgent")
            self.assertEqual("CancelPairing" in methods, fail)

    def test_existing_pair_and_non_keyboard_keep_their_paths(self):
        for properties in ({"Paired": True}, {"Icon": "audio-headset"}):
            bus, session = Mock(), Mock()
            bus.call_sync.return_value.unpack.return_value = ({DEVICE: {
                "org.bluez.Device1": {"Address": "AA:BB:CC:DD:EE:FF", **properties}
            }},)
            with patch.object(pairing, "pair_keyboard") as keyboard:
                pairing.pair("AA:BB:CC:DD:EE:FF", bus, session)
                keyboard.assert_not_called()
            self.assertEqual(session.call_sync.called, not properties.get("Paired", False))


if __name__ == "__main__":
    unittest.main()
