# Shell motion

Settings → Appearance → Motion controls the existing persisted
`Config.theme.animDuration` value. Smooth selects 300 ms, Quick selects 180 ms,
and Off selects 0; the slider allows custom durations. Installing this change
preserves the user's saved duration.

`modules/theme/Motion.qml` derives opening, closing, resize, feedback, press,
and content fade timings from that value. Openings use OutCubic; exits use
InOutCubic. Interaction feedback settles without overshoot. Continuous status
indicators retain their own cadence.

The island morphs from its existing bar geometry. BarPopup reveals at its
attachment edge without scaling text. Launcher and notes share MotionReveal,
which keeps content painted through exit, releases input immediately on close,
and reverses from its current position. Turning motion Off during a reveal
settles it immediately. Notes blur follows the painted card through exit.

Validation:

```sh
PYTHONPATH=tests/integration python3 -m unittest test_shell_motion test_settings_layout test_quick_notes
```

Tests isolate configuration, palette generation and hardware services. The
motion test checks pointer input during exit, rapid reversals, launcher
placement at both edges, preset/custom durations, Off during animation and
persistence in a fresh process. Settings checks include navigation and search
for Motion. Full assistant checks require local Unix sockets.

Use native hot reload; never restart the desktop shell to apply these changes.
