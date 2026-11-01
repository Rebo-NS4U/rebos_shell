# Built-in shell functionality checks — 2026-11-01

Scope: built-in shell apps and panels. This is a functionality and regression
pass, not a release certification for every installed desktop application.

## Changes

- Added a real QML Settings-window test covering opening, user/compositor close,
  reopening, state-driven close and workspace move/focus requests. The compositor
  boundary is stubbed; the window implementation is real.
- Extended bar interaction coverage to exercise volume/mute glyph changes,
  palette propagation to all three indicators, playing animation, and stopping
  animation while paused or hidden. Audio and brightness use disposable stubs.
- Corrected three obsolete source-contract expectations for shader rendering,
  the volume icon component and direct palette references. Current behavior is
  covered by runtime assertions instead of requiring those old implementations.
- Made tooltip rendering checks wait for the enter transition and content layout
  before capture. The test now checks capture acceptance and image-save success,
  and reports its checkpoint if it times out. Three consecutive focused runs
  passed after this correction.

## Checks

- Syntax scan: all 204 production QML files passed the repository's syntax-only
  scanner. It filters parser errors and does not establish import/type validity.
- Unit discovery: 174 tests passed.
- Full integration discovery with GPU tests enabled: 73 tests passed, no skips.
- Lifecycle/adversarial discovery: 19 tests passed. These use models and fixtures.
- Installed script discovery: 37 tests passed, including six local fan-control
  tests with fake driver files and mocked module commands. Upstream script
  discovery separately passed all 31 tests.
- Bar schema: 14 checks passed. Shell style schema, migration and 184 surface
  contrast checks passed.
- The existing tier runner passed its 197 reported checks; that runner counts
  the syntax scan as six checks and does not discover the full integration suite.
- Offscreen GPU pixel tests passed for dotted and double outline shaders.
- Settings and bar runtime regressions passed independently.

The four discovery groups (174 unit, 73 integration, 19 lifecycle/adversarial,
37 installed-script tests) total 303 passing tests. The tier runner and focused
reruns overlap these groups and are not added to that total.

Reproduce the upstream checks from the repository root:

```sh
python3 -m unittest discover -s tests/unit -p 'test_*.py' -v
REBOS_GPU_RENDER_TEST=1 python3 -m unittest discover -s tests/integration -p 'test_*.py' -v
python3 -m unittest discover -s tests/e2e -p 'test_*.py' -v
python3 -m unittest discover -s scripts -p 'test_*.py' -v
node tests/schema/test_bar_config_schema.js
node tests/schema/test_shell_style_schema.js
```

Integration tests require local socket access; the opt-in render check also
requires graphics access. Initial restricted assistant tests returned
`Operation not permitted`; rerunning with the supported approval passed.

The integration suite exercises Settings tabs/search/resizing, bar pointer
actions, launcher/lazy panel lifecycle, dashboard/calendar, file shelf drops,
scratchpad persistence and failures, monitor details, taskbar, network and GPU
polling, Bluetooth actions, night light, outside clicks, theme persistence and
application exports, wallpaper conversion, assistant sessions/questions/model
selection, and rendering/layout behavior. Hardware and external services are
mocked where tests change state. Assistant lifecycle tests use temporary sockets
and disposable agents; no live assistant backend is restarted.

## Live desktop smoke checks

The running panel accepted launch commands for launcher, projects, dashboard,
system monitor, sound, microphone, Wi-Fi, Bluetooth, battery, weather, calendar,
notifications, wallpaper, file shelf and Settings. The captured panel log had no
new application exceptions or binding-loop warnings; Qt Wayland text-input focus
warnings remain. Command acceptance and clean logs alone do not prove every
rendered control works; the interaction suites provide separate coverage.

The prior Settings fix was also verified on the actual desktop through an
open-close-reopen cycle. After the functionality pass, the panel remained active
with PID 823; Niri and both assistant services were active. No Quickshell or Niri
restart was used.

## Limits

No live power-off, reboot, suspend, lock, driver reload, network reconnect,
Bluetooth pairing, volume change, wallpaper change or playback launch was
performed. Those disruptive actions and hardware-specific behavior need a
dedicated manual check. Existing notes were not read or written; scratchpad
tests use temporary files. These checks do not establish long-duration resource
stability, battery life or every multi-monitor/hardware combination.

The installed shell has local additions and is not a Git checkout. Upstream
automated tests ran in a fresh source checkout; live smoke checks ran against
the installed shell. Results from those two boundaries are recorded separately.
