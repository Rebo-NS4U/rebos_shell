# Automatic app color refresh

Wallpaper generation calls `Colors.refreshApps()` only after Matugen succeeds.
The shared palette watcher also handles presets and Appearance changes. The CLI
wallpaper helper relies on this completion path rather than exporting the old
palette while Matugen is still working.

`Colors` waits until all six serialized exporters have finished successfully,
then runs `scripts/reload_theme_apps.py`. Rapid selections coalesce while writers
are busy. A failed exporter prevents app restarts with incomplete theme files.

- Kitty uses its existing SIGUSR1 reload; GTK uses its existing theme notification.
- Qt5ct/Qt6ct settings timestamps change when their palette changes; KDE apps also
  receive the palette notification over D-Bus.
- btop receives SIGUSR2 to reload its config and theme. This handler is defined in
  [btop.cpp](https://github.com/aristocratos/btop/blob/main/src/btop.cpp).
- Fish refreshes at the next prompt, Neovim polls the effective palette, VS Code
  watches its settings, and Vesktop's generated stylesheet uses its existing theme
  loader. These existing consumers retain their own reload behavior.
- Zen and Spotify restart when their generated theme files change, as explicitly
  selected by the user on 2026-10-27. Spicetify finishes refreshing installed assets
  before Spotify restarts. Zen launches with `--restore-last-session`.

Only running native Zen/Spotify processes owned by the current user are restarted.
Renderer children and closed apps are excluded. There is no force-kill: an app
that does not exit within ten seconds remains running and is eligible for retry.
Flatpak browser/client restarts are not implemented. Editors and document viewers
are never terminated by this helper. Browser session restoration and each app's
visual result require verification with those apps running.

Content fingerprints persist in `~/.cache/rebos_shell/app-theme-reload.json`;
the first invocation establishes a baseline. Identical exports and shell hot
reloads do not cause repeat restarts. The latest result is recorded in
`app-theme-reload-status.json` in the same directory.

Validation: `tests/integration/test_unified_app_theme.py` exercises real QML palette
replacement and export-before-refresh ordering in an isolated home. External app
actions are replaced by an assertion script. `test_theme_app_reload.py` covers
changed-file dispatch, repeat suppression, closed apps, retries and replacement of
a real disposable process. No shell/compositor restart is required.
