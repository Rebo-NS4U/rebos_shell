#!/usr/bin/bash
set -euo pipefail
# stdout is a private pipe owned by sudo. Never invoke this helper from chat.
exec /usr/bin/python3 "$(dirname -- "$(readlink -f -- "$0")")/assistant_sudo_dialog.py" password
