# File shelf

Drag local files or folders over the **middle of the left edge** of any screen.
The handle and shelf appear only during the file drag. They hide when the drag
leaves or finishes; normal pointer hovering leaves them hidden. Multiple files can be dropped at once;
duplicates appear only once. Drag a card into a file manager, upload field, or
another app that accepts files.

- Press **Super+Alt+F** to open or close the shelf when retrieving stored files.
  A shelf explicitly opened this way stays open until you close it.
- The X on a card removes its reference. The trash button clears the shelf.
- The header X closes the panel while keeping its cards. Escape closes it when
  the shelf has keyboard focus.
- Removing cards and clearing the shelf leave original files untouched.
- Shelf contents are shared across monitors, with one expanded panel at a time.
- Up to 64 references are retained, including across shell reloads and restarts.
- Image formats supported for previews include PNG, JPEG, WebP, GIF, BMP and AVIF.

IPC: `qs ipc call rebos_shell run file-shelf` (`shelf` is also accepted).

The shelf accepts and exports copy actions only. It stores file URIs in
`Quickshell.statePath("file-shelf.json")`; no file contents are copied into this
state file. Moving or deleting an original file can invalidate its card. Missing
files are omitted when saved references are restored. Browser links, remote file
URIs and special files such as pipes are rejected.

The shell's existing surface styles, palette, blur and motion settings apply.
An unpainted two-pixel target at the middle of the left edge receives incoming
file drags. The expanded shelf takes input over its handle and card panel, and
reserves no desktop space. It hides during locking. Close, clear and remove actions are
blocked during an outgoing drag so delegates stay alive until Qt finishes it.

Implementation:

- `modules/widgets/fileshelf/`: handle, shelf, file cards and native drag/drop.
- `modules/services/FileShelf.qml`: shared model, queued metadata and atomic state.
- `scripts/file_shelf.py`: read-only local-file validation and metadata via stdin.

Checks:

```sh
python3 -m unittest tests.integration.test_file_shelf tests.integration.test_shell_motion tests.integration.test_panel_outside_click
niri validate
```

The shelf integration check compiles a Qt 6 test plugin to send URI drag/drop
events through a real QQuickWindow. It checks copy-only acceptance, local path
validation, duplicates, actions, lock hiding, screen selection, late results after
clearing, persistence, and original-file preservation. Qt 6 development headers,
`/usr/lib/qt6/moc`, a C++ compiler and Quickshell are required.

On 2026-10-27, an additional isolated Wayland check used a virtual pointer and a
separate Qt Widgets app to transfer an encoded filename into and out of the
shelf. Both transfers completed and the original file was unchanged. Other
apps' particular drop-target behavior still depends on their supported formats.

Qt native drag setup follows [Qt Quick Drag](https://doc.qt.io/qt-6/qml-qtquick-drag.html).
Apply changes with native hot reload; do not restart Quickshell or Niri.
