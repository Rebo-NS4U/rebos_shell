pragma Singleton
import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.globals

// Keep the original daemon compatible with existing live conversations. Its
// client can be closed like any other tab; the manager itself stays alive.
AiSession {
    id: root
    sessionEnabled: false
    property AiSession activeSession: root
    property list<AiSession> sessions: []
    property bool sessionsReady: false
    property bool restoringSessions: false
    property list<string> notifiedQuestionKeys: []
    onSessionsChanged: syncQuestionNotifications()
    property Component sessionFactory: Component { AiSession {} }
    property alias sessionModel: viewModel
    ListModel { id: viewModel }

    function syncQuestionNotifications() {
        let pendingKeys = [];
        for (let session of sessions) {
            for (let question of session.questionRequests) {
                const key = "assistant-question:" + session.channelId + ":" + question.requestId;
                pendingKeys.push(key);
                if (notifiedQuestionKeys.includes(key)) continue;
                Notifications.notifyInternal({
                    appName: "Assistant",
                    appIcon: "dialog-question",
                    summary: "Assistant needs your answer",
                    body: String(question.message || "Open the assistant to answer a question.").slice(0, 300),
                    replaceKey: key,
                    expireTimeout: 10000,
                    actions: [{identifier: "answer", text: "Answer"}],
                    actionHandlers: {answer: function () {
                        if (!root.sessions.includes(session) || !session.questionRequests.some(item => item.requestId === question.requestId)) return;
                        root.selectSession(session);
                        GlobalStates.toggleAssistant();
                    }}
                });
            }
        }
        const removed = notifiedQuestionKeys.filter(key => !pendingKeys.includes(key));
        if (removed.length) {
            Notifications.discardNotifications(Notifications.list.filter(notification => removed.includes(notification.replaceKey)).map(notification => notification.id));
        }
        notifiedQuestionKeys = pendingKeys;
    }

    Timer {
        id: rememberTimer
        interval: 150
        onTriggered: root.rememberSessions()
    }

    function rememberSessions() {
        if (restoringSessions || !sessionsReady) return;
        StateService.set("assistantSessionChannels", sessions.map(session => session.channelId));
        StateService.set("assistantActiveChannel", activeSession.channelId);
    }

    function selectSession(session) {
        if (!session || session === activeSession || sessions.indexOf(session) < 0) return;
        activeSession = session;
        rememberTimer.restart();
    }

    function addSession(channel) {
        let session;
        if (channel === "default") {
            session = root;
            root.sessionEnabled = true;
        } else {
            session = sessionFactory.createObject(root, {channelId: channel});
        }
        if (!session) return null;
        session.questionRequestsChanged.connect(root.syncQuestionNotifications);
        sessions = sessions.concat([session]);
        viewModel.append({sessionObject: session});
        return session;
    }

    function newSession() {
        let channel = "chat-" + Date.now() + "-" + Math.random().toString(36).slice(2, 8);
        let session = addSession(channel);
        if (session) selectSession(session);
        rememberSessions();
    }

    function ensureSession() {
        if (sessionsReady && sessions.length === 0) newSession();
    }

    function openChat(id) {
        let existing = sessions.find(session => session.currentChatId === id);
        if (existing) { selectSession(existing); return; }
        newSession();
        activeSession.loadChat(id);
    }

    function closeSession(session) {
        const index = sessions.indexOf(session);
        if (index < 0) return;
        session.saveCurrentChat();
        const remaining = sessions.filter(item => item !== session);
        if (activeSession === session)
            activeSession = remaining[Math.min(index, remaining.length - 1)] || root;
        viewModel.remove(index);
        sessions = remaining;
        // Disabling the original client stops its daemon without destroying
        // the manager, or restarting it on the next shell reload.
        session.sessionEnabled = false;
        if (remaining.length === 0) GlobalStates.hideAssistant();
        rememberSessions();
        if (session !== root) session.destroy(500);
    }

    function restoreSessions() {
        if (sessionsReady || StateService.initialized === false) return;
        restoringSessions = true;
        let channels = StateService.get("assistantSessionChannels", ["default"]);
        if (Array.isArray(channels)) {
            for (let channel of channels) {
                if (typeof channel === "string" && /^[a-zA-Z0-9_-]{1,64}$/.test(channel)
                    && !sessions.some(session => session.channelId === channel))
                    addSession(channel);
            }
        }
        let active = StateService.get("assistantActiveChannel", "default");
        activeSession = sessions.find(session => session.channelId === active) || sessions[0] || root;
        restoringSessions = false;
        sessionsReady = true;
    }

    Connections {
        target: StateService
        function onStateLoaded() { root.restoreSessions(); }
    }
    Component.onCompleted: Qt.callLater(root.restoreSessions)
}
