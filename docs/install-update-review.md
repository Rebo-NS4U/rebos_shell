# Install and update review — 2026-11-01

The standalone installer now defaults to the published shell repository, follows
its remote default branch on first clone, and reuses the preference-preserving
updater for existing checkouts. This removes the hard-coded `main` reset and the
path that moved an existing non-Git directory aside. Local source edits receive
the updater's recovery backup. Invalid destinations are rejected unchanged.

The launcher installs under the user's `~/.local/bin` instead of creating a
system-wide executable tied to one home directory. Its generated script handles
spaces and forwards arguments unchanged. Existing launchers are backed up;
linked launchers are rejected. The Settings desktop entry points to the bundled
Phosphor gear SVG, with its MIT license embedded. The same gear replaces the
previous six-tooth font glyph in shell controls.

Strict shell mode is enabled, unmapped dependency names work with unset-variable
checking, the font lookup and Fedora COPR commands avoid pipefail/SIGPIPE issues,
and font downloads fail on HTTP errors. Unsupported distributions stop before
continuing through installation. The updater locks each checkout before fetching
or replacing files so concurrent runs cannot interleave backups and writes.

Verification:

- 13 standalone install/update tests passed against disposable homes and actual
  local Git repositories. They cover a non-main default branch, source backups,
  non-repository destinations, launcher quoting/argument forwarding, symlink
  preservation, preview, fetch failure and concurrent update rejection.
- Two QML dashboard/Settings runtime checks passed.
- All 43 rebos_enclosure desktop tests passed, including full installer flow
  with system commands stubbed, payload verification, backups, recovery,
  preference preservation and remote update fetching.
- Shell syntax, desktop-entry validation and both Git whitespace checks passed.
- The SVG rendered successfully and was visually inspected.

Five ignored, generated Python bytecode files had made the desktop payload fail
its strict inventory check. They were moved to a temporary recovery directory;
the payload checksum list was updated only for the intentional icon changes.
The snapshot generator carries the new icon reference into future snapshots.

The real system package installation, Fedora/NixOS installation and hardware
service changes were not executed. The running panel remained at PID 823 and
both assistant services stayed active. No desktop or assistant restart was used.
