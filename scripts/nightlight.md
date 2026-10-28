# Night Light

`NightLightService.qml` controls the display through the D-Bus API provided by
[wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs).
The backend is installed in the user's bin directory:

```sh
cargo install wl-gammarelay-rs --locked --root "$HOME/.local"
ln -s ~/.config/quickshell/scripts/rebos-nightlight.service ~/.config/systemd/user/rebos-nightlight.service
systemctl --user daemon-reload
```

The installed D-Bus activation descriptor is
`~/.local/share/dbus-1/services/rs.wl-gammarelay.service`:

```ini
[D-BUS Service]
Name=rs.wl-gammarelay
Exec=/absolute/path/to/.local/bin/wl-gammarelay-rs
SystemdService=rebos-nightlight.service
```

Use the actual home path for `Exec`; D-Bus does not expand shell variables.
After adding the descriptor to an already running session, refresh discovery:

```sh
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
```
Niri starts the user service at login. A D-Bus request can also activate it
on demand. The service inherits the session's `WAYLAND_DISPLAY` and
`XDG_RUNTIME_DIR`; it must run within the graphical user session.

The shell restores its saved enabled state and strength after startup/reload.
Off applies 6500K while retaining the selected warm temperature. Commands are
serialized, keeping the latest queued temperature. `active` reflects confirmed
backend state; `desiredActive` handles pending toggles and strength changes.
Failed writes retain an error and do not change the confirmed temperature.

Diagnostics:

```sh
systemctl --user status rebos-nightlight.service
journalctl --user -u rebos-nightlight.service
busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature
python3 -m unittest discover -s tests/integration -p test_night_light.py -v
```

On this installation, wl-gammarelay-rs 0.3.2 acquired the laptop panel's
4096-entry gamma ramp. Live QML verification exercised 6500K → 3800K → 4500K →
6500K → 3800K. Synthetic integration tests cover restoration, latest queued
strength, disabling, failed writes, and subsequent recovery.
