# Assistant usage and terminal access

Click **Model** near the top of the sidebar to choose the model for this
conversation. The list shows names and descriptions provided by your agent;
search filters both. A checkmark identifies the current model. If no session
is connected yet, use **Load models** to connect without sending a message.
Models can be changed between replies. The button shows switching progress,
and errors leave the previous selection active. Your draft stays in place.
The existing `/model` and `/model <id>` commands also work.

The sidebar shows shared Codex plan quota percentages and refreshes every minute
while open. Click the readout or send `/usage` for each quota window and its reset
time. Hover over it for details and the time of the last check. These are account
limits shared with other Codex clients, not a measurement of this bot alone.
Unknown or failed checks show usage as unavailable.

New ACP sessions receive the `plan_usage` MCP server, exposing the read-only
`check_plan_usage` tool. Start a new chat with `/new` if an existing session was
opened before the tool was added. The helper uses `account/rateLimits/read` through
the installed Codex app-server and existing Codex login. It does not run inference
or read credentials directly. No additional Python packages are required.

Codex already supplies shell execution tools; ask the bot to run a command and
use its existing permission controls when prompted. `/terminal` opens Kitty in
the current chat's working directory for manual terminal use.

Drag the small handle on the sidebar's inner edge to resize its width. The width
is saved when the drag finishes. The panel retains its full-screen height.

The assistant is encouraged to ask early when your preferences, scope, or missing
details would change the result. Its `assistant_questions.ask_user_question` tool
opens an answerable card during normal work. Select a choice or choose Something
else and add your own answer, then click Send. Questions without choices accept
text directly. Decline skips a question; Cancel dismisses it; Stop cancels the turn.
Questions stay with their chat and survive shell reloads. Existing connections
pick up the tool once their current turn finishes, preserving the session.
Clear, simple tasks continue without unnecessary questions.

Protocol reference: <https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt>.
