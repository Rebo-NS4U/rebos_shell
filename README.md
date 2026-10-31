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

Published source: [Rebo-NS4U/rebos_shell](https://github.com/Rebo-NS4U/rebos_shell).
For the complete Arch desktop, use the bundled
[rebos_enclosure installer](https://github.com/Rebo-NS4U/rebos_enclosure).

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

## Updater

Use [update.sh](update.sh) to pull the latest shell content from
[Rebo-NS4U/rebos_shell](https://github.com/Rebo-NS4U/rebos_shell) while keeping
your saved preferences. Run it from your existing shell Git checkout:

```bash
cd /path/to/rebos_shell
./update.sh --check   # Preview the changes first
./update.sh           # Apply the update
```

The updater follows GitHub's default branch and prints its backup location before
applying changes. Git and Python 3 are required; run it as your normal user.
To update a checkout from another directory or select a branch:

```bash
/path/to/rebos_shell/update.sh --path /path/to/rebos_shell --check
./update.sh --branch rebos-shell-refresh
```

It updates shell source only, without installing packages or restarting desktop
services. For a Nix-managed installation, update through Nix instead. The bundled
desktop installer snapshot has no Git metadata and cannot be updated with this
script; `--path` must point to a shell Git checkout.

Only changed source files are replaced. Obsolete tracked files are removed;
unrelated untracked files remain. Local code edits and files that collide with new
source files are backed up before replacement. Each backup contains only affected
existing files, a Git index copy, and a manifest listing the old/new commits and
added/removed paths. Its location is printed during the update, normally under
`~/.local/state/rebos_shell/backups/update-*`. Directory conflicts stop the update
before any source files are changed.

Saved preferences under `~/.config/rebos_shell`, personal state/data/cache,
wallpapers, and Niri settings are left in place (including custom XDG locations).
New settings continue to use the shell's normal defaults. Source changes are
picked up by Quickshell's normal hot reload.

The installer and Nix package are still inherited scaffolding and may need
adjustment for this fork.

## Attribution and license

rebos_shell is a customized desktop shell derived from Ambxst by Axenide and contributions by jR4dh3y. Full copyright and
contributor history from that lineage is preserved in this repository’s Git
history.

This project is licensed under the GNU Affero General Public License v3.0 or
later. See [LICENSE](./LICENSE).
