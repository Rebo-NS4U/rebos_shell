.pragma library

var data = {

    "enabled": true,
    "sidebarEnabled": true,
    "defaultAgent": "codex",
    "workingDirectory": "",
    "agents": [
        {
            "id": "codex",
            "name": "Codex",
            "command": ["sh", "-lc", "CODEX_PATH=\"$(command -v codex)\" exec npx -y @agentclientprotocol/codex-acp"],
            "authMethod": "chat-gpt"
        }
    ],
    "sidebarWidth": 400,
    "sidebarPosition": "right",
    "sidebarPinnedOnStartup": false
}
