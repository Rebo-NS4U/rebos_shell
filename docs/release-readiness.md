# Release readiness — 2026-10-31

This performance and correctness pass is applied locally. The version remains
unchanged; release approval needs the remaining checks below.

## Changes

- Island content loads on demand, stays alive through exit fades, and unloads
  when closed. This includes the gallery, resource monitor, calendar and launcher.
- The standard bar dashboard and floating launcher also unload after closing.
- Minute-only clocks use Quickshell's minute-precision SystemClock. The calendar
  retains seconds while visible. Hidden waveform position polling stops.
- GPU/VM status polling stops while controls are hidden or suspension is active;
  opening controls refreshes immediately.
- Launcher selection has one owner. Arrow navigation advances one row; filtering
  to zero results clears selection without ListView feedback or binding loops.
- Delayed launcher focus checks that content still exists after quick closure.
- Battery hover corners reference their styled button explicitly.
- Power-menu Escape handling attaches to its focusable content instead of a window.
- Outside-click test fixtures now represent the separate assistant architecture.

## Verification

Passed:

- 31-file QML syntax scan, plus explicit syntax checks of the changed launcher,
  clock, GPU service and power-menu files. This scanner checks syntax only.
- Six focused integration suites: release resources, shell motion, dashboard,
  appearance settings, outside clicks, network resource use.
- GPU polling, monitor details and bar button integration suites: four tests.
- All 22 standalone assistant integration checks with local socket access.
- Real desktop IPC opens for dashboard, sound, microphone, Wi-Fi, Bluetooth,
  resources, alerts, wallpapers, battery, weather, calendar, apps and projects.
- Settled screenshots inspected for dashboard, calendar, gallery, resources and
  launcher on the current 1920x1200 display.
- Automatic shell reload preserved the shell PID and active assistant backend.
- Whitespace/error check with git diff --check.

New lifecycle coverage exercises all 15 island modes, exit retention, rapid
reversal, zero-duration motion and keyboard/filter selection. Hardware panels
are stand-ins in this test; live IPC/screenshots cover actual panel construction.

## Resource observations and remaining checks

The existing shell process initially used 739624 KiB RSS / 645305 KiB PSS.
After the initial lazy-loading change its RSS was approximately 637956 KiB.
After visiting every tested panel it used 774600 KiB RSS / 671808 KiB PSS.
Hot reload, caches and allocator retention affect these figures; the initial
reduction is not evidence of a durable steady-state RAM saving.

A subsequent 12-cycle dashboard/gallery/launcher exercise ranged from 830828 to
846012 KiB RSS and ended at 845356 KiB, versus 836984 KiB after its first cycle.
This short run does not establish a leak or prove long-term memory stability.
One eight-second idle CPU sample recorded zero CPU ticks after the clock change;
the baseline recorded one tick. Neither sample measures battery life.

Remaining before release:

- Run a controlled fresh-login RAM comparison and longer idle/open-close soak.
- Measure unplugged battery drain with comparable display brightness and workload.
- Verify multi-monitor placement, suspend/resume and lock/unlock on hardware.
- Resolve three existing Tier 1 source-contract test failures. They expect a
  ShaderEffect in FluidTextProgress, DynamicVolumeIcon in IslandStatusIcons, and
  direct Colors.overBackground use in IslandStatusIcons. Those two implementation
  files were unchanged by this pass. The broad suite reports 188 passes / 3 fails.
- Investigate remaining Qt Wayland text-input focus warnings. The tested panel
  opens did not report launcher binding loops, battery corner warnings or invalid
  window Keys attachment after these fixes.

No release was published, no power profile was changed, and no active assistant
backend was restarted. The pre-existing AiSession.qml edit is preserved.
