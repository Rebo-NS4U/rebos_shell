# <img src="./assets/rebos_shell/rebos_shell-logo-color.svg" alt="" width="40" height="40"> rebos_shell

**rebos_shell** is a Niri-first Wayland desktop shell built with
[Quickshell](https://quickshell.org).

## Hard fork

This project is a **hard fork** of
[Ambxst](https://github.com/Axenide/Ambxst) by
[Axenide](https://github.com/Axenide).

It is not Ambxst, does not track Ambxst as an upstream merge target for
day-to-day work, and ships under its own name, branding, config paths, and
release process. The fork keeps a lean runtime focus:

- wallpaper
- one unified bar
- floating run menu
- lockscreen
- reactive JSON configuration

Multi-monitor support uses Quickshell `Variants` on `Quickshell.screens`.

## Features

Version **1.1.6** adds the redesigned clock dashboard, edge window navigation,
desktop shortcut creation and adjustable window corners. It also updates shell
outlines, media handling, blur and idle network resource use.

Published source: [Dytox2/rebos_shell](https://github.com/Dytox2/rebos_shell).
For the complete Arch desktop, use the bundled
[rebos_enclosure installer](https://github.com/Dytox2/rebos_enclosure).

- Runs directly on [Niri](https://github.com/YaLTeR/niri) via its JSON event stream
- Normalized monitor, workspace, and window state for multi-monitor setups
- Unified bar with workspaces/taskbar, clock, system status, and systray
- Floating run menu and power menu
- Wallpaper picker and secure `WlSessionLock` session lock
- Isolated `rebos_shell` config, state, cache, data, and IPC paths
- [Persistent assistant](scripts/ai_bridge.md) that keeps working across shell reloads

## Direct commands

The shell exposes lightweight commands through its IPC runner. For example,
`rebos_shell run wallpapers` opens the wallpaper picker on the focused monitor
and toggles it closed when invoked again. This can be bound from Niri with:

```kdl
Mod+Shift+W hotkey-overlay-title="Open Wallpapers" { spawn "rebos_shell" "run" "wallpapers"; }
```

## Run the development tree

Install Quickshell and the runtime tools needed by the shell. Install fonts once,
then run from a checkout:

```bash
./scripts/install-fonts.sh
qs -p /path/to/rebos_shell
```

Or use the CLI wrapper:

```bash
./cli.sh
```

The installer and Nix package are still inherited scaffolding and may need
adjustment for this fork.

## Attribution and license

rebos_shell is a customized desktop shell derived from Ambxst by Axenide and contributions by jR4dh3y. Full copyright and
contributor history from that lineage is preserved in this repository’s Git
history.

This project is licensed under the GNU Affero General Public License v3.0 or
later. See [LICENSE](./LICENSE).
