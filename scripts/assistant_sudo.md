# Administrator requests

Use `~/.local/bin/assistant-sudo --reason 'Reason for the change' -- command argument...`.
The desktop first shows the exact argument list and working directory for approval.
After approval, sudo requests authentication through a masked desktop password dialog.
Canceling either dialog prevents execution. No password is stored by these helpers or sent to chat.
Sudo policy still determines which commands the user can run.

From a sandboxed assistant, request the normal reviewed execution outside the sandbox
before invoking this helper; it cannot grant sandbox permission itself. Never disable
the sandbox or alter sudoers to get around a rejected request. Do not call the askpass
script directly, capture its output, or ask the user to paste passwords into chat.

Installation: make both scripts executable and link `assistant_sudo.py` as
`~/.local/bin/assistant-sudo`. Keep `assistant_sudo_dialog.py` beside the scripts.
Requires sudo, Python with GTK4/PyGObject and Cairo, and an accessible desktop session.

Both dialogs read the shell palette and theme settings, following wallpaper colors,
OLED backgrounds, font, roundness and the shared logical-pixel dither grid. Open
dialogs refresh their appearance when the theme changes. The approval dialog starts
with Cancel focused; Escape or window close cancels either dialog.
