#!/usr/bin/env python3
"""Pair through BlueZ's default desktop agent so PIN prompts remain visible."""
import json
import re
import sys

from gi.repository import Gio, GLib


def pair(address, system_bus, session_bus):
    if not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", address):
        raise ValueError("Invalid Bluetooth device address")
    # Activate the installed desktop agent before asking BlueZ to pair.
    session_bus.call_sync(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        "StartServiceByName", GLib.Variant("(su)", ("org.blueman.Applet", 0)),
        None, Gio.DBusCallFlags.NONE, 10000, None,
    )
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
        try:
            system_bus.call_sync(
                "org.bluez", path, "org.bluez.Device1", "Pair", None, None,
                Gio.DBusCallFlags.NONE, 90000, None,
            )
        except GLib.Error as error:
            if "Timeout" in str(error) or "timed out" in str(error).lower():
                try:
                    system_bus.call_sync(
                        "org.bluez", path, "org.bluez.Device1", "CancelPairing",
                        None, None, Gio.DBusCallFlags.NONE, 5000, None,
                    )
                except GLib.Error:
                    pass
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
