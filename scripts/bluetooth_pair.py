#!/usr/bin/env python3
"""Stream keyboard pairing codes to the shell; use the desktop agent otherwise."""
import json
import re
import secrets
import sys

from gi.repository import Gio, GLib


AGENT_PATH = "/org/rebos/KeyboardPairing"
AGENT_XML = """
<node><interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="Cancel"/>
  <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
  <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
  <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
  <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>
"""


def emit(event):
    print(json.dumps(event), flush=True)


def is_keyboard(device):
    return (device.get("Icon") == "input-keyboard"
            or (int(device.get("Class", 0)) & 0x1F40) == 0x0540
            or int(device.get("Appearance", 0)) == 0x03C1)


class KeyboardAgent:
    def __init__(self, path, output=emit):
        self.path = path
        self.output = output
        self.pin = f"{secrets.randbelow(1000000):06d}"

    def handle(self, connection, sender, object_path, interface, method, parameters, invocation):
        args = parameters.unpack()
        if args and args[0] != self.path:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Unexpected pairing device")
            return
        if method in ("Release", "Cancel"):
            self.output({"event": "clear-code"})
        elif method in ("DisplayPasskey", "DisplayPinCode", "RequestPinCode", "RequestPasskey"):
            code = f"{args[1]:06d}" if method == "DisplayPasskey" else args[1] if method == "DisplayPinCode" else self.pin
            self.output({"event": "keyboard-code", "code": code,
                         "entered": args[2] if method == "DisplayPasskey" else 0})
            if method == "RequestPinCode":
                invocation.return_value(GLib.Variant("(s)", (code,)))
                return
            if method == "RequestPasskey":
                invocation.return_value(GLib.Variant("(u)", (int(code),)))
                return
        elif method not in ("RequestAuthorization", "AuthorizeService"):
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Keyboard requires an unsupported confirmation method")
            return
        invocation.return_value(None)


def pair_keyboard(system_bus, path):
    agent = KeyboardAgent(path)
    interface = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
    registration = system_bus.register_object(AGENT_PATH, interface, agent.handle, None, None)
    registered = False
    loop = GLib.MainLoop()
    errors = []

    def paired(connection, result, _data):
        try:
            connection.call_finish(result)
        except GLib.Error as error:
            errors.append(error)
        finally:
            loop.quit()

    try:
        system_bus.call_sync(
            "org.bluez", "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
            GLib.Variant("(os)", (AGENT_PATH, "DisplayOnly")), None,
            Gio.DBusCallFlags.NONE, 10000, None,
        )
        registered = True
        # Async Pair keeps the main loop available for Agent1 callbacks.
        system_bus.call("org.bluez", path, "org.bluez.Device1", "Pair", None, None,
                        Gio.DBusCallFlags.NONE, 90000, None, paired, None)
        loop.run()
        if errors:
            cancel_pairing(system_bus, path)
            raise errors[0]
    finally:
        if registered:
            try:
                system_bus.call_sync(
                    "org.bluez", "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent",
                    GLib.Variant("(o)", (AGENT_PATH,)), None,
                    Gio.DBusCallFlags.NONE, 5000, None,
                )
            except GLib.Error:
                pass
        system_bus.unregister_object(registration)
        emit({"event": "clear-code"})


def cancel_pairing(system_bus, path):
    try:
        system_bus.call_sync("org.bluez", path, "org.bluez.Device1", "CancelPairing",
                             None, None, Gio.DBusCallFlags.NONE, 5000, None)
    except GLib.Error:
        pass


def pair(address, system_bus, session_bus):
    if not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", address):
        raise ValueError("Invalid Bluetooth device address")
    objects = system_bus.call_sync(
        "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
        None, None, Gio.DBusCallFlags.NONE, 10000, None,
    ).unpack()[0]
    for path, interfaces in objects.items():
        device = interfaces.get("org.bluez.Device1", {})
        if device.get("Address", "").upper() != address.upper():
            continue
        if device.get("Paired", False):
            return
        if is_keyboard(device):
            pair_keyboard(system_bus, path)
            return
        # Other devices retain the existing desktop confirmation/input dialogs.
        session_bus.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "StartServiceByName", GLib.Variant("(su)", ("org.blueman.Applet", 0)),
            None, Gio.DBusCallFlags.NONE, 10000, None,
        )
        try:
            system_bus.call_sync(
                "org.bluez", path, "org.bluez.Device1", "Pair", None, None,
                Gio.DBusCallFlags.NONE, 90000, None,
            )
        except GLib.Error as error:
            if "Timeout" in str(error) or "timed out" in str(error).lower():
                cancel_pairing(system_bus, path)
            raise
        return
    raise ValueError("Device is no longer available. Put it in pairing mode and scan again.")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Choose a Bluetooth device to pair")
        pair(sys.argv[1], Gio.bus_get_sync(Gio.BusType.SYSTEM),
             Gio.bus_get_sync(Gio.BusType.SESSION))
        print(json.dumps({"paired": True}))
    except (GLib.Error, ValueError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        sys.exit(1)
