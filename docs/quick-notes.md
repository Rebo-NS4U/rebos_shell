# Quick notes

Press **Super+Alt+N** to toggle the scratchpad on the focused monitor. Escape,
the Close button, or clicking outside closes it. The popup uses the existing
Quickshell overlay and reserves no space, so tiled windows keep their layout.

Notes save automatically after a brief pause and when closed. Ctrl+S saves
immediately or retries a failed save. The footer shows pending changes and errors.
The plain-text Markdown file is `~/Documents/Quick Notes.md` and survives shell
restarts. The editor is a single scratchpad; Markdown is edited as plain text.

IPC: `qs ipc call rebos_shell run notes`

Check: `python tests/integration/test_quick_notes.py` (offscreen Quickshell,
isolated files, and stubbed desktop services/theme). This checks persistence,
Unicode, close/reopen, failed saves, and popup loading; it does not exercise
live Wayland focus, input masks, or keyboard shortcuts.

The popup follows the shell’s rounded cards, Phosphor icons, themed tooltips,
and compact controls. Header, focus outline, selection, scrollbar, and save
status use the live `Colors` singleton from the existing Matugen pipeline;
wallpaper palette changes update the popup automatically.
