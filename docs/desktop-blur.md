# Desktop blur

Settings → Appearance → Blur offers four saved choices:

- **Lighter glass**: two blur passes, offset 2, on apps and shell panels.
- **Shell panels only**: the original three-pass blur on shaped shell surfaces;
  app windows, their popups and other layer clients are unblurred.
- **Blur off**: disables blur for all window, popup and layer surfaces.
- **Full glass**: the original three passes, offset 3, across apps and shell panels.

Transparency and app colors remain controlled by the existing theme settings.
The initial choice is Full glass, preserving the previous appearance.

`Config.performance.desktopBlur` persists in performance.json. `DesktopBlur.qml`
initializes with the shell and regenerates `~/.cache/rebos_shell/niri-blur.kdl`
after configuration loading and on selection changes. The main Niri config
includes this file after its profile and window rules. The helper validates
each generated fragment with Niri before replacing the previous file atomically;
failures retain the previous file and appear in Settings. Rapid selections are
coalesced, and the latest choice is reapplied after any in-flight operation.

Full glass and Lighter glass leave the profile's shaped surface policy intact.
Shell panels only excludes the rebos_shell namespaces from its layer
override, preserving client blur regions rather than forcing full-screen blur.
Switching back rewrites the entire generated fragment, removing previous
disabling rules. Niri and Quickshell use native hot reload; no manual restart.

Verification: `tests/integration/test_desktop_blur.py` exercises real QML clicks,
exclusive selection, all four generated modes, rapid updates, persistence in a
fresh process, and preservation of the last good file when validation fails.
The Settings layout test includes the Blur navigation card. Existing background
blur and shell motion checks also pass. Live preset GPU measurements were
inconclusive because playback/activity changed during the sweep; do not use
those samples as a fixed-content performance comparison.
