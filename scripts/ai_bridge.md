# Persistent assistant

## Multiple chats

The New chat button and `/new` create an independent `AiSession.qml` client.
`Ai.qml` keeps the list and selected client; the sidebar switches views without
cancelling background turns. Tabs show busy chats and chats awaiting questions
or permissions. Stop and Reconnect act on the selected chat. Closing an extra
tab stops its backend and keeps its saved history. History selects an already
open conversation or opens it in another client. Unsent text and attachments
are checkpointed separately for every chat.

The original chat retains `rebos-assistant.service` and `acp.sock`. Additional
chats use `rebos-assistant@<channel>.service` and `acp-<channel>.sock`, with
separate ACP processes, checkpoints and event streams. Install the template:

```sh
ln -s ~/.config/quickshell/scripts/rebos-assistant@.service ~/.config/systemd/user/rebos-assistant@.service
systemctl --user daemon-reload
```

The existing StateService stores open channel IDs and selection so menu reloads
reattach every live chat. This retains the existing service-crash/reboot limits
described below. The upgrade does not restart the original daemon.

`ai_bridge.py --server` runs as `rebos-assistant.service` in the systemd user
manager. It owns the ACP adapter and Codex process. `Ai.qml` owns only a disposable
stdio/socket relay. Closing, crashing or reloading Quickshell detaches that relay
without sending cancellation or terminating the backend.

Install the user unit once (the checkout must be available at
`~/.config/quickshell`):

```sh
mkdir -p ~/.config/systemd/user
ln -s ~/.config/quickshell/scripts/rebos-assistant.service ~/.config/systemd/user/rebos-assistant.service
systemctl --user daemon-reload
```

The menu starts the service on demand. It does not need to be enabled at login.
The unit deliberately has no `PartOf` dependency on Quickshell or the graphical
session. Its socket lives in `$XDG_RUNTIME_DIR/rebos-assistant/acp.sock`, with a
private directory and socket permissions. Nothing listens on the network.

The menu checkpoints chat messages, session/model selection, pending RPCs and
permission requests. Every outbound ACP message includes its checkpoint in the
same socket frame. Server events have sequence numbers; the daemon retains
unacknowledged events and replays them after reattachment. Text is flushed into
the checkpoint before acknowledgement to prevent losing streamed chunks.
Events are applied in order, outside the QML stdout handler.

Permission requests arriving while the menu is absent wait for user input after
reattachment. The daemon never approves them automatically. The existing Stop
button still cancels a turn, Reconnect explicitly replaces the agent, and
disabling AI explicitly stops the backend. A normal shell reload does none of
those things.

This preserves live work across shell restarts, not computer reboots or a crash
of the assistant service itself. Checkpoints and event journals are in memory;
ordinary chat-history files remain managed by `Ai.qml`. The initial migration
from the former child-process integration cannot transfer an already running
ACP process; existing saved conversations remain in History.

Diagnostics (do not dump protocol payloads or chat content into logs):

```sh
systemctl --user status rebos-assistant.service
python3 -m unittest discover -s tests/integration -p test_ai_bridge.py -v
```

The tests use a synthetic ACP process, a private Unix socket and real offscreen
Quickshell instances. They verify checkpoint/replay, process replacement,
explicit shutdown, and completion of one ongoing turn after the first menu has
exited, including a permission request received while no menu exists.

## Questions and activity

The menu advertises ACP `elicitation.form` and `plan` client capabilities.
The installed Codex ACP adapter translates its user-input requests into
`elicitation/create` form requests. `AssistantQuestions.qml` renders explicit
choice buttons, text/number fields, booleans, and multiple selections; answers
are validated against the restricted schema and sent only on **Send answer**.
Decline and Cancel return the corresponding ACP action. Agent cancellation
notifications dismiss expired forms. Private fields are masked and excluded
from saved chat messages.

Question requests, unfinished drafts, validation errors and progress are part
of the bridge checkpoint. They survive a menu restart without resubmission.
`AssistantActivity.qml` shows a collapsible, height-limited view of explicit
plan steps, with recent tool actions as the fallback. It does not derive steps
from model reasoning. Completed activity is retained with the saved chat.

When upgrading an existing connection that did not advertise form support,
the menu waits until its current turn is finished, then renegotiates the new
capabilities and resumes the same saved ACP session. It does not interrupt a
busy turn to enable questions.
