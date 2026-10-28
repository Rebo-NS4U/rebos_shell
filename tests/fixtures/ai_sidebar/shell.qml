import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.modules.sidebar
import qs.modules.globals

ShellRoot {
    id: test

    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            let found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }

    property int beats: 0
    property string scenario: Quickshell.env("AI_LAYOUT_SCENARIO") || "history"

    Component.onCompleted: {
        Ai.currentChat = [{
            "role": "user",
            "content": "sample"
        }, {
            "role": "assistant",
            "content": "sample words sample words sample words sample words sample words s",
            "model": "Codex"
        }, {
            "role": "assistant",
            "content": "",
            "model": "Codex",
            "functionCall": {
                "id": "tool",
                "name": "Read project memory",
                "args": {
                }
            },
            "toolStatus": "completed",
            "functionPending": false,
            "functionApproved": true
        }, {
            "role": "assistant",
            "content": "sample words sample words sample word",
            "model": "Codex"
        }, {
            "role": "user",
            "content": "sample words"
        }, {
            "role": "assistant",
            "content": "sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample word",
            "model": "Codex"
        }, {
            "role": "user",
            "content": "sample words sampl"
        }, {
            "role": "assistant",
            "content": "sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words sample words samp",
            "model": "Codex"
        }, {
            "role": "user",
            "content": "sample words sa"
        }, {
            "role": "assistant",
            "content": "sample words sample words sample words sample words sample",
            "model": "Codex"
        }, {
            "role": "user",
            "content": "sample words sample words sam"
        }, {
            "role": "assistant",
            "content": "sa",
            "model": "Codex"
        }, {
            "role": "user",
            "content": "sample wor"
        }, {
            "role": "assistant",
            "content": "sample words sample words samp",
            "model": "Codex"
        }];
        if (scenario === "long_reply") {
            Ai.currentChat = [{
                "role": "user",
                "content": "sample words sample words sample words sample words sample words"
            }, {
                "role": "assistant",
                "content": "sample words sample words sample words sample w",
                "model": "Codex"
            }, {
                "role": "assistant",
                "content": "",
                "model": "Codex",
                "functionCall": {
                    "id": "tool",
                    "name": "Inspect files",
                    "args": {
                    }
                },
                "toolStatus": "completed",
                "functionPending": false,
                "functionApproved": true
            }, {
                "role": "assistant",
                "content": "sample words sample words sample words sample words sample words sample \nwords sample words sample words sample words sample words sample words s\nample words sample words sample words sample words sample words sample w\nords sample words sample words sample words sample words sample words sa\nmple words sample words sample words sample words sample words sample wo",
                "model": "Codex"
            }, {
                "role": "user",
                "content": "sample words sample words sampl"
            }, {
                "role": "assistant",
                "content": "sample words sample words sample words sample words sampl\ne words sample words sample words sample words sample wor\nds sample words sample words sample words sample words sa\nmple words sample words sample words sample words sample \nwords sample words sample words sample words sample words\n sample words sample words sample words sample words samp\nle words sample words sample words sample words sample wo\nrds sample words sample words sample words sample words s\nample words sample words sample words sample words sample\n words sample words sample words sample words sample word\ns sample words sample words sample words sample words sam\nple wor",
                "model": "Codex"
            }, {
                "role": "user",
                "content": "sample words sample words"
            }];
            Ai.agentTurnActive = true;
            Ai.isLoading = true;
            Ai.activeAssistantIndex = -1;
        } else {
            Ai.activeAssistantIndex = Ai.currentChat.length - 1;
        }
        console.log("LOADED messages", Ai.currentChat.length);
    }

    Window {
        visible: true
        width: 1280
        height: 800

        AssistantSidebar {
            id: sidebar
            targetScreen: Quickshell.screens[0]
        }

    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            test.beats++;
            // Reflow a streaming chat at both narrow and wide sidebar sizes.
            if (test.beats === 10)
                GlobalStates.assistantWidth = 320;
            if (test.beats === 20)
                GlobalStates.assistantWidth = 740;
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            Ai.handleSessionUpdate({
                "update": {
                    "sessionUpdate": "agent_message_chunk",
                    "content": {
                        "type": "text",
                        "text": " streamed text ".repeat(100)
                    }
                }
            });
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (test.beats < 10) {
                console.error("FAIL: event loop starved", test.beats);
                Qt.exit(1);
            } else {
                if (test.scenario === "long_reply") {
                    let status = findNamed(sidebar, "assistantStatusText");
                    let scroll = findNamed(sidebar, "assistantStatusScroll");
                    if (!status || !scroll || scroll.width <= 0 || scroll.height <= 0 || status.width > scroll.width) {
                        console.error("FAIL: busy status has invalid layout");
                        Qt.exit(1);
                        return;
                    }
                }
                console.log("PASS UI responsive", test.beats);
                Qt.quit();
            }
        }
    }

}
