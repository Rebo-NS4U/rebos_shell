import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "AiQuestions.js" as Questions
import qs.modules.services

// ACP client and chat-state adapter for the assistant sidebar.
//
// Codex runs through its local ACP adapter and owns authentication, models,
// tools, permissions, and conversation context. The systemd user bridge owns
// its lifetime; this client and its stdio relay can be replaced at any time.
Scope {
    id: root

    property string channelId: "default"
    property string inputDraft: ""
    property list<var> attachmentDraft: []
    readonly property string sessionTitle: {
        let first = currentChat.find(message => message.role === "user");
        return first ? String(first.content).slice(0, 60) : "New chat";
    }
    property bool sessionEnabled: true
    readonly property bool featureEnabled: sessionEnabled && Config.aiReady && (Config.ai.enabled ?? true)
    onSessionEnabledChanged: {
        if (sessionEnabled) Qt.callLater(bootstrap);
        else if (bootstrapped || bridgeAttached) shutdown();
    }

    // ============================================
    // AGENTS
    // ============================================

    readonly property var builtInAgents: [
        {
            id: "codex",
            name: "Codex",
            description: "OpenAI Codex coding agent through the official ACP adapter",
            icon: Qt.resolvedUrl("../../assets/aiproviders/openai.svg"),
            command: ["sh", "-lc", "CODEX_PATH=\"$(command -v codex)\" exec npx -y @agentclientprotocol/codex-acp"],
            authMethod: "chat-gpt",
            installHint: "Install Codex and Node.js; the ACP adapter reuses your Codex login",
            provider: "acp",
            api_format: "ACP",
            model: "codex"
        }
    ]

    property var models: builtInAgents
    property var currentModel: models.length > 0 ? models[0] : null
    property string currentAgentId: currentModel ? currentModel.id : "codex"
    property string processAgentId: ""
    property bool fetchingModels: false

    function normalizeAgent(configured, fallback) {
        let command = configured && Array.isArray(configured.command) ? configured.command : fallback.command;
        if (!command || command.length === 0)
            command = fallback.command;
        return {
            id: configured && configured.id ? configured.id : fallback.id,
            name: configured && configured.name ? configured.name : fallback.name,
            description: configured && configured.description ? configured.description : fallback.description,
            icon: fallback.icon,
            command: command,
            authMethod: configured && configured.authMethod ? configured.authMethod : fallback.authMethod,
            installHint: configured && configured.installHint ? configured.installHint : fallback.installHint,
            provider: "acp",
            api_format: "ACP",
            model: configured && configured.id ? configured.id : fallback.id
        };
    }

    function refreshAgents() {
        let configured = Config.ai && Array.isArray(Config.ai.agents) ? Config.ai.agents : [];
        let next = [];
        for (let i = 0; i < builtInAgents.length; i++) {
            let fallback = builtInAgents[i];
            let override = null;
            for (let j = 0; j < configured.length; j++) {
                if (configured[j] && configured[j].id === fallback.id) {
                    override = configured[j];
                    break;
                }
            }
            next.push(normalizeAgent(override, fallback));
        }
        models = next;

        let restored = findAgent(currentAgentId);
        if (!restored) {
            let preferred = Config.ai && Config.ai.defaultAgent ? Config.ai.defaultAgent : "codex";
            restored = findAgent(preferred) || models[0];
        }
        if (restored) {
            currentModel = restored;
            currentAgentId = restored.id;
        }
    }

    function findAgent(value) {
        let needle = (value || "").toLowerCase();
        for (let i = 0; i < models.length; i++) {
            let agent = models[i];
            if (agent.id.toLowerCase() === needle || agent.name.toLowerCase() === needle)
                return agent;
        }
        return null;
    }

    function setModel(value) {
        let agent = findAgent(value);
        if (!agent) {
            pushSystemMessage("Unknown ACP agent: " + value);
            return;
        }
        if (agent.id === currentAgentId)
            return;

        cancelGeneration(false);
        currentModel = agent;
        currentAgentId = agent.id;
        StateService.set("lastAiAgent", agent.id);
        createNewChat();
    }

    function fetchAvailableModels() {
        fetchingModels = true;
        refreshAgents();
        refreshTimer.restart();
    }

    function reconnectAgent() {
        if (!featureEnabled)
            return;
        cancelGeneration(false);
        sessionReady = false;
        currentSessionId = "";
        pendingSessionAction = {
            kind: "new"
        };
        if (agentProcess.running && bridgeAttached) {
            bridgeAttached = false;
            agentProcess.write(JSON.stringify({bridge: "reset"}) + "\n");
        } else {
            restartAgentProcess();
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: root.fetchingModels = false
    }

    // ============================================
    // ACP CONNECTION
    // ============================================

    readonly property int protocolVersion: 1
    property bool initialized: false
    property bool authenticated: false
    property bool sessionReady: false
    property bool expectedProcessStop: false
    property bool restartPending: false
    property bool suppressReplay: false
    property var agentCapabilities: ({})
    property var authMethods: []
    property var pendingRpc: ({})
    property int nextRpcId: 1
    property int activePromptRequestId: -1
    property var pendingSessionAction: null
    property var queuedPrompt: null
    property string agentStderrTail: ""
    property bool turnFailureHandled: false

    property var sessionConfigOptions: []
    property var sessionModels: []
    property string currentSessionModelId: ""
    property string pendingSessionModelId: ""
    property string modelSwitchError: ""
    readonly property bool switchingSessionModel: pendingSessionModelId.length > 0
    readonly property string sessionModelName: {
        for (let i = 0; i < sessionModels.length; i++) {
            if (sessionModels[i].modelId === currentSessionModelId)
                return sessionModels[i].name || currentSessionModelId;
        }
        return currentSessionModelId || "Agent default";
    }
    property var availableCommands: []
    property string currentModeId: ""
    property int contextUsed: 0
    property int contextSize: 0
    property real sessionCost: 0
    property string sessionCostCurrency: ""
    property string planUsageSummary: "Plan usage: not checked"
    property string planUsageDetails: ""
    property bool usageRequestedInChat: false
    readonly property bool checkingPlanUsage: planUsageProcess.running
    readonly property string usageScript: Qt.resolvedUrl("../../scripts/ai_plan_usage.py").toString().replace(/^file:\/\//, "")
    readonly property string questionsScript: Qt.resolvedUrl("../../scripts/ai_questions.py").toString().replace(/^file:\/\//, "")

    function refreshPlanUsage(showInChat) {
        usageRequestedInChat = usageRequestedInChat || !!showInChat;
        if (!planUsageProcess.running) {
            planUsageProcess.command = ["python3", usageScript];
            planUsageProcess.running = true;
        }
    }

    function applyPlanUsage(data) {
        if (data.error) {
            planUsageSummary = "Plan usage unavailable";
            planUsageDetails = data.error;
        } else {
            let summaries = [];
            let details = ["Shared Codex account quota (includes other Codex clients)."];
            for (let limit of data.limits || []) {
                for (let window of limit.windows || []) {
                    let minutes = window.windowDurationMins;
                    let label = minutes >= 1440 ? (minutes / 1440) + "d"
                        : minutes >= 60 ? (minutes / 60) + "h"
                        : minutes ? minutes + "m" : window.kind;
                    let text = limit.name + " " + label + ": " + Math.round(window.usedPercent) + "% used";
                    summaries.push(text);
                    details.push(text + (window.resetsAt ? " · resets " + new Date(window.resetsAt * 1000).toLocaleString() : ""));
                }
            }
            planUsageSummary = summaries.length ? summaries.join(" · ") : "Plan usage unavailable";
            details.push("Checked " + new Date(data.checkedAt * 1000).toLocaleString());
            planUsageDetails = details.join("\n");
        }
        if (usageRequestedInChat) {
            usageRequestedInChat = false;
            Qt.callLater(() => root.pushSystemMessage(root.planUsageDetails));
        }
    }

    Process {
        id: planUsageProcess
        stdout: StdioCollector {
            id: planUsageStdout
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.applyPlanUsage({error: "Plan usage helper could not start"});
                return;
            }
            try {
                root.applyPlanUsage(JSON.parse(planUsageStdout.text));
            } catch (e) {
                root.applyPlanUsage({error: "Plan usage helper returned an invalid response"});
            }
        }
    }

    function openTerminal() {
        Quickshell.execDetached(["kitty", "--directory", currentChatCwd || workingDirectory()]);
    }

    function workingDirectory() {
        let configured = Config.ai && Config.ai.workingDirectory ? Config.ai.workingDirectory.trim() : "";
        if (!configured)
            return Quickshell.env("HOME");
        if (configured === "~")
            return Quickshell.env("HOME");
        if (configured.startsWith("~/"))
            return Quickshell.env("HOME") + configured.substring(1);
        if (configured.startsWith("/"))
            return configured;
        return Quickshell.env("HOME") + "/" + configured;
    }

    // Only the disposable relay is a Quickshell child. The agent, pending RPCs,
    // permission requests and undelivered events live in the background bridge.
    readonly property string bridgeScript: Qt.resolvedUrl("../../scripts/ai_bridge.py").toString().replace(/^file:\/\//, "")
    property bool bridgeAttached: false
    property bool bridgeDirty: false
    property double bridgeSequence: 0
    readonly property list<string> bridgeStateKeys: [
        "initialized", "authenticated", "sessionReady", "suppressReplay",
        "agentCapabilities", "authMethods", "pendingRpc", "nextRpcId",
        "activePromptRequestId", "pendingSessionAction", "queuedPrompt", "agentStderrTail",
        "turnFailureHandled", "sessionConfigOptions", "sessionModels", "currentSessionModelId",
        "pendingSessionModelId", "modelSwitchError", "availableCommands", "currentModeId",
        "contextUsed", "contextSize", "sessionCost", "sessionCostCurrency",
        "activeAssistantMessageId", "activeAssistantIndex", "pendingPermissions", "isLoading",
        "toolRunning", "agentTurnActive", "statusText", "thoughtText", "thoughtMessageId", "lastError",
        "currentChat", "currentChatId", "currentChatAgentId", "currentSessionId",
        "currentChatCwd", "currentAgentId", "questionRequests", "questionDrafts",
        "inputDraft", "attachmentDraft", "questionErrors", "taskPlan", "taskPlanMarkdown", "activityLog", "questionSupportNegotiated", "questionToolNegotiated"
    ]

    function bridgeState() {
        flushAssistantText();
        let state = {};
        for (let key of bridgeStateKeys)
            state[key] = root[key];
        return state;
    }

    function checkpointBridge() {
        if (!bridgeAttached || !agentProcess.running)
            return;
        bridgeDirty = false;
        agentProcess.write(JSON.stringify({bridge: "checkpoint", seq: bridgeSequence, state: bridgeState()}) + "\n");
    }

    Timer {
        id: bridgeCheckpointTimer
        interval: 250
        // Idle sessions have no state to save and need no periodic wakeups.
        running: root.bridgeAttached && root.bridgeDirty
        repeat: true
        onTriggered: {
            if (root.bridgeDirty)
                root.checkpointBridge();
        }
    }

    Timer {
        id: bridgeReconnectTimer
        interval: 1500
        onTriggered: {
            if (root.featureEnabled && !agentProcess.running)
                root.startAgentProcess();
        }
    }

    onCurrentChatChanged: bridgeDirty = true
    onStatusTextChanged: bridgeDirty = true

    property list<string> bridgeFrames: []

    function queueBridgeLine(line) {
        bridgeFrames.push(line);
        Qt.callLater(root.drainBridgeFrames);
    }

    function drainBridgeFrames() {
        let frames = Array.from(bridgeFrames);
        bridgeFrames = [];
        for (let line of frames)
            handleBridgeLine(line);
    }

    function handleBridgeLine(line) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            console.warn("Ignoring invalid assistant bridge frame");
            return;
        }
        if (event.bridge === "attached") {
            // A checkpoint already contains flushed text. Discard any local
            // batch before restoring it, otherwise it can be appended twice.
            assistantTextTimer.stop();
            pendingAssistantText = "";
            pendingAssistantMessageId = "";
            bridgeSequence = event.seq || 0;
            bridgeAttached = true;
            if (event.state) {
                for (let key of bridgeStateKeys) {
                    if (event.state[key] !== undefined)
                        root[key] = event.state[key];
                }
                currentModel = findAgent(currentAgentId) || models[0];
                processAgentId = currentAgentId;
                chatModelChanged();
                if (agentTurnActive && Object.keys(pendingPermissions).length === 0 && questionRequests.length === 0)
                    turnWatchdog.restart();
            } else {
                resetConnectionState();
                processAgentId = currentAgentId;
                if (!currentChatId) {
                    currentChatId = String(Date.now()) + "-" + channelId;
                    currentChatAgentId = currentAgentId;
                    currentChatCwd = workingDirectory();
                }
                if (!pendingSessionAction)
                    pendingSessionAction = {kind: currentSessionId ? "load" : "new",
                        sessionId: currentSessionId, cwd: currentChatCwd};
                startInitialization();
            }
            bridgeDirty = true;
            return;
        }
        if (event.seq !== undefined) {
            if (event.seq <= bridgeSequence)
                return;
            bridgeSequence = event.seq;
        }
        if (event.bridge === "acp") {
            handleAcpLine(JSON.stringify(event.message));
        } else if (event.bridge === "stderr") {
            handleAgentStderr(event.text);
        } else if (event.bridge === "exit") {
            flushAssistantText();
            turnWatchdog.stop();
            isLoading = false;
            agentTurnActive = false;
            toolRunning = false;
            sessionReady = false;
            pendingPermissions = {};
            questionRequests = [];
            questionDrafts = {};
            questionErrors = {};
            pendingRpc = {};
            activePromptRequestId = -1;
            pendingSessionModelId = "";
            statusText = "Assistant stopped";
            pushSystemMessage("Assistant process exited (" + event.code + "). Reconnect the assistant to start it again.");
        } else if (event.bridge === "error") {
            lastError = event.error || "Assistant background service is unavailable";
            statusText = lastError;
            console.warn(lastError);
        }
        bridgeDirty = true;
    }

    function resetConnectionState() {
        flushAssistantText();
        initialized = false;
        authenticated = false;
        sessionReady = false;
        agentCapabilities = {};
        authMethods = [];
        pendingRpc = {};
        activePromptRequestId = -1;
        sessionConfigOptions = [];
        sessionModels = [];
        currentSessionModelId = "";
        pendingSessionModelId = "";
        modelSwitchError = "";
        availableCommands = [];
        currentModeId = "";
        processAgentId = "";
        agentStderrTail = "";
    }

    function startAgentProcess() {
        if (!featureEnabled || !currentModel)
            return;
        resetConnectionState();
        processAgentId = currentAgentId;
        bridgeReconnectTimer.stop();
        bridgeAttached = false;
        agentProcess.command = ["python3", bridgeScript];
        if (channelId !== "default")
            agentProcess.command = agentProcess.command.concat(["--channel", channelId]);
        agentProcess.workingDirectory = workingDirectory();
        expectedProcessStop = false;
        statusText = "Starting " + currentModel.name + "…";
        agentProcess.running = true;
    }

    function restartAgentProcess() {
        if (!featureEnabled) {
            shutdown();
            return;
        }
        if (agentProcess.running) {
            restartPending = true;
            expectedProcessStop = true;
            agentProcess.running = false;
            return;
        }
        restartPending = false;
        startAgentProcess();
    }

    function ensureConnection(action) {
        if (!featureEnabled)
            return;
        pendingSessionAction = action;
        if (agentProcess.running && processAgentId === currentAgentId && authenticated) {
            performSessionAction();
            return;
        }
        if (!agentProcess.running || processAgentId !== currentAgentId) {
            restartAgentProcess();
            return;
        }
        statusText = "Connecting to " + currentModel.name + "…";
    }

    function sendEnvelope(envelope) {
        if (!agentProcess.running)
            return false;
        if (!bridgeAttached)
            return false;
        bridgeDirty = false;
        agentProcess.write(JSON.stringify({bridge: "send", seq: bridgeSequence, state: bridgeState(), message: envelope}) + "\n");
        return true;
    }

    function sendRequest(method, params, kind, context) {
        let id = nextRpcId++;
        let pending = Object.assign({}, pendingRpc);
        pending[String(id)] = {
            kind: kind || method,
            method: method,
            context: context || {}
        };
        pendingRpc = pending;
        if (kind === "prompt")
            activePromptRequestId = id;
        if (!sendEnvelope({
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params || {}
        })) {
            delete pending[String(id)];
            pendingRpc = pending;
            return -1;
        }
        return id;
    }

    function sendNotification(method, params) {
        sendEnvelope({
            jsonrpc: "2.0",
            method: method,
            params: params || {}
        });
    }

    function sendResponse(id, result) {
        sendEnvelope({
            jsonrpc: "2.0",
            id: id,
            result: result
        });
    }

    function sendErrorResponse(id, code, message) {
        sendEnvelope({
            jsonrpc: "2.0",
            id: id,
            error: {
                code: code,
                message: message
            }
        });
    }

    function startInitialization() {
        questionSupportNegotiated = true;
        sendRequest("initialize", {
            protocolVersion: protocolVersion,
            clientCapabilities: {
                fs: {
                    readTextFile: false,
                    writeTextFile: false
                },
                terminal: false,
                elicitation: {form: {}},
                plan: {}
            },
            clientInfo: {
                name: "rebos_shell",
                title: "rebos_shell",
                version: "1.0.0"
            }
        }, "initialize");
    }

    function chooseAuthMethod(result) {
        let methods = result && Array.isArray(result.authMethods) ? result.authMethods : [];
        if (methods.length === 0)
            return "";

        // The adapter's ChatGPT method is "chat-gpt", not "chatgpt".
        // Never fall back to its first method: that is API-key authentication.
        for (let method of methods) {
            if (method.id === "chat-gpt")
                return method.id;
        }
        return "";
    }

    function performSessionAction() {
        if (!authenticated || !pendingSessionAction)
            return;

        let action = pendingSessionAction;
        pendingSessionAction = null;
        questionToolNegotiated = true;
        let params = {
            cwd: action.cwd || workingDirectory(),
            mcpServers: [{
                name: "plan_usage",
                command: "python3",
                args: [usageScript, "--mcp"],
                env: []
            }, {
                name: "assistant_questions",
                command: "python3",
                args: [questionsScript],
                env: []
            }]
        };

        if (action.kind === "load" && action.sessionId) {
            let sessionCapabilities = agentCapabilities && agentCapabilities.sessionCapabilities
                ? agentCapabilities.sessionCapabilities : {};
            if (sessionCapabilities.resume !== undefined && sessionCapabilities.resume !== null) {
                params.sessionId = action.sessionId;
                sendRequest("session/resume", params, "session_resume", action);
                statusText = "Resuming " + currentModel.name + " session…";
                return;
            }
            if (agentCapabilities && agentCapabilities.loadSession === true) {
                params.sessionId = action.sessionId;
                suppressReplay = true;
                sendRequest("session/load", params, "session_load", action);
                statusText = "Loading " + currentModel.name + " session…";
                return;
            }
            pushSystemMessage(currentModel.name + " cannot restore this ACP session. A new session was started.");
        }

        sendRequest("session/new", params, "session_new", action);
        statusText = "Opening " + currentModel.name + " session…";
    }

    function applySessionSetup(result) {
        let setup = result || {};
        if (setup.sessionId)
            currentSessionId = setup.sessionId;
        sessionReady = currentSessionId.length > 0;
        suppressReplay = false;
        updateSessionConfiguration(setup);
        statusText = queuedPrompt ? "Thinking…" : "";
        saveCurrentChat();
        if (queuedPrompt)
            dispatchQueuedPrompt();
    }

    function updateSessionConfiguration(payload) {
        let data = payload || {};
        if (Array.isArray(data.configOptions))
            sessionConfigOptions = data.configOptions;

        if (data.models) {
            currentSessionModelId = data.models.currentModelId || currentSessionModelId;
            sessionModels = Array.isArray(data.models.availableModels) ? data.models.availableModels : sessionModels;
        }

        let modelOption = null;
        for (let i = 0; i < sessionConfigOptions.length; i++) {
            let option = sessionConfigOptions[i];
            if (option && (option.category === "model" || option.id === "model")) {
                modelOption = option;
                break;
            }
        }
        if (modelOption) {
            currentSessionModelId = String(modelOption.currentValue || "");
            let mapped = [];
            let choices = Array.isArray(modelOption.options) ? modelOption.options : [];
            for (let i = 0; i < choices.length; i++) {
                mapped.push({
                    modelId: String(choices[i].value || ""),
                    name: choices[i].name || String(choices[i].value || ""),
                    description: choices[i].description || ""
                });
            }
            sessionModels = mapped;
        }
    }

    function setSessionConfigOption(configId, value) {
        if (!sessionReady)
            return;
        let params = {
            sessionId: currentSessionId,
            configId: configId,
            value: value
        };
        if (typeof value === "boolean")
            params.type = "boolean";
        sendRequest("session/set_config_option", params, "set_config_option", {
            configId: configId,
            value: value
        });
    }

    function setSessionModel(modelId) {
        if (!sessionReady || isBusy || switchingSessionModel || !modelId || modelId === currentSessionModelId)
            return;
        if (!sessionModels.some(model => model.modelId === modelId)) {
            modelSwitchError = "This model is no longer available. Reopen the model list.";
            return;
        }
        modelSwitchError = "";
        pendingSessionModelId = modelId;
        for (let i = 0; i < sessionConfigOptions.length; i++) {
            let option = sessionConfigOptions[i];
            if (option && (option.category === "model" || option.id === "model")) {
                let requestId = sendRequest("session/set_config_option", {
                    sessionId: currentSessionId,
                    configId: option.id,
                    value: modelId
                }, "set_config_option", {modelId: modelId});
                if (requestId < 0) {
                    pendingSessionModelId = "";
                    modelSwitchError = "Connection lost. Reconnect to choose a model.";
                }
                return;
            }
        }
        let requestId = sendRequest("session/set_model", {
            sessionId: currentSessionId,
            modelId: modelId
        }, "set_model", {
            modelId: modelId
        });
        if (requestId < 0) {
            pendingSessionModelId = "";
            modelSwitchError = "Connection lost. Reconnect to choose a model.";
        }
    }

    function formatRpcError(error) {
        if (!error)
            return "Unknown ACP error";
        let message = error.message || "ACP request failed";
        if (error.data) {
            if (typeof error.data === "string")
                message += ": " + error.data;
            else if (error.data.message)
                message += ": " + error.data.message;
            else if (error.data.detail)
                message += ": " + error.data.detail;
        }
        return message;
    }

    function handleRpcError(entry, error) {
        let message = formatRpcError(error);
        console.warn("ACP " + (entry ? entry.method : "request") + " failed: " + message);
        if (entry && (entry.kind === "set_model" || (entry.kind === "set_config_option" && entry.context.modelId))) {
            pendingSessionModelId = "";
            modelSwitchError = "Could not switch models: " + message;
            return;
        }
        turnWatchdog.stop();

        if (entry && (entry.kind === "session_load" || entry.kind === "session_resume")) {
            suppressReplay = false;
            pushSystemMessage("Could not restore the ACP session: " + message + ". Starting a new session.");
            pendingSessionAction = {
                kind: "new"
            };
            performSessionAction();
            return;
        }

        lastError = message;
        isLoading = false;
        agentTurnActive = false;
        toolRunning = false;
        statusText = "";
        let hint = currentModel && currentModel.installHint ? "\n\n" + currentModel.installHint : "";
        pushSystemMessage(message + hint);
    }

    function handleResponse(message) {
        flushAssistantText();
        let key = String(message.id);
        let entry = pendingRpc[key];
        let next = Object.assign({}, pendingRpc);
        delete next[key];
        pendingRpc = next;
        if (!entry)
            return;
        if (message.error) {
            handleRpcError(entry, message.error);
            return;
        }

        let result = message.result || {};
        switch (entry.kind) {
        case "initialize": {
            if (result.protocolVersion !== protocolVersion) {
                handleRpcError(entry, {
                    message: "Unsupported ACP protocol version " + result.protocolVersion
                });
                return;
            }
            initialized = true;
            agentCapabilities = result.agentCapabilities || {};
            authMethods = Array.isArray(result.authMethods) ? result.authMethods : [];
            if (result._meta && result._meta.modelState) {
                currentSessionModelId = result._meta.modelState.currentModelId || "";
                sessionModels = result._meta.modelState.availableModels || [];
            }
            let authMethod = chooseAuthMethod(result);
            if (authMethod) {
                statusText = "Authenticating " + currentModel.name + "…";
                sendRequest("authenticate", {
                    methodId: authMethod
                }, "authenticate");
            } else {
                authenticated = true;
                performSessionAction();
            }
            break;
        }
        case "authenticate":
            authenticated = true;
            performSessionAction();
            break;
        case "session_new":
        case "session_load":
        case "session_resume":
            applySessionSetup(result);
            break;
        case "prompt":
            if (message.id === activePromptRequestId)
                activePromptRequestId = -1;
            turnWatchdog.stop();
            isLoading = false;
            agentTurnActive = false;
            toolRunning = false;
            statusText = "";
            activeAssistantIndex = -1;
            activeAssistantMessageId = "";
            saveCurrentChat();
            break;
        case "set_config_option":
            updateSessionConfiguration(result);
            if (entry.context.modelId) {
                if (!Array.isArray(result.configOptions) && !result.models)
                    currentSessionModelId = entry.context.modelId;
                pendingSessionModelId = "";
                modelSwitchError = "";
                saveCurrentChat();
            }
            statusText = "";
            break;
        case "set_model":
            currentSessionModelId = entry.context.modelId || currentSessionModelId;
            pendingSessionModelId = "";
            modelSwitchError = "";
            saveCurrentChat();
            statusText = "";
            break;
        }
    }

    property bool questionSupportNegotiated: false
    property bool questionToolNegotiated: false
    property list<var> questionRequests: []
    property var questionDrafts: ({})
    property var questionErrors: ({})
    property list<var> taskPlan: []
    property string taskPlanMarkdown: ""
    property list<var> activityLog: []
    readonly property list<var> activitySegments: taskPlan.length > 0
        ? taskPlan.concat(activityLog.filter(action => !taskPlan.some(step => step.content === action.planStep)))
        : activityLog

    // Use public turn text, never private thought chunks, for the overall goal.
    readonly property string activityTask: {
        let lastUser = -1;
        for (let i = currentChat.length - 1; i >= 0; i--) {
            if (currentChat[i].role === "user") { lastUser = i; break; }
        }
        let request = lastUser >= 0 ? String(currentChat[lastUser].content || "").trim() : "";
        let summary = "";
        for (let i = lastUser + 1; i < currentChat.length; i++) {
            let message = currentChat[i];
            if (message.role === "assistant" && !message.functionCall && message.content) {
                let paragraph = String(message.content).trim().split(/\n\s*\n/)[0];
                // Wait for a complete sentence so the heading does not flicker while streaming.
                let sentence = paragraph.match(/^(.+?[.!?])(?:\s|$)/);
                if (sentence) { summary = sentence[1]; break; }
            }
        }
        let text = (summary || request || "Work on your request").replace(/[*`#]/g, "").replace(/\s+/g, " ");
        return text.length > 240 ? text.slice(0, 237).trim() + "…" : text;
    }

    // Public progress belongs in the panel; never use private thought chunks.
    readonly property string activityProgress: {
        let lastUser = -1;
        for (let i = currentChat.length - 1; i >= 0; i--) {
            if (currentChat[i].role === "user") { lastUser = i; break; }
        }
        let opening = currentChat.findIndex((message, index) => index > lastUser
            && message.role === "assistant" && !message.functionCall && message.content);
        for (let i = currentChat.length - 1; i > opening && i > lastUser; i--) {
            let message = currentChat[i];
            if (message.role === "user") break;
            if (message.role !== "assistant" || message.functionCall || !message.content) continue;
            let paragraph = String(message.content).trim().split(/\n\s*\n/)[0];
            if (!/[.!?](?:\s|$)/.test(paragraph)) continue;
            let text = paragraph.replace(/[*`#]/g, "").replace(/\s+/g, " ").trim();
            if (text === activityTask) return "";
            return text.length > 600 ? text.slice(0, 597).trim() + "…" : text;
        }
        return "";
    }

    function activityText(text) {
        return String(text || "")
            .replace(/(?:[~.\w-]+\/)*([.\w-]+)\.(?:qml|js|ts|tsx|jsx|py|md|json|toml|yaml|yml|kdl|css|sh|conf|ini)\b/g, function(path, name) {
                let known = {AssistantActivity: "the activity panel", AiSession: "the assistant session",
                    AssistantSidebar: "the assistant sidebar", test_ai_questions: "the assistant question checks"};
                if (known[name]) return known[name];
                let words = name.replace(/^test[_-]/, "").replace(/([a-z])([A-Z])/g, "$1 $2")
                    .replace(/[_-]+/g, " ").toLowerCase();
                return "the " + words + (/^test[_-]/.test(name) ? " checks" : " file");
            })
            .replace(/QML syntax validation|syntax validation/gi, "a check for writing mistakes")
            .replace(/syntax errors/gi, "writing mistakes")
            .replace(/current implementation/gi, "current behavior")
            .replace(/automated tests/gi, "automatic checks")
            .replace(/\s+/g, " ").trim();
    }

    function activitySentence(entry) {
        let title = String(entry.content || "").replace(/\s+/g, " ").trim();
        let message = currentChat.find(item => item.functionCall && item.functionCall.id === entry.id);
        let args = entry.rawInput || message?.functionCall?.args || {};
        let command = args.command || args.cmd || "";
        command = Array.isArray(command) ? command.join(" ") : String(command);
        let source = command || title;
        // Preserve descriptive titles, including those naming files or test suites.
        let technical = /^(?:mcp__|functions\.|tools\.|[\w]+\.[\w]+\s*\(|(?:rg|cat|sed|grep|python\d*|pytest|qmllint|git|bash|sh)\s)|[{}\n]/;
        let descriptive = title.split(" ").length >= 4 && !technical.test(title)
            && !/^(?:Run a command for this task|Search for the information needed|Check that the changes work correctly|Read the relevant files and settings)/i.test(title);
        if (descriptive)
            return activityText(title.charAt(0).toUpperCase() + title.slice(1) + (/[.!?…]$/.test(title) ? "" : "."));

        let paths = [args.file_path, args.path, ...(Array.isArray(args.paths) ? args.paths : [])]
            .filter(value => typeof value === "string");
        // Extract only file/directory targets, never arbitrary arguments or output.
        let matches = source.match(/(?:[~.\w-]+\/)*[.\w-]+\.(?:qml|js|ts|tsx|jsx|py|md|json|toml|yaml|yml|kdl|css|sh|conf|ini)\b|(?:[~.\w-]+\/)+[.\w-]+/g) || [];
        let patch = String(args.patch || args.input || "");
        let patchPaths = /\*\*\* (?:Update|Add|Delete) File: ([^\n]+)/g;
        let match;
        while ((match = patchPaths.exec(patch)) !== null)
            paths.push(match[1]);
        let targets = [...new Set(paths.concat(matches).map(path => path.split("/").filter(Boolean).pop()).filter(Boolean))];
        let target = targets.slice(0, 3).join(", ") + (targets.length > 3 ? " and " + (targets.length - 3) + " more files" : "");
        let kind = entry.kind || "";
        let action;
        if (/\b(?:qmllint|pytest|unittest|ctest|eslint)\b|\b(?:npm|pnpm|cargo)\s+(?:run\s+)?test\b/.test(source))
            action = "Check " + (target || "the affected behavior") + " for errors using "
                + (/qmllint/.test(source) ? "QML syntax validation" : "the automated tests");
        else if (/\b(?:rg|grep|find)\s/.test(source) || kind === "search")
            action = "Search " + (target || "the project files") + " for matching code and settings";
        else if (/\b(?:cat|sed|head|tail|read_file)\s/.test(source) || kind === "read")
            action = "Inspect " + (target || "the relevant configuration") + " to understand its current implementation";
        else if (/apply_patch|write_file|edit_file/.test(source) || kind === "edit" || patch.includes("*** Begin Patch"))
            action = "Update " + (target || "the affected files") + " with the requested changes";
        else if (kind === "fetch")
            action = "Retrieve " + (args.url ? "information from " + String(args.url).split("/")[2] : "online reference information");
        else
            action = "Run a local operation" + (target ? " involving " + target : " for the current step");
        let purpose = String(entry.planStep || entry.purpose || entry.task || activityTask || "").replace(/[*`#]/g, "").replace(/\s+/g, " ").trim();
        let purposeSentence = purpose.match(/^(.+?[.!?])(?:\s|$)/);
        if (purposeSentence) purpose = purposeSentence[1];
        if (purpose && purpose.toLowerCase() !== action.toLowerCase())
            action += ". " + purpose.slice(0, 360);
        return activityText(action + (/[.!?…]$/.test(action) ? "" : "."));
    }

    function activityExplanation(entry, isPlan) {
        if (!entry)
            return "";
        if (isPlan) {
            let actions = activityLog.filter(action => action.planStep === entry.content);
            let details = actions.map(action => activityExplanation(action, false));
            return details.length ? details.join("\n\n────────\n\n")
                : "No changes or command output have been reported for this step yet.";
        }
        let parts = [];
        let message = currentChat.find(item => item.functionCall && item.functionCall.id === entry.id);
        if (message) {
            let args = message.functionCall.args || {};
            let command = args.command || args.cmd;
            if (command)
                parts.push("Command:\n" + (Array.isArray(command) ? command.join(" ") : String(command)));
            let patch = args.patch || (typeof args.input === "string" && args.input.includes("*** Begin Patch") ? args.input : "");
            if (patch)
                parts.push("Changes:\n" + String(patch).slice(0, 12000));
            let output = String(message.content || "").trim();
            if (output)
                parts.push("Reported details:\n" + output.slice(0, 12000)
                    + (output.length > 12000 ? "\n\nMore output is available in the chat's tool card." : ""));
        }
        return parts.length ? parts.join("\n\n") : "No changes or command output have been reported for this action yet.";
    }

    Timer {
        interval: 1000
        running: root.bridgeAttached && (!root.questionSupportNegotiated || !root.questionToolNegotiated) && !root.isBusy
            && Object.keys(root.pendingRpc).length === 0
        onTriggered: {
            root.pendingSessionAction = {kind: root.currentSessionId ? "load" : "new",
                sessionId: root.currentSessionId, cwd: root.currentChatCwd || root.workingDirectory()};
            root.sessionReady = false;
            root.bridgeAttached = false;
            agentProcess.write(JSON.stringify({bridge: "reset"}) + "\n");
        }
    }

    function recordActivity(update) {
        let id = update.toolCallId;
        if (!id)
            return;
        let entries = Array.from(activityLog);
        let index = entries.findIndex(entry => entry.id === id);
        let previous = index >= 0 ? entries[index] : {};
        let entry = {id: id, content: update.title || previous.content || update.kind || "Tool",
            kind: update.kind || previous.kind || "",
            rawInput: update.rawInput || previous.rawInput || {},
            purpose: previous.purpose !== undefined ? previous.purpose : activityProgress,
            task: previous.task !== undefined ? previous.task : activityTask,
            planStep: previous.planStep !== undefined ? previous.planStep
                : (taskPlan.find(step => step.status === "in_progress")?.content || ""),
            status: update.status || previous.status || "pending"};
        if (index >= 0)
            entries[index] = entry;
        else
            entries.push(entry);
        activityLog = entries.slice(-80);
        bridgeDirty = true;
    }

    function questionFields(request) {
        return Questions.fields(request.schema);
    }

    function handleQuestionRequest(requestId, params) {
        if (params.mode !== "form" || !params.requestedSchema) {
            sendErrorResponse(requestId, -32602, "Only form questions are supported");
            return;
        }
        if (params.sessionId && currentSessionId && params.sessionId !== currentSessionId) {
            sendResponse(requestId, {action: "cancel"});
            return;
        }
        let fields = Questions.fields(params.requestedSchema);
        if (fields.some(field => !["string", "number", "integer", "boolean", "array"].includes(field.type))) {
            sendErrorResponse(requestId, -32602, "Unsupported question field type");
            return;
        }
        let requests = Array.from(questionRequests).filter(request => request.requestId !== requestId);
        requests.push({requestId: requestId, message: params.message || "Your input is needed",
            schema: params.requestedSchema, agent: currentModel ? currentModel.name : "Assistant"});
        questionRequests = requests;
        turnWatchdog.stop();
        statusText = "Waiting for your answer…";
        bridgeDirty = true;
    }

    function setQuestionAnswer(requestId, key, value) {
        let drafts = Object.assign({}, questionDrafts);
        let draft = Object.assign({}, drafts[String(requestId)] || {});
        draft[key] = value;
        drafts[String(requestId)] = draft;
        questionDrafts = drafts;
        let errors = Object.assign({}, questionErrors);
        delete errors[String(requestId)];
        questionErrors = errors;
        bridgeDirty = true;
    }

    function removeQuestion(requestId) {
        if (!Array.from(questionRequests).some(request => request.requestId === requestId))
            return;
        questionRequests = Array.from(questionRequests).filter(request => request.requestId !== requestId);
        let drafts = Object.assign({}, questionDrafts);
        delete drafts[String(requestId)];
        questionDrafts = drafts;
        let errors = Object.assign({}, questionErrors);
        delete errors[String(requestId)];
        questionErrors = errors;
        bridgeDirty = true;
        if (questionRequests.length === 0 && Object.keys(pendingPermissions).length === 0) {
            statusText = agentTurnActive ? "Continuing…" : "";
            if (agentTurnActive)
                turnWatchdog.restart();
        }
    }

    function answerQuestion(requestId, action) {
        let request = Array.from(questionRequests).find(item => item.requestId === requestId);
        if (!request || !["accept", "decline", "cancel"].includes(action))
            return false;
        let result = {action: action};
        if (action === "accept") {
            let checked = Questions.validate(request.schema, questionDrafts[String(requestId)] || {});
            if (checked.error) {
                let errors = Object.assign({}, questionErrors);
                errors[String(requestId)] = checked.error;
                questionErrors = errors;
                bridgeDirty = true;
                return false;
            }
            result.content = checked.content;
            let answers = Questions.fields(request.schema).filter(field => checked.content[field.key] !== undefined)
                .map(field => field.title + ": " + (field.secret ? "[private answer]" : String(checked.content[field.key])));
            let chat = Array.from(currentChat);
            chat.push({role: "user", content: answers.join("\n"), questionAnswer: true});
            currentChat = chat;
            activeAssistantIndex = -1;
            activeAssistantMessageId = "";
        }
        removeQuestion(requestId);
        sendResponse(requestId, result);
        saveCurrentChat();
        return true;
    }

    function handleAgentRequest(message) {
        flushAssistantText();
        if (message.method === "elicitation/create") {
            handleQuestionRequest(message.id, message.params || {});
            return;
        }
        if (message.method === "$/cancel_request" || message.method === "notifications/cancelled") {
            let params = message.params || {};
            removeQuestion(params.id !== undefined ? params.id : params.requestId);
            return;
        }
        if (message.method === "session/request_permission") {
            handlePermissionRequest(message.id, message.params || {});
            return;
        }

        // These capabilities are intentionally not advertised. Rejecting a
        // non-conforming request is safer than silently touching the system.
        if (message.id !== undefined)
            sendErrorResponse(message.id, -32601, "ACP client method not supported: " + message.method);
    }

    function handleAcpLine(line) {
        let trimmed = (line || "").trim();
        if (!trimmed)
            return;
        let message;
        try {
            message = JSON.parse(trimmed);
        } catch (e) {
            console.warn("Ignoring non-JSON ACP stdout: " + trimmed.substring(0, 200));
            return;
        }

        if (message.method) {
            if (message.method === "session/update") {
                handleSessionUpdate(message.params || {});
            } else {
                handleAgentRequest(message);
            }
            return;
        }
        if (message.id !== undefined)
            handleResponse(message);
    }

    Process {
        id: agentProcess
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.queueBridgeLine(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn("Assistant relay: " + data)
        }

        onStarted: {
            write(JSON.stringify({bridge: "attach", command: root.currentModel.command,
                cwd: root.workingDirectory(), path: Quickshell.env("PATH")}) + "\n");
        }

        onExited: (exitCode, exitStatus) => {
            let wasExpected = root.expectedProcessStop;
            let shouldRestart = root.restartPending;
            root.bridgeAttached = false;
            root.expectedProcessStop = false;
            root.restartPending = false;
            turnWatchdog.stop();
            if (shouldRestart) {
                Qt.callLater(root.startAgentProcess);
            } else if (!wasExpected && root.featureEnabled) {
                // A relay failure does not mean the agent or turn has stopped.
                root.statusText = root.lastError || "Reconnecting to assistant…";
                bridgeReconnectTimer.restart();
            }
        }
    }

    function handleAgentStderr(data) {
        let line = (data || "").trim();
        if (!line)
            return;
        agentStderrTail = (agentStderrTail + "\n" + line).slice(-6000);
        if (!agentTurnActive || turnFailureHandled)
            return;

        let lower = line.toLowerCase();
        if (lower.includes("quota reached") || lower.includes("quota_exhausted")
                || lower.includes("resource_exhausted")) {
            failActiveTurn(
                currentModel.name + " reported that the active model's provider quota is exhausted."
                + "\n\nChoose another model with `/model`, or update the model in "
                + currentModel.name + "."
            );
        } else if (lower.includes("rate limit") || lower.includes("status\":429")
                || lower.includes("[429]")) {
            failActiveTurn(
                currentModel.name + " was rate-limited by the active model provider."
                + "\n\nWait for the provider reset or choose another model with `/model`."
            );
        } else if (lower.includes("unauthorized") || lower.includes("authentication failed")
                || lower.includes("invalid api key")) {
            failActiveTurn(
                currentModel.name + " could not authenticate with the active model provider."
                + "\n\nComplete the agent's login flow, then reconnect it."
            );
        }
    }

    // ============================================
    // ACP SESSION UPDATES
    // ============================================

    property string activeAssistantMessageId: ""
    property int activeAssistantIndex: -1
    property var pendingPermissions: ({})
    property string pendingAssistantText: ""
    property string pendingAssistantMessageId: ""

    Timer {
        id: assistantTextTimer
        interval: 33
        onTriggered: root.flushAssistantText()
    }

    function queueAssistantText(update) {
        let messageId = update.messageId || "";
        if (pendingAssistantText && messageId !== pendingAssistantMessageId)
            flushAssistantText();
        pendingAssistantMessageId = messageId;
        pendingAssistantText += contentBlockText(update.content);
        // Do not restart: continuous output must still render regularly.
        if (pendingAssistantText && !assistantTextTimer.running)
            assistantTextTimer.start();
    }

    function flushAssistantText() {
        assistantTextTimer.stop();
        if (!pendingAssistantText)
            return;
        let update = {
            messageId: pendingAssistantMessageId,
            content: { type: "text", text: pendingAssistantText }
        };
        pendingAssistantText = "";
        pendingAssistantMessageId = "";
        appendAgentMessage(update);
    }

    function contentBlockText(content) {
        if (!content)
            return "";
        if (content.type === "text")
            return content.text || "";
        if (content.type === "resource" && content.resource)
            return content.resource.text || content.resource.uri || "";
        if (content.type === "resource_link")
            return content.name || content.uri || "";
        if (content.type === "image")
            return "[Image]";
        if (content.type === "audio")
            return "[Audio]";
        return "";
    }

    function toolContentText(content) {
        if (!Array.isArray(content))
            return "";
        let parts = [];
        for (let i = 0; i < content.length; i++) {
            let item = content[i];
            if (!item)
                continue;
            if (item.type === "content")
                parts.push(contentBlockText(item.content));
            else if (item.type === "diff") {
                let diff = "Changed " + (item.path || "file");
                if (item.oldText !== undefined)
                    diff += "\n\nBefore:\n" + item.oldText;
                if (item.newText !== undefined)
                    diff += "\n\nAfter:\n" + item.newText;
                parts.push(diff);
            } else if (item.type === "terminal")
                parts.push(item.output || "");
        }
        return parts.filter(part => part && part.length > 0).join("\n\n");
    }

    function appendAgentMessage(update) {
        let text = contentBlockText(update.content);
        if (!text)
            return;
        let messageId = update.messageId || "";
        let shouldCreate = activeAssistantIndex < 0 || activeAssistantIndex >= currentChat.length;
        if (!shouldCreate && messageId && activeAssistantMessageId && messageId !== activeAssistantMessageId)
            shouldCreate = true;

        let chat = Array.from(currentChat);
        if (shouldCreate) {
            chat.push({
                role: "assistant",
                content: text,
                model: activeAgentLabel(),
                acpMessageId: messageId
            });
            activeAssistantIndex = chat.length - 1;
            activeAssistantMessageId = messageId;
        } else {
            let existing = chat[activeAssistantIndex] || {};
            chat[activeAssistantIndex] = Object.assign({}, existing, {
                content: (existing.content || "") + text,
                model: activeAgentLabel(),
                acpMessageId: messageId || existing.acpMessageId || ""
            });
        }
        currentChat = chat;
    }

    function findToolMessageIndex(toolCallId) {
        for (let i = currentChat.length - 1; i >= 0; i--) {
            let msg = currentChat[i];
            if (msg && msg.functionCall && msg.functionCall.id === toolCallId)
                return i;
        }
        return -1;
    }

    function updateToolRunning() {
        let running = false;
        let turnStart = 0;
        for (let i = currentChat.length - 1; i >= 0; i--) {
            if (currentChat[i] && currentChat[i].role === "user") {
                turnStart = i;
                break;
            }
        }
        for (let i = turnStart; i < currentChat.length; i++) {
            let msg = currentChat[i];
            if (msg && msg.toolStatus && (msg.toolStatus === "pending" || msg.toolStatus === "in_progress")) {
                running = true;
                break;
            }
        }
        toolRunning = running;
    }

    function upsertToolCall(update) {
        recordActivity(update);
        let toolCallId = update.toolCallId || ("tool_" + Date.now());
        let index = findToolMessageIndex(toolCallId);
        let chat = Array.from(currentChat);
        let status = update.status || "pending";
        let title = update.title || update.kind || "Tool";
        let output = toolContentText(update.content);
        let args = update.rawInput || {};

        if (index < 0) {
            chat.push({
                role: "assistant",
                content: output,
                model: activeAgentLabel(),
                functionCall: {
                    id: toolCallId,
                    name: title,
                    args: args
                },
                functionPending: false,
                functionApproved: status === "completed" ? true : undefined,
                toolStatus: status,
                toolKind: update.kind || "other"
            });
        } else {
            let existing = chat[index];
            let existingCall = existing.functionCall || {};
            chat[index] = Object.assign({}, existing, {
                content: output || existing.content || "",
                functionCall: {
                    id: toolCallId,
                    name: update.title || existingCall.name || title,
                    args: update.rawInput || existingCall.args || {}
                },
                functionApproved: status === "completed" ? true
                    : (status === "failed" ? false : existing.functionApproved),
                toolStatus: status,
                toolKind: update.kind || existing.toolKind || "other"
            });
        }
        currentChat = chat;
        updateToolRunning();
        if (status === "completed" || status === "failed")
            saveCurrentChat();
    }

    function handlePermissionRequest(requestId, params) {
        let tool = params.toolCall || {};
        let toolCallId = tool.toolCallId || ("permission_" + requestId);
        upsertToolCall(tool);
        let index = findToolMessageIndex(toolCallId);
        if (index < 0) {
            sendResponse(requestId, {
                outcome: {
                    outcome: "cancelled"
                }
            });
            return;
        }

        let permissions = Object.assign({}, pendingPermissions);
        permissions[String(requestId)] = {
            requestId: requestId,
            toolCallId: toolCallId,
            options: Array.isArray(params.options) ? params.options : []
        };
        pendingPermissions = permissions;

        let chat = Array.from(currentChat);
        chat[index] = Object.assign({}, chat[index], {
            functionPending: true,
            permissionRequestId: requestId
        });
        currentChat = chat;
        turnWatchdog.stop();
        statusText = "Waiting for permission…";
    }

    function choosePermissionOption(options, allow) {
        let preferredKinds = allow ? ["allow_once", "allow_always"] : ["reject_once", "reject_always"];
        for (let p = 0; p < preferredKinds.length; p++) {
            for (let i = 0; i < options.length; i++) {
                if (options[i].kind === preferredKinds[p])
                    return options[i].optionId;
            }
        }
        return options.length > 0 ? options[0].optionId : "";
    }

    function resolvePermission(index, allow) {
        if (index < 0 || index >= currentChat.length)
            return;
        let message = currentChat[index];
        let requestId = message.permissionRequestId;
        let permission = pendingPermissions[String(requestId)];
        if (!permission)
            return;

        let permissions = Object.assign({}, pendingPermissions);
        delete permissions[String(requestId)];
        pendingPermissions = permissions;
        let chat = Array.from(currentChat);
        chat[index] = Object.assign({}, chat[index], {
            functionPending: false,
            functionApproved: allow
        });
        currentChat = chat;
        statusText = allow ? "Running tool…" : "Tool rejected";
        if (allow && agentTurnActive && questionRequests.length === 0)
            turnWatchdog.restart();
        let optionId = choosePermissionOption(permission.options, allow);
        if (optionId) {
            sendResponse(requestId, {
                outcome: {
                    outcome: "selected",
                    optionId: optionId
                }
            });
        } else {
            sendResponse(requestId, {
                outcome: {
                    outcome: "cancelled"
                }
            });
        }

        saveCurrentChat();
    }

    function approveCommand(index) {
        resolvePermission(index, true);
    }

    function rejectCommand(index) {
        resolvePermission(index, false);
    }

    function handleSessionUpdate(params) {
        if (params.sessionId && currentSessionId && params.sessionId !== currentSessionId)
            return;
        if (suppressReplay)
            return;
        if (agentTurnActive && questionRequests.length === 0 && Object.keys(pendingPermissions).length === 0)
            turnWatchdog.restart();

        let update = params.update || {};
        if (update.sessionUpdate !== "agent_message_chunk")
            flushAssistantText();
        switch (update.sessionUpdate) {
        case "agent_message_chunk":
            queueAssistantText(update);
            statusText = "Responding…";
            break;
        case "agent_thought_chunk": {
            let messageId = update.messageId || "";
            if (messageId !== thoughtMessageId)
                thoughtText = "";
            thoughtMessageId = messageId;
            thoughtText = (thoughtText + contentBlockText(update.content)).slice(-4000);
            statusText = thoughtText.trim() || "Thinking through your request…";
            break;
        }
        case "tool_call":
        case "tool_call_update":
            upsertToolCall(update);
            if (update.status === "in_progress")
                statusText = update.title || "Running tool…";
            break;
        case "plan":
        case "plan_update":
            if (Array.isArray(update.entries))
                taskPlan = update.entries.map(entry => ({content: entry.content || entry.step || "Step", status: entry.status || "pending"}));
            else if (update.plan && update.plan.type === "markdown")
                taskPlanMarkdown = update.plan.content || "";
            statusText = "Updating the plan…";
            bridgeDirty = true;
            break;
        case "plan_removed":
            taskPlan = [];
            taskPlanMarkdown = "";
            break;
        case "available_commands_update":
            availableCommands = update.availableCommands || update.commands || [];
            break;
        case "current_mode_update":
            currentModeId = update.currentModeId || update.modeId || "";
            break;
        case "config_option_update":
            updateSessionConfiguration(update);
            break;
        case "usage_update":
            contextUsed = update.used || 0;
            contextSize = update.size || 0;
            if (update.cost) {
                sessionCost = update.cost.amount || 0;
                sessionCostCurrency = update.cost.currency || "";
            }
            break;
        }
    }

    // ============================================
    // CHAT API
    // ============================================

    property bool isLoading: false
    property bool toolRunning: false
    property bool agentTurnActive: false
    readonly property bool isBusy: isLoading || toolRunning || agentTurnActive
    readonly property bool supportsMessageEditing: false
    readonly property bool supportsRegeneration: false
    property string statusText: ""
    property string thoughtText: ""
    property string thoughtMessageId: ""
    property string lastError: ""

    Timer {
        id: turnWatchdog
        interval: 120000
        repeat: false
        onTriggered: root.failActiveTurn(
            "The ACP agent produced no updates for two minutes, so the stalled turn was cancelled."
            + "\n\nCheck the agent's provider connection or select another agent/model."
        )
    }

    property var currentChat: []
    property string currentChatId: ""
    property string currentChatAgentId: ""
    property string currentSessionId: ""
    property string currentChatCwd: ""
    property var chatHistory: []

    signal chatModelChanged
    signal historyModelChanged

    function activeAgentLabel() {
        let agent = currentModel ? currentModel.name : "ACP";
        if (currentSessionModelId)
            return agent + " · " + currentSessionModelId;
        return agent;
    }

    function pushSystemMessage(message) {
        if (!message)
            return;
        let chat = Array.from(currentChat);
        chat.push({
            role: "system",
            content: message
        });
        currentChat = chat;
        saveCurrentChat();
    }

    function failActiveTurn(message) {
        if (!agentTurnActive || turnFailureHandled)
            return;
        turnFailureHandled = true;
        cancelGeneration(false);
        lastError = message;
        pushSystemMessage(message);
    }

    function commandHelp() {
        let lines = [
            "🤖 **ACP Assistant Commands**",
            "",
            "**`/new`** — start a fresh ACP session",
            "**`/agent`** — show Codex",
            "**`/agent <name>`** — switch ACP agent",
            "**`/model`** — list models exposed by the active agent",
            "**`/model <id>`** — select an agent model",
            "**`/status`** — show the active ACP connection",
            "**`/usage`** — check shared Codex plan quota and reset times",
            "**`/terminal`** — open a terminal in the current working directory"
        ];
        if (availableCommands.length > 0) {
            lines.push("", "**Agent commands**");
            for (let i = 0; i < availableCommands.length; i++) {
                let command = availableCommands[i];
                lines.push("`/" + (command.name || "") + "` — " + (command.description || ""));
            }
        }
        return lines.join("\n");
    }

    function handleLocalCommand(message) {
        if (!message.startsWith("/"))
            return false;
        let parts = message.substring(1).trim().split(/\s+/);
        let command = (parts.shift() || "").toLowerCase();
        let argument = parts.join(" ").trim();

        if (command === "new") {
            Ai.newSession();
            return true;
        }
        if (command === "help") {
            pushSystemMessage(commandHelp());
            return true;
        }
        if (command === "usage") {
            refreshPlanUsage(true);
            return true;
        }
        if (command === "terminal") {
            openTerminal();
            return true;
        }
        if (command === "agent") {
            if (argument) {
                setModel(argument);
            } else {
                let names = models.map(agent => "`" + agent.id + "` — " + agent.name);
                pushSystemMessage("Available ACP agents:\n\n" + names.join("\n"));
            }
            return true;
        }
        if (command === "model") {
            if (argument) {
                setSessionModel(argument);
            } else if (sessionModels.length > 0) {
                let max = Math.min(sessionModels.length, 40);
                let names = [];
                for (let i = 0; i < max; i++) {
                    let model = sessionModels[i];
                    names.push("`" + (model.modelId || "") + "` — " + (model.name || model.modelId || ""));
                }
                if (sessionModels.length > max)
                    names.push("…and " + (sessionModels.length - max) + " more");
                pushSystemMessage("Active model: `" + currentSessionModelId + "`\n\n" + names.join("\n"));
            } else {
                pushSystemMessage("The active ACP agent has not exposed a model selector.");
            }
            return true;
        }
        if (command === "status") {
            pushSystemMessage(
                "**Agent:** " + (currentModel ? currentModel.name : "None")
                + "\n**ACP:** " + (sessionReady ? "connected" : "disconnected")
                + "\n**Session:** `" + (currentSessionId || "none") + "`"
                + "\n**Model:** `" + (currentSessionModelId || "agent default") + "`"
                + "\n**Working directory:** `" + workingDirectory() + "`"
            );
            return true;
        }
        return false;
    }

    function sendMessage(message, attachments) {
        if (switchingSessionModel)
            return;
        let text = message || "";
        if (handleLocalCommand(text))
            return;
        if (!text.trim() && (!attachments || attachments.length === 0))
            return;
        if (isBusy) {
            pushSystemMessage("The active ACP turn is still running. Stop it before sending another message.");
            return;
        }

        taskPlan = [];
        taskPlanMarkdown = "";
        activityLog = [];
        thoughtText = "";
        thoughtMessageId = "";
        if (!currentChatId)
            currentChatId = String(Date.now()) + "-" + channelId;
        let chat = Array.from(currentChat);
        chat.push({
            role: "user",
            content: text,
            attachments: attachments || []
        });
        currentChat = chat;
        currentChatAgentId = currentAgentId;
        currentChatCwd = workingDirectory();
        saveCurrentChat();

        queuedPrompt = {
            text: text,
            attachments: attachments || []
        };
        isLoading = true;
        agentTurnActive = true;
        turnFailureHandled = false;
        lastError = "";
        statusText = sessionReady ? "Thinking…" : "Connecting to " + currentModel.name + "…";
        activeAssistantIndex = -1;
        activeAssistantMessageId = "";

        if (sessionReady && agentProcess.running && processAgentId === currentAgentId)
            dispatchQueuedPrompt();
        else
            ensureConnection({
                kind: currentSessionId ? "load" : "new",
                sessionId: currentSessionId,
                cwd: currentChatCwd
            });
    }

    function dispatchQueuedPrompt() {
        if (!queuedPrompt || !sessionReady)
            return;
        let queued = queuedPrompt;
        queuedPrompt = null;
        let prompt = [];
        if (queued.text)
            prompt.push({
                type: "text",
                text: queued.text
            });

        prompt.push({type: "text", text: "Shell activity preference: Begin with one concise, descriptive sentence stating the overall task you are working on. For multi-step work, keep the plan in plain English with specific steps describing the intended result. Give concise public progress updates explaining what you found, what you are doing next, and why it helps the request. Use everyday English in visible activity rows: describe the feature, action and purpose rather than filenames, command names or technical jargon. For example, say Check that activity rows explain the work clearly. Put filenames and technical identifiers in expandable details. Use specific descriptive tool titles where supported, avoiding vague labels such as Running a command or Reading files. Keep code, patches, commands and relevant output in expandable details; the visible activity should explain the purpose and progress of the work."});
        prompt.push({type: "text", text: "Shell assistant interaction preference: Use the assistant_questions ask_user_question tool to ask a focused, answerable question early when a meaningful preference, scope choice, or missing detail could change the result. Offer 2–3 clear choices when useful, with the recommendation first. Ask more actively instead of silently choosing subjective details. Wait for the answer before dependent changes. Continue routine authorized work without extra permission questions. Do not repeat answered questions or ask unnecessary questions for clear, simple tasks. If the tool is unavailable, ask a concise question in chat."});

        let supportsImages = agentCapabilities && agentCapabilities.promptCapabilities
            && agentCapabilities.promptCapabilities.image === true;
        let attachments = queued.attachments || [];
        if (attachments.length > 0 && !supportsImages) {
            failActiveTurn(currentModel.name + " does not support image prompts. Select an agent with image support and try again.");
            return;
        }
        for (let i = 0; i < attachments.length; i++) {
            let attachment = attachments[i];
            if (supportsImages && attachment && attachment.base64) {
                prompt.push({
                    type: "image",
                    mimeType: attachment.mimeType || "image/png",
                    data: attachment.base64
                });
            }
        }
        activePromptRequestId = sendRequest("session/prompt", {
            sessionId: currentSessionId,
            prompt: prompt
        }, "prompt");
        turnWatchdog.restart();
        statusText = "Thinking…";
    }

    function cancelGeneration(announce) {
        flushAssistantText();
        turnWatchdog.stop();
        if (currentSessionId && agentProcess.running) {
            sendNotification("session/cancel", {
                sessionId: currentSessionId
            });
            if (activePromptRequestId >= 0) {
                sendNotification("$/cancel_request", {
                    id: activePromptRequestId
                });
            }
        }

        let questions = Array.from(questionRequests);
        for (let question of questions)
            answerQuestion(question.requestId, "cancel");
        activityLog = activityLog.map(entry => (entry.status === "in_progress" || entry.status === "pending")
            ? Object.assign({}, entry, {status: "stopped"}) : entry);
        taskPlan = taskPlan.map(entry => entry.status === "in_progress"
            ? Object.assign({}, entry, {status: "stopped"}) : entry);
        let permissionKeys = Object.keys(pendingPermissions);
        for (let i = 0; i < permissionKeys.length; i++) {
            let pending = pendingPermissions[permissionKeys[i]];
            sendResponse(pending.requestId, {
                outcome: {
                    outcome: "cancelled"
                }
            });
        }
        pendingPermissions = {};
        activePromptRequestId = -1;
        queuedPrompt = null;
        isLoading = false;
        agentTurnActive = false;
        toolRunning = false;
        statusText = announce ? "Stopped" : "";

        let chat = Array.from(currentChat);
        for (let i = 0; i < chat.length; i++) {
            if (chat[i] && chat[i].functionPending === true) {
                chat[i] = Object.assign({}, chat[i], {
                    functionPending: false,
                    functionApproved: false,
                    toolStatus: "failed"
                });
            }
        }
        currentChat = chat;
        saveCurrentChat();
    }

    function createNewChat() {
        cancelGeneration(false);
        currentChat = [];
        taskPlan = [];
        taskPlanMarkdown = "";
        activityLog = [];
        currentChatId = String(Date.now()) + "-" + channelId;
        currentChatAgentId = currentAgentId;
        currentChatCwd = workingDirectory();
        currentSessionId = "";
        sessionReady = false;
        activeAssistantIndex = -1;
        activeAssistantMessageId = "";
        pendingPermissions = {};
        chatModelChanged();
        if (featureEnabled) {
            ensureConnection({
                kind: "new",
                cwd: currentChatCwd
            });
        }
    }

    function regenerateResponse(index) {
        pushSystemMessage("Regeneration is owned by the ACP agent. Ask it to reconsider or regenerate the response.");
    }

    function updateMessage(index, newContent) {
        pushSystemMessage("ACP session history is agent-owned, so previous turns cannot be edited locally.");
    }

    // ============================================
    // CHAT PERSISTENCE
    // ============================================

    property string chatDir: Quickshell.env("HOME") + "/.local/share/rebos_shell/chats"
    property string pendingSavePath: ""
    property string pendingSaveData: ""

    FileView {
        id: chatFileView
        printErrors: false
        atomicWrites: true
    }

    function chatEnvelope() {
        return {
            version: 2,
            protocol: "acp",
            agentId: currentChatAgentId || currentAgentId,
            sessionId: currentSessionId,
            cwd: currentChatCwd || workingDirectory(),
            taskPlan: taskPlan,
            taskPlanMarkdown: taskPlanMarkdown,
            activityLog: activityLog,
            messages: currentChat
        };
    }

    function saveCurrentChat() {
        flushAssistantText();
        if (!currentChatId || currentChat.length === 0)
            return;
        pendingSavePath = chatDir + "/" + currentChatId + ".json";
        pendingSaveData = JSON.stringify(chatEnvelope(), null, 2);
        if (!ensureChatDirProcess.running) {
            ensureChatDirProcess.command = ["/usr/bin/mkdir", "-p", chatDir];
            ensureChatDirProcess.running = true;
        }
    }

    Process {
        id: ensureChatDirProcess
        onExited: exitCode => {
            if (exitCode !== 0 || !root.pendingSavePath)
                return;
            chatFileView.path = root.pendingSavePath;
            chatFileView.setText(root.pendingSaveData);
            root.pendingSavePath = "";
            root.pendingSaveData = "";
            root.reloadHistory();
        }
    }

    function deleteChat(id) {
        if (!id)
            return;
        if (id === currentChatId)
            createNewChat();
        deleteChatProcess.command = ["/usr/bin/rm", "-f", chatDir + "/" + id + ".json"];
        deleteChatProcess.running = true;
    }

    Process {
        id: deleteChatProcess
        onExited: root.reloadHistory()
    }

    function reloadHistory() {
        let pyScript = `import glob, json, os
chat_dir = ${JSON.stringify(chatDir)}
os.makedirs(chat_dir, exist_ok=True)
files = sorted(glob.glob(os.path.join(chat_dir, "*.json")), key=os.path.getmtime, reverse=True)
for path in files:
    chat_id = os.path.basename(path)[:-5]
    title = "New Chat"
    agent = ""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        messages = payload if isinstance(payload, list) else payload.get("messages", [])
        agent = "" if isinstance(payload, list) else payload.get("agentId", "")
        for message in messages:
            if message.get("role") == "user":
                value = message.get("content", "").replace("\\n", " ").strip()
                title = value[:40] + ("..." if len(value) > 40 else "")
                break
    except Exception:
        pass
    print(json.dumps({"id": chat_id, "title": title, "agentId": agent}))
`;
        listHistoryProcess.command = ["python3", "-c", pyScript];
        listHistoryProcess.running = true;
    }

    Process {
        id: listHistoryProcess
        stdout: SplitParser {
            onRead: data => {
                try {
                    let item = JSON.parse(data);
                    root._historyBuffer.push({
                        id: item.id,
                        title: item.title || "New Chat",
                        agentId: item.agentId || "",
                        path: root.chatDir + "/" + item.id + ".json"
                    });
                } catch (e) {
                    console.warn("Failed to parse chat history entry: " + e);
                }
            }
        }
        onRunningChanged: {
            if (running)
                root._historyBuffer = [];
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.chatHistory = root._historyBuffer.slice();
                root.historyModelChanged();
            }
        }
    }
    property var _historyBuffer: []

    function loadChat(id) {
        if (!id)
            return;
        cancelGeneration(false);
        loadChatProcess.targetId = id;
        loadChatProcess.command = ["/usr/bin/cat", chatDir + "/" + id + ".json"];
        loadChatProcess.running = true;
    }

    Process {
        id: loadChatProcess
        property string targetId: ""
        stdout: StdioCollector {
            id: loadChatStdout
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            try {
                let payload = JSON.parse(loadChatStdout.text);
                let isLegacy = Array.isArray(payload);
                let agentId = isLegacy ? root.currentAgentId : (payload.agentId || root.currentAgentId);
                let agent = root.findAgent(agentId) || root.currentModel;
                root.currentModel = agent;
                root.currentAgentId = agent.id;
                root.currentChatAgentId = agent.id;
                root.currentChat = isLegacy ? payload : (payload.messages || []);
                root.currentChatId = targetId;
                root.currentSessionId = isLegacy ? "" : (payload.sessionId || "");
                root.currentChatCwd = isLegacy ? root.workingDirectory() : (payload.cwd || root.workingDirectory());
                root.sessionReady = false;
                root.activeAssistantIndex = -1;
                root.activeAssistantMessageId = "";
                root.pendingPermissions = {};
                root.questionRequests = [];
                root.questionDrafts = {};
                root.questionErrors = {};
                root.taskPlan = payload.taskPlan || [];
                root.taskPlanMarkdown = payload.taskPlanMarkdown || "";
                root.activityLog = payload.activityLog || [];
                root.chatModelChanged();
                root.ensureConnection({
                    kind: root.currentSessionId ? "load" : "new",
                    sessionId: root.currentSessionId,
                    cwd: root.currentChatCwd
                });
            } catch (e) {
                root.pushSystemMessage("Failed to load chat: " + e);
            }
        }
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    property bool bootstrapped: false

    Process {
        id: bridgeStopProcess
        command: ["python3", root.bridgeScript, "--stop", "--channel", root.channelId]
    }

    function shutdown() {
        if (planUsageProcess.running)
            planUsageProcess.running = false;
        flushAssistantText();
        refreshTimer.stop();
        bridgeReconnectTimer.stop();
        turnWatchdog.stop();
        restartPending = false;
        expectedProcessStop = true;
        pendingSessionAction = null;
        queuedPrompt = null;
        pendingPermissions = {};
        questionRequests = [];
        questionDrafts = {};
        questionErrors = {};
        activePromptRequestId = -1;
        isLoading = false;
        agentTurnActive = false;
        toolRunning = false;
        statusText = "";
        if (agentProcess.running) {
            // Explicitly disabling AI stops the backend. QML destruction only
            // closes the relay, so ordinary shell reloads keep work running.
            agentProcess.running = false;
        }
        bridgeAttached = false;
        bridgeStopProcess.running = true;
        if (ensureChatDirProcess.running)
            ensureChatDirProcess.running = false;
        if (deleteChatProcess.running)
            deleteChatProcess.running = false;
        if (listHistoryProcess.running)
            listHistoryProcess.running = false;
        if (loadChatProcess.running)
            loadChatProcess.running = false;
        resetConnectionState();
        bootstrapped = false;
    }

    function bootstrap() {
        if (!featureEnabled || bootstrapped)
            return;
        bootstrapped = true;
        refreshAgents();
        let preferred = StateService.get(
            "lastAiAgent",
            Config.ai && Config.ai.defaultAgent ? Config.ai.defaultAgent : "codex"
        );
        let agent = findAgent(preferred) || models[0];
        if (agent) {
            currentModel = agent;
            currentAgentId = agent.id;
        }
        reloadHistory();
        startAgentProcess();
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            if (root.featureEnabled && !root.bootstrapped)
                root.bootstrap();
        }
    }

    Connections {
        target: Config
        function onAiReadyChanged() {
            if (root.featureEnabled) {
                root.refreshAgents();
                if (!root.bootstrapped)
                    root.bootstrap();
            }
        }
    }

    Connections {
        target: Config.ai
        function onEnabledChanged() {
            // Read the changed setting directly: featureEnabled's binding
            // may not have reevaluated when this signal handler runs.
            if (Config.ai.enabled && root.sessionEnabled && Config.aiReady)
                root.bootstrap();
            else
                root.shutdown();
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            if (root.featureEnabled && !root.bootstrapped)
                root.bootstrap();
        });
    }
}
