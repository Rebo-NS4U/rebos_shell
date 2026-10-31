import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.theme
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import Quickshell
import Quickshell.Io

Item {
    id: root
    anchors.fill: parent

    required property ShellScreen targetScreen
    property bool tiled: false
    property bool windowFocused: true

    onTiledChanged: {
        if (root.active) {
            root.wantsFocus = true;
            Qt.callLater(root.focusSearchInput);
        }
    }

    readonly property bool active: GlobalStates.assistantAvailable
        && GlobalStates.assistantVisible
        && targetScreen.name === GlobalStates.assistantScreenName
    readonly property Item blurTarget: sidebarBackground
    property alias hitbox: sidebarContainer
    property alias resizeHitbox: resizeHandle
    readonly property bool hasActiveFocus: currentPage?.input.activeFocus ?? false
    property Item currentPage: null
    Connections {
        target: Ai
        function onSessionsReadyChanged() { if (root.active) Ai.ensureSession(); }
    }

    readonly property int sidebarMargin: 4
    property bool wantsFocus: false
    property bool menuExpanded: false
    property real menuWidth: 250
    property list<var> slashCommands: [
        {
            name: "agent",
            description: "Switch ACP agent"
        },
        {
            name: "model",
            description: "Switch the active agent model"
        },
        {
            name: "help",
            description: "Show help"
        },
        {
            name: "new",
            description: "Start a new ACP session"
        },
        {
            name: "usage",
            description: "Check plan quota and reset times"
        },
        {
            name: "terminal",
            description: "Open terminal in working directory"
        },
        {
            name: "status",
            description: "Show ACP connection status"
        }
    ]

    readonly property real maximumSidebarWidth: Math.max(0, root.width - root.sidebarMargin - resizeHandle.width)
    readonly property real minimumSidebarWidth: Math.min(300, maximumSidebarWidth)

    function resizeSidebar(requestedWidth) {
        GlobalStates.assistantWidth = Math.round(Math.max(minimumSidebarWidth,
            Math.min(maximumSidebarWidth, requestedWidth)));
    }

    function saveSidebarWidth() {
        Config.ai.sidebarWidth = GlobalStates.assistantWidth;
    }

    onWidthChanged: {
        if (!root.tiled && root.width > 0)
            resizeSidebar(GlobalStates.assistantWidth);
    }

    function focusSearchInput() {
        currentPage?.input.forceActiveFocus();
    }

    function sendCurrentMessage() {
        const mainChatArea = currentPage;
        if (!mainChatArea) return;
        const inputField = mainChatArea.input;
        const chatView = mainChatArea.chat;
        if (Ai.activeSession.isBusy || Ai.activeSession.switchingSessionModel || (!inputField.text.trim() && mainChatArea.pendingAttachments.length === 0))
            return;
        // Release the layer's exclusive keyboard focus before starting a turn.
        root.wantsFocus = false;
        inputField.focus = false;
        chatView.followBottom = true;
        Ai.activeSession.sendMessage(inputField.text.trim(), mainChatArea.pendingAttachments.length > 0 ? mainChatArea.pendingAttachments : undefined);
        inputField.text = "";
        mainChatArea.clearAttachments();
    }

    Connections {
        target: GlobalStates
        function onAssistantFocusRequested(wasAlreadyOpen) {
            if (targetScreen.name === GlobalStates.assistantScreenName) {
                Qt.callLater(() => {
                    if (!root.active) return;
                    root.wantsFocus = true;
                    focusSearchInput();
                });
            }
        }
    }

    onActiveChanged: {
        if (active) {
            Ai.ensureSession();
            Ai.activeSession.refreshPlanUsage(false);
            root.wantsFocus = true;
            Qt.callLater(() => {
                focusSearchInput();
            });
        } else {
            root.wantsFocus = false;
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: Ai.activeSession.refreshPlanUsage(false)
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (!root.wantsFocus)
                root.wantsFocus = true;
            mouse.accepted = false;
        }
    }

    MouseArea {
        id: resizeHandle
        width: 16
        height: sidebarContainer.height
        y: sidebarContainer.y
        visible: !root.tiled && sidebarContainer.visible && root.active
        cursorShape: Qt.SplitHCursor
        preventStealing: true
        z: 10

        x: {
            if (root.tiled) return 0;
            if (GlobalStates.assistantPosition === "left")
                return sidebarContainer.x + sidebarContainer.width;
            return sidebarContainer.x - width;
        }

        property real pressMouseX: 0
        property int pressWidth: 0

        StyledRect {
            width: 3
            height: 48
            anchors.centerIn: parent
            variant: "primary"
            radius: Styling.radius(4)
            opacity: resizeHandle.containsMouse || resizeHandle.pressed ? 1 : 0.5
        }
        hoverEnabled: true

        onPressed: {
            let mapped = mapToItem(root, mouseX, 0);
            pressMouseX = mapped.x;
            pressWidth = GlobalStates.assistantWidth;
        }

        onPositionChanged: mouse => {
            if (!pressed)
                return;
            let mapped = mapToItem(root, mouse.x, mouse.y);
            let delta;
            if (GlobalStates.assistantPosition === "right")
                delta = pressMouseX - mapped.x;
            else
                delta = mapped.x - pressMouseX;
            root.resizeSidebar(pressWidth + delta);
        }

        onReleased: root.saveSidebarWidth()
        onCanceled: root.saveSidebarWidth()
        onDoubleClicked: {
            root.resizeSidebar(400);
            root.saveSidebarWidth();
        }
        StyledToolTip {
            show: parent.containsMouse && !parent.pressed
            tooltipText: "Drag to resize · double-click to reset"
        }
    }

    Item {
        id: sidebarContainer
        width: root.tiled ? parent.width : GlobalStates.assistantWidth + root.sidebarMargin
        height: parent.height

        // Avoid animating the off-screen dock during first layout: parent.width
        // resolves from 0 → screen size and would flash a left→right slide.
        property bool slideReady: false
        Component.onCompleted: Qt.callLater(() => {
            slideReady = true;
        })

        x: {
            if (root.tiled) return 0;
            if (GlobalStates.assistantPosition === "left")
                return root.active ? 0 : -(width);
            return root.active ? parent.width - width : parent.width;
        }

        visible: root.active || (slideReady && slideAnimation.running)

        Behavior on x {
            enabled: !root.tiled && !resizeHandle.pressed && sidebarContainer.slideReady && (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
            NumberAnimation {
                id: slideAnimation
                duration: root.active ? Motion.enter : Motion.exit
                easing.type: root.active ? Motion.enterCurve : Motion.exitCurve
            }
        }

        StyledRect {
            id: sidebarBackground
            anchors.fill: parent
            anchors.topMargin: root.sidebarMargin
            anchors.bottomMargin: root.sidebarMargin
            anchors.leftMargin: GlobalStates.assistantPosition === "left" ? root.sidebarMargin : 0
            anchors.rightMargin: GlobalStates.assistantPosition === "right" ? root.sidebarMargin : 0
            variant: "bg"
            radius: Styling.radius(16)
            border.color: Styling.unifiedStyle ? Config.resolveColor(Styling.getStyledRectConfig("bg").border[0]) : Qt.alpha(Colors.primary, 0.28)
            border.width: 1
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0
                            contentItem: StyledText {
                                text: Icons.list
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(2)
                                color: root.menuExpanded ? Styling.srItem("overprimary") : Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Config.animDuration / 4
                                    }
                                }
                            }
                            onClicked: root.menuExpanded = !root.menuExpanded
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0
                            contentItem: StyledText {
                                text: Icons.edit
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(2)
                                color: Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Config.animDuration / 4
                                    }
                                }
                            }
                            StyledToolTip {
                                show: parent.hovered
                                tooltipText: "New chat — other chats keep working"
                            }
                            onClicked: {
                                Ai.newSession();
                                root.menuExpanded = false;
                            }
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0

                            contentItem: StyledText {
                                text: Icons.pin
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(2)
                                color: GlobalStates.assistantPinned ? Styling.srItem("overprimary") : Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Config.animDuration / 4
                                    }
                                }
                            }

                            objectName: "assistantPinButton"
                            StyledToolTip {
                                show: parent.hovered
                                tooltipText: root.tiled ? "Return to sidebar" : "Tile assistant window"
                            }
                            onClicked: {
                                GlobalStates.assistantPinned = !GlobalStates.assistantPinned;
                                Config.ai.sidebarPinnedOnStartup = GlobalStates.assistantPinned;
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: "Assistant"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.DemiBold
                            color: Colors.overSurface
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: [-1, 1]
                            delegate: Button {
                                required property int modelData
                                visible: !root.tiled
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 32
                                flat: true
                                padding: 0
                                enabled: modelData < 0
                                    ? GlobalStates.assistantWidth > root.minimumSidebarWidth
                                    : GlobalStates.assistantWidth < root.maximumSidebarWidth
                                contentItem: StyledText {
                                    text: parent.modelData < 0 ? "−" : "+"
                                    font.pixelSize: Styling.fontSize(3)
                                    color: Colors.primary
                                    opacity: parent.enabled ? 1 : 0.35
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: StyledRect {
                                    variant: parent.hovered ? "focus" : "transparent"
                                    radius: Styling.radius(8)
                                }
                                StyledToolTip {
                                    show: parent.hovered
                                    tooltipText: modelData < 0 ? "Narrower panel" : "Wider panel"
                                }
                                onClicked: {
                                    root.resizeSidebar(GlobalStates.assistantWidth + modelData * 80);
                                    root.saveSidebarWidth();
                                }
                            }
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0

                            contentItem: StyledText {
                                text: GlobalStates.assistantPosition === "right" ? Icons.caretRight : Icons.caretLeft
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(2)
                                color: Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Config.animDuration / 4
                                    }
                                }
                            }

                            onClicked: GlobalStates.hideAssistant()
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Colors.outline
                        opacity: 0.15
                    }
                }

                Flickable {
                    id: sessionStrip
                    Layout.topMargin: 6
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 38 : 0
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 4
                    visible: Ai.sessions.length > 0
                    contentWidth: sessionRow.width
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    function revealActive() {
                        let index = Ai.sessions.indexOf(Ai.activeSession);
                        let tab = sessionRepeater.itemAt(index);
                        if (!tab) return;
                        let rightEdge = tab.x + tab.width;
                        if (tab.x < contentX) contentX = tab.x;
                        else if (rightEdge > contentX + width) contentX = rightEdge - width;
                        contentX = Math.max(0, Math.min(contentX, contentWidth - width));
                    }
                    onWidthChanged: Qt.callLater(revealActive)
                    onContentWidthChanged: Qt.callLater(revealActive)
                    Connections {
                        target: Ai
                        function onActiveSessionChanged() { Qt.callLater(sessionStrip.revealActive); }
                    }
                    Row {
                        id: sessionRow
                        spacing: 6
                        Repeater {
                            id: sessionRepeater
                            model: Ai.sessionModel
                            delegate: Button {
                                id: sessionTab
                                required property AiSession sessionObject
                            readonly property AiSession modelData: sessionObject
                                readonly property bool selected: Ai.activeSession === modelData
                                readonly property bool needsAnswer: modelData.questionRequests.length > 0
                                    || Object.keys(modelData.pendingPermissions).length > 0
                                readonly property bool closable: true
                                width: Math.min(Math.max(120, titleMetrics.advanceWidth + (closable ? 60 : 36)),
                                    Math.min(224, Math.max(120, sessionStrip.width - 12)))
                                height: 32
                                flat: true
                                padding: 0
                                leftPadding: 12
                                rightPadding: closable ? 30 : 12
                                onClicked: Ai.selectSession(modelData)
                                TextMetrics {
                                    id: titleMetrics
                                    font: tabTitle.font
                                    text: sessionTab.modelData.sessionTitle
                                }
                                background: StyledRect {
                                    variant: "internalbg"
                                    radius: Styling.radius(0)
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.primary, sessionTab.selected ? 0.35 : sessionTab.hovered ? 0.16 : 0.06)
                                    color: Qt.alpha(Colors.primary, sessionTab.selected ? 0.12 : sessionTab.hovered ? 0.06 : 0.02)
                                    Behavior on color { ColorAnimation { duration: Config.animDuration / 4 } }
                                    Behavior on border.color { ColorAnimation { duration: Config.animDuration / 4 } }
                                }
                                contentItem: RowLayout {
                                    spacing: 7
                                    StyledRect {
                                        Layout.preferredWidth: 5
                                        Layout.preferredHeight: 5
                                        variant: "focus"
                                        radius: width / 2
                                        color: Colors.primary
                                        opacity: sessionTab.needsAnswer ? 1 : sessionTab.modelData.isBusy ? 0.75 : 0.3
                                    }
                                    StyledText {
                                        id: tabTitle
                                        Layout.fillWidth: true
                                        text: sessionTab.modelData.sessionTitle
                                        color: sessionTab.selected ? Colors.primary : Colors.overSurface
                                        opacity: sessionTab.selected ? 1 : 0.75
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: sessionTab.selected ? Font.Medium : Font.Normal
                                        renderType: Text.NativeRendering
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                StyledToolTip {
                                    show: sessionTab.hovered && !closeTab.hovered
                                    tooltipText: sessionTab.modelData.sessionTitle
                                    description: sessionTab.needsAnswer ? "Waiting for your answer"
                                        : sessionTab.modelData.isBusy ? "Working in the background" : ""
                                }
                                Button {
                                    id: closeTab
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    visible: sessionTab.closable
                                    flat: true
                                    padding: 0
                                    opacity: hovered || sessionTab.selected || sessionTab.hovered ? 1 : 0.4
                                    onClicked: Ai.closeSession(sessionTab.modelData)
                                    contentItem: StyledText {
                                        text: "×"
                                        color: Colors.overSurface
                                        font.pixelSize: Styling.fontSize(1)
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: StyledRect {
                                        variant: "focus"
                                        radius: Styling.radius(-4)
                                        opacity: closeTab.hovered ? 0.65 : 0
                                    }
                                    StyledToolTip {
                                        show: closeTab.hovered
                                        tooltipText: "Close chat"
                                        description: "Stops this chat's work"
                                    }
                                }
                            }
                        }
                    }
                }

                AssistantModelPicker {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 8
                    visible: root.active
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    flat: true
                    padding: 8
                    background: StyledRect {
                        variant: parent.hovered ? "focus" : "internalbg"
                        radius: Styling.radius(8)
                        border.color: Qt.alpha(Colors.primary, 0.16)
                        border.width: 1
                    }
                    contentItem: StyledText {
                        text: Ai.activeSession.checkingPlanUsage ? "Checking plan usage…" : Ai.activeSession.planUsageSummary
                        color: Colors.overSurface
                        font.pixelSize: Styling.fontSize(-3)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    StyledToolTip {
                        show: parent.hovered
                        tooltipText: Ai.activeSession.planUsageDetails || "Click to check shared Codex plan usage"
                    }
                    onClicked: Ai.activeSession.refreshPlanUsage(true)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Repeater {
                        id: chatPages
                        model: Ai.sessionModel
                        delegate: Loader {
                            id: pageLoader
                            required property AiSession sessionObject
                            readonly property AiSession modelData: sessionObject
                            readonly property bool selected: Ai.activeSession === modelData
                            property bool visited: selected
                            anchors.fill: parent
                            active: visited
                            visible: selected
                            onSelectedChanged: {
                                if (selected) {
                                    visited = true;
                                    if (item) root.currentPage = item;
                                }
                            }
                            onLoaded: {
                                if (selected) root.currentPage = item;
                            }
                    sourceComponent: Item {
                        id: mainChatArea
                        readonly property AiSession session: pageLoader.modelData
                        property alias input: inputField
                        property alias chat: chatView
                        objectName: "assistantChatPage_" + session.channelId

                        Component.onCompleted: {
                            inputField.text = session.inputDraft;
                            pendingAttachments = session.attachmentDraft.slice();
                        }
                        Connections {
                            target: mainChatArea.session
                            function onInputDraftChanged() {
                                if (inputField.text !== mainChatArea.session.inputDraft)
                                    inputField.text = mainChatArea.session.inputDraft;
                            }
                            function onAttachmentDraftChanged() {
                                if (JSON.stringify(mainChatArea.pendingAttachments) !== JSON.stringify(mainChatArea.session.attachmentDraft))
                                    mainChatArea.pendingAttachments = mainChatArea.session.attachmentDraft.slice();
                            }
                        }
                        anchors.fill: parent

                        property list<var> pendingAttachments: []
                        onPendingAttachmentsChanged: {
                            mainChatArea.session.attachmentDraft = pendingAttachments.slice();
                            mainChatArea.session.bridgeDirty = true;
                        }

                        function addAttachment(mimeType, base64Data, fileName) {
                            let list = pendingAttachments.slice();
                            list.push({
                                type: "image",
                                mimeType: mimeType,
                                base64: base64Data,
                                name: fileName
                            });
                            pendingAttachments = list;
                        }

                        function normalizeFilePath(path) {
                            let p = path ? path.trim() : "";
                            if (p.startsWith("file://"))
                                p = p.substring(7);
                            try {
                                p = decodeURIComponent(p);
                            } catch (e) {
                            }
                            return p;
                        }

                        function fileMimeForPath(path) {
                            let ext = path.split(".").pop().toLowerCase();
                            let mimeMap = {
                                png: "image/png",
                                jpg: "image/jpeg",
                                jpeg: "image/jpeg",
                                gif: "image/gif",
                                webp: "image/webp",
                                bmp: "image/bmp"
                            };
                            return mimeMap[ext] || "";
                        }

                        function addAttachmentFromFile(path) {
                            let filePath = normalizeFilePath(path);
                            if (!filePath)
                                return;
                            let mimeType = fileMimeForPath(filePath);
                            if (!mimeType) {
                                mainChatArea.session.pushSystemMessage("Only image files are supported for attachments.");
                                return;
                            }
                            attachmentReadProcess.filePath = filePath;
                            attachmentReadProcess.mimeType = mimeType;
                            attachmentReadProcess.fileName = filePath.split("/").pop();
                            attachmentReadProcess.running = true;
                        }

                        function addAttachmentsFromUriList(text) {
                            let lines = text.split("\n");
                            for (let i = 0; i < lines.length; i++) {
                                let line = lines[i].trim();
                                if (line === "" || line.startsWith("#"))
                                    continue;
                                addAttachmentFromFile(line);
                            }
                        }

                        function removeAttachment(index) {
                            let list = pendingAttachments.slice();
                            list.splice(index, 1);
                            pendingAttachments = list;
                        }

                        function clearAttachments() {
                            pendingAttachments = [];
                        }
                        StyledRect {
                            id: historyPage
                            anchors.fill: parent
                            variant: "bg"
                            visible: root.menuExpanded
                            opacity: root.menuExpanded ? 1 : 0
                            z: 10

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Config.animDuration
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8

                                StyledText {
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    text: "Chat History"
                                    color: Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(4)
                                    font.weight: Font.Bold
                                }

                                ListView {
                                    id: historyList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: mainChatArea.session.chatHistory
                                    spacing: 4

                                    delegate: Button {
                                        width: historyList.width
                                        height: 48
                                        flat: true

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 8

                                            Column {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter

                                                StyledText {
                                                    renderType: Text.NativeRendering
                                                    font.hintingPreference: Font.PreferFullHinting
                                                    text: modelData.title || "New Chat"
                                                    color: mainChatArea.session.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.overSurface
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(0)
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }

                                                StyledText {
                                                    renderType: Text.NativeRendering
                                                    font.hintingPreference: Font.PreferFullHinting
                                                    text: {
                                                        let date = new Date(parseInt(modelData.id));
                                                        return date.toLocaleString(Qt.locale(), "MMM dd, hh:mm a");
                                                    }
                                                    color: mainChatArea.session.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.outline
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-3)
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                            }

                                            Button {
                                                visible: parent.parent.hovered
                                                flat: true
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28

                                                contentItem: StyledText {
                                                    text: Icons.trash
                                                    font.family: Icons.font
                                                    color: parent.hovered ? Colors.error : Colors.outline
                                                    font.pixelSize: Styling.fontSize(0)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                background: null
                                                onClicked: mainChatArea.session.deleteChat(modelData.id)
                                            }
                                        }

                                        background: StyledRect {
                                            variant: mainChatArea.session.currentChatId === modelData.id ? "focus" : (parent.hovered ? "surfaceVariant" : "transparent")
                                            radius: Styling.radius(6)
                                        }

                                        onClicked: {
                                            Ai.openChat(modelData.id);
                                            root.menuExpanded = false;
                                        }
                                    }
                                }
                            }
                        }
                        property int retryIndex: -1
                        property string username: ""

                        Process {
                            running: true
                            command: ["whoami"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let user = text.trim();
                                    if (user) {
                                        mainChatArea.username = user.charAt(0).toUpperCase() + user.slice(1);
                                    }
                                }
                            }
                        }

                        Process {
                            id: zenityProcess
                            command: ["zenity", "--file-selection", "--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp", "--file-filter=All files | *"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let filePath = text.trim();
                                    if (filePath.length > 0)
                                        mainChatArea.addAttachmentFromFile(filePath);
                                }
                            }
                        }

                        Process {
                            id: attachmentReadProcess
                            property string filePath: ""
                            property string mimeType: ""
                            property string fileName: ""
                            command: ["bash", "-c", "/usr/bin/base64 -w 0 '" + filePath.replace(/'/g, "'\\''") + "'"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0)
                                        mainChatArea.addAttachment(attachmentReadProcess.mimeType, data, attachmentReadProcess.fileName);
                                    else if (attachmentReadProcess.filePath.length > 0)
                                        mainChatArea.session.pushSystemMessage("Failed to read attachment data.");
                                }
                            }
                            stderr: StdioCollector {
                                id: attachmentReadStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let errorText = attachmentReadStderr.text.trim();
                                    mainChatArea.session.pushSystemMessage("Failed to read attachment: " + (errorText.length > 0 ? errorText : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardTypesProcess
                            command: ["wl-paste", "--list-types"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let types = text.trim().split("\n");
                                    let imageType = "";
                                    for (let i = 0; i < types.length; i++) {
                                        if (types[i].startsWith("image/")) {
                                            imageType = types[i].trim();
                                            break;
                                        }
                                    }
                                    if (imageType.length > 0) {
                                        clipboardImageProcess.mimeType = imageType;
                                        clipboardImageProcess.running = true;
                                        return;
                                    }
                                    if (types.indexOf("text/uri-list") !== -1) {
                                        clipboardUrisProcess.running = true;
                                        return;
                                    }
                                    mainChatArea.session.pushSystemMessage("Clipboard does not contain an image or file.");
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardTypesStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardTypesStderr.text.trim();
                                    mainChatArea.session.pushSystemMessage("Clipboard read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardImageProcess
                            property string mimeType: ""
                            command: ["bash", "-c", "wl-paste --type \"" + mimeType + "\" 2>/dev/null | /usr/bin/base64 -w 0" ]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0) {
                                        let ext = clipboardImageProcess.mimeType.split("/")[1] || "png";
                                        mainChatArea.addAttachment(clipboardImageProcess.mimeType, data, "clipboard." + ext);
                                    } else {
                                        mainChatArea.session.pushSystemMessage("Clipboard image read returned no data.");
                                    }
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardImageStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardImageStderr.text.trim();
                                    mainChatArea.session.pushSystemMessage("Clipboard image read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardUrisProcess
                            command: ["wl-paste", "--type", "text/uri-list"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0)
                                        mainChatArea.addAttachmentsFromUriList(data);
                                    else
                                        mainChatArea.session.pushSystemMessage("Clipboard file list is empty.");
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardUrisStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardUrisStderr.text.trim();
                                    mainChatArea.session.pushSystemMessage("Clipboard file read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }
                        property bool isWelcome: mainChatArea.session.currentChat.length === 0

                        ColumnLayout {
                            anchors.bottom: inputContainer.top
                            anchors.bottomMargin: 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: mainChatArea.isWelcome
                            spacing: 8

                            StyledText {
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                text: "Hello, <font color='" + Styling.srItem("overprimary") + "'>" + mainChatArea.username + "</font>."
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(18)
                                font.weight: Font.Bold
                                textFormat: Text.StyledText
                                Layout.alignment: Qt.AlignHCenter
                                color: Colors.overBackground
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                height: 40

                                StyledText {
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    text: mainChatArea.session.currentModel ? mainChatArea.session.currentModel.name : ""
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(2)
                                    font.weight: Font.Bold
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                visible: false
                            }

                            AssistantActivity {
                                session: mainChatArea.session
                                Layout.fillWidth: true
                            }

                            Flickable {
                                id: chatView
                                visible: !mainChatArea.isWelcome
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: messageColumn.height + 16 + inputContainer.height + 40
                                flickableDirection: Flickable.VerticalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                property bool followBottom: true

                                onContentHeightChanged: {
                                    if (followBottom)
                                        chatScrollTimer.restart();
                                }
                                onHeightChanged: {
                                    if (followBottom)
                                        chatScrollTimer.restart();
                                }
                                onMovementStarted: followBottom = false
                                onMovementEnded: {
                                    followBottom = contentY >= Math.max(0, contentHeight - height) - 40;
                                }

                                Timer {
                                    id: chatScrollTimer
                                    interval: 0
                                    onTriggered: {
                                        if (chatView.followBottom && !chatView.moving)
                                            chatView.contentY = Math.max(0, chatView.contentHeight - chatView.height);
                                    }
                                }

                                Column {
                                    id: messageColumn
                                    x: 4
                                    y: 16
                                    width: Math.max(0, chatView.width - 8)
                                    spacing: 16

                                    Repeater {
                                        // Keep message widgets alive while their streamed text changes.
                                        model: mainChatArea.session.currentChat.length

                                        delegate: Item {
                                            id: messageDelegate
                                            objectName: "assistantMessage_" + mainChatArea.session.channelId + "_" + index
                                            required property int index
                                            readonly property var modelData: mainChatArea.session.currentChat[index] || {}

                                            property bool isUser: modelData.role === "user"
                                            property bool isToolResult: modelData.role === "function"
                                            property bool isSystem: modelData.role === "system" || isToolResult
                                            property bool isEditing: false
                                            property bool retryMode: false
                                            property bool toolExpanded: false

                                            readonly property string toolResultTitle: {
                                                if (!isToolResult)
                                                    return "";
                                                let c = (modelData.content || "").toLowerCase();
                                                if (c.indexOf("cancelled") === 0 || c.indexOf("superseded") === 0)
                                                    return "Cancelled";
                                                let n = modelData.name || "";
                                                if (n === "run_shell_command")
                                                    return "Ran command";
                                                return n || "Tool result";
                                            }
                                            readonly property string toolResultDetail: {
                                                if (!isToolResult)
                                                    return "";
                                                let a = modelData.toolArgs || {};
                                                if (modelData.name === "run_shell_command" && a.command)
                                                    return a.command;
                                                let c = (modelData.content || "").trim();
                                                let line = c.split("\n")[0] || "";
                                                return line.length > 80 ? line.substring(0, 80) + "…" : line;
                                            }

                                            width: messageColumn.width
                                            height: bubbleArea.height + 8

                                            Row {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 10
                                                layoutDirection: (isUser && !isSystem) ? Qt.RightToLeft : Qt.LeftToRight
                                                spacing: 12

                                                MouseArea {
                                                    id: bubbleArea
                                                    // Full row width so bubbles can use most of the sidebar (no avatar column).
                                                    width: parent.width
                                                    height: Math.max(bubble.height, 32) + (modelIndicator.visible ? modelIndicator.implicitHeight + 4 : 0)
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton

                                                    // Action rail (edit / copy / regenerate):
                                                    // short bubbles → horizontal row; tall replies → vertical stack.
                                                    Grid {
                                                        id: actionRail
                                                        readonly property bool horizontal: !messageDelegate.isEditing && bubble.height < 88
                                                        columns: horizontal ? 3 : 1
                                                        rows: horizontal ? 1 : 3
                                                        anchors.top: horizontal ? undefined : bubble.top
                                                        anchors.topMargin: 4
                                                        anchors.verticalCenter: horizontal ? bubble.verticalCenter : undefined
                                                        anchors.left: isUser ? undefined : bubble.right
                                                        anchors.right: isUser ? bubble.left : undefined
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 4
                                                        flow: horizontal ? Grid.LeftToRight : Grid.TopToBottom
                                                        layoutDirection: isUser ? Qt.RightToLeft : Qt.LeftToRight
                                                        visible: bubbleArea.containsMouse || messageDelegate.isEditing
                                                        z: 2

                                                        Button {
                                                            width: 24
                                                            height: 24
                                                            flat: true
                                                            padding: 0
                                                            visible: !isSystem && mainChatArea.session.supportsMessageEditing

                                                            property bool isHovered: hovered

                                                            contentItem: StyledText {
                                                                text: messageDelegate.isEditing ? Icons.accept : Icons.edit
                                                                font.family: Icons.font
                                                                color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }

                                                            background: StyledRect {
                                                                variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                                radius: Styling.radius(4)
                                                            }

                                                            onClicked: {
                                                                if (messageDelegate.isEditing) {
                                                                    mainChatArea.session.updateMessage(index, bubbleContentText.text);
                                                                    messageDelegate.isEditing = false;
                                                                } else {
                                                                    messageDelegate.isEditing = true;
                                                                    bubbleContentText.forceActiveFocus();
                                                                    bubbleContentText.cursorPosition = bubbleContentText.text.length;
                                                                }
                                                            }
                                                        }

                                                        Button {
                                                            width: 24
                                                            height: 24
                                                            flat: true
                                                            padding: 0
                                                            visible: !messageDelegate.isEditing

                                                            property bool isHovered: hovered

                                                            contentItem: StyledText {
                                                                text: Icons.copy
                                                                font.family: Icons.font
                                                                color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }

                                                            background: StyledRect {
                                                                variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                                radius: Styling.radius(4)
                                                            }

                                                            onClicked: {
                                                                // Avoid embedding huge tool dumps into a generated QML string.
                                                                let text = (modelData.content || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "");
                                                                if (text.length > 8000)
                                                                    text = text.substring(0, 8000) + "\\n…";
                                                                let p = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { command: ["wl-copy", "' + text + '"] }', parent);
                                                                p.running = true;
                                                            }
                                                        }

                                                        Button {
                                                            visible: !isUser && !isSystem && !messageDelegate.isEditing && mainChatArea.session.supportsRegeneration
                                                            width: 24
                                                            height: 24
                                                            flat: true
                                                            padding: 0

                                                            property bool isHovered: hovered

                                                            contentItem: StyledText {
                                                                text: Icons.arrowCounterClockwise
                                                                font.family: Icons.font
                                                                color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }

                                                            background: StyledRect {
                                                                variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                                radius: Styling.radius(4)
                                                            }

                                                            onClicked: mainChatArea.session.regenerateResponse(index)
                                                        }
                                                    }

                                                    StyledRect {
                                                        id: bubble
                                                        // Wrapped content derives its width from this bubble.
                                                        // Sizing the bubble from that content's implicitWidth
                                                        // creates a layout cycle that can stall ListView polish.
                                                        width: messageDelegate.width * (isSystem ? 0.92 : 0.78)
                                                        height: bubbleContent.implicitHeight + 24

                                                        anchors.right: isUser ? parent.right : undefined
                                                        anchors.left: isUser ? undefined : parent.left

                                                        // User = primary; assistant = surface (better contrast than secondary on dark themes)
                                                        variant: isSystem ? "internalbg" : (isUser ? "primary" : "surface")
                                                        radius: Styling.radius(12)
                                                        border.width: messageDelegate.isEditing ? 2 : 0
                                                        border.color: Styling.srItem("overprimary")

                                                        readonly property color contentColor: isSystem
                                                            ? Colors.outline
                                                            : (isUser ? bubble.itemColor : Colors.overSurface)

                                                        ColumnLayout {
                                                            id: bubbleContent
                                                            anchors.centerIn: parent
                                                            width: parent.width - 32
                                                            spacing: 8

                                                            // ── Tool result: compact chip (expand for raw output) ──
                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                visible: messageDelegate.isToolResult
                                                                spacing: 6

                                                                MouseArea {
                                                                    Layout.fillWidth: true
                                                                    Layout.preferredHeight: toolChipRow.implicitHeight
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: messageDelegate.toolExpanded = !messageDelegate.toolExpanded

                                                                    RowLayout {
                                                                        id: toolChipRow
                                                                        anchors.left: parent.left
                                                                        anchors.right: parent.right
                                                                        spacing: 8

                                                                        StyledText {
                                                                            text: Icons.terminal
                                                                            font.family: Icons.font
                                                                            font.pixelSize: Styling.fontSize(0)
                                                                            color: Styling.srItem("overprimary")
                                                                        }

                                                                        ColumnLayout {
                                                                            Layout.fillWidth: true
                                                                            spacing: 1

                                                                            StyledText {
                                                                                renderType: Text.NativeRendering
                                                                                Layout.fillWidth: true
                                                                                text: messageDelegate.toolResultTitle
                                                                                color: Colors.overSurface
                                                                                font.family: Config.theme.font
                                                                                font.pixelSize: Styling.fontSize(-1)
                                                                                font.weight: Font.Medium
                                                                                elide: Text.ElideRight
                                                                            }

                                                                            StyledText {
                                                                                renderType: Text.NativeRendering
                                                                                Layout.fillWidth: true
                                                                                visible: messageDelegate.toolResultDetail.length > 0
                                                                                text: messageDelegate.toolResultDetail
                                                                                color: Colors.outline
                                                                                font.family: Config.theme.font
                                                                                font.pixelSize: Styling.fontSize(-3)
                                                                                elide: Text.ElideRight
                                                                            }
                                                                        }

                                                                        StyledText {
                                                                            text: messageDelegate.toolExpanded ? Icons.caretUp : Icons.caretDown
                                                                            font.family: Icons.font
                                                                            font.pixelSize: Styling.fontSize(-2)
                                                                            color: Colors.outline
                                                                        }
                                                                    }
                                                                }

                                                                StyledRect {
                                                                    Layout.fillWidth: true
                                                                    visible: messageDelegate.toolExpanded
                                                                    variant: "surface"
                                                                    color: Colors.surface
                                                                    radius: Styling.radius(6)
                                                                    implicitHeight: Math.min(toolResultScroll.contentHeight + 12, 180)

                                                                    Flickable {
                                                                        id: toolResultScroll
                                                                        anchors.fill: parent
                                                                        anchors.margins: 6
                                                                        contentWidth: width
                                                                        contentHeight: toolResultText.implicitHeight
                                                                        clip: true
                                                                        boundsBehavior: Flickable.StopAtBounds
                                                                        flickableDirection: Flickable.VerticalFlick

                                                                        TextEdit {
                                                                            id: toolResultText
                                                                            objectName: "toolResultText"
                                                                            width: toolResultScroll.width
                                                                            renderType: Text.NativeRendering
                                                                            font.hintingPreference: Font.PreferFullHinting
                                                                            text: messageDelegate.isToolResult && messageDelegate.toolExpanded
                                                                                ? (modelData.content || "") : ""
                                                                            textFormat: Text.PlainText
                                                                            color: Colors.outline
                                                                            font.family: "Monospace"
                                                                            font.pixelSize: Styling.fontSize(-3)
                                                                            wrapMode: Text.WrapAnywhere
                                                                            readOnly: true
                                                                            selectByMouse: true
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            // ── Normal message body (not tool results) ──
                                                            ColumnLayout {
                                                                id: messageBody
                                                                objectName: "messageBody"
                                                                Layout.fillWidth: true
                                                                visible: !messageDelegate.isToolResult && !messageDelegate.isEditing && !bubbleContentText.visible
                                                                spacing: 8

                                                                readonly property bool streaming: mainChatArea.session.isBusy && mainChatArea.session.activeAssistantIndex === messageDelegate.index
                                                                readonly property list<var> segments: {
                                                                    // Hidden tool output has its own on-demand plain-text view.
                                                                    if (messageDelegate.isToolResult || messageDelegate.isEditing)
                                                                        return [];
                                                                    let txt = messageDelegate.modelData.content || "";
                                                                    if (streaming)
                                                                        return [{type: "text", content: txt, language: ""}];
                                                                    let parts = [];
                                                                    let regex = /```(\w*)\n([\s\S]*?)```/g;
                                                                    let lastIndex = 0;
                                                                    let match;
                                                                    while ((match = regex.exec(txt)) !== null) {
                                                                        if (match.index > lastIndex) {
                                                                            parts.push({
                                                                                type: "text",
                                                                                content: txt.substring(lastIndex, match.index),
                                                                                language: ""
                                                                            });
                                                                        }
                                                                        parts.push({
                                                                            type: "code",
                                                                            content: match[2].trim(),
                                                                            language: match[1] || "text"
                                                                        });
                                                                        lastIndex = regex.lastIndex;
                                                                    }
                                                                    if (lastIndex < txt.length) {
                                                                        parts.push({
                                                                            type: "text",
                                                                            content: txt.substring(lastIndex),
                                                                            language: ""
                                                                        });
                                                                    }
                                                                    return parts;
                                                                }
                                                                Repeater {
                                                                    model: messageBody.segments.length

                                                                    delegate: Loader {
                                                                        required property int index
                                                                        Layout.fillWidth: true
                                                                        sourceComponent: segment.type === 'code' ? codeComponent : textComponent

                                                                        readonly property var segment: messageBody.segments[index] || { type: "text", content: "", language: "" }

                                                                        Component {
                                                                            id: textComponent
                                                                            TextEdit {
                                                                                renderType: Text.NativeRendering
                                                                                font.hintingPreference: Font.PreferFullHinting
                                                                                width: bubbleContent.width
                                                                                text: segment.content
                                                                                textFormat: messageBody.streaming ? Text.PlainText : Text.MarkdownText
                                                                                color: bubble.contentColor
                                                                                font.family: Config.theme.font
                                                                                font.pixelSize: Styling.fontSize(0)
                                                                                wrapMode: Text.Wrap
                                                                                readOnly: true
                                                                                selectByMouse: true

                                                                                onLinkActivated: link => Qt.openUrlExternally(link)
                                                                            }
                                                                        }

                                                                        Component {
                                                                            id: codeComponent
                                                                            CodeBlock {
                                                                                width: bubbleContent.width
                                                                                code: segment.content
                                                                                language: segment.language
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            TextEdit {
                                                                renderType: Text.NativeRendering
                                                                font.hintingPreference: Font.PreferFullHinting
                                                                id: bubbleContentText
                                                                objectName: "bubbleContentText"
                                                                Layout.fillWidth: true
                                                                text: messageDelegate.isEditing && !messageDelegate.isToolResult
                                                                    ? (modelData.content || "") : ""
                                                                textFormat: Text.PlainText
                                                                color: bubble.contentColor
                                                                font.family: Config.theme.font
                                                                font.pixelSize: Styling.fontSize(0)
                                                                wrapMode: Text.Wrap
                                                                readOnly: !messageDelegate.isEditing
                                                                selectByMouse: true
                                                                visible: messageDelegate.isEditing && !messageDelegate.isToolResult
                                                            }

                                                            // ── Pending / active tool call on assistant message ──
                                                            ColumnLayout {
                                                                visible: modelData.functionCall !== undefined && !messageDelegate.isToolResult
                                                                Layout.fillWidth: true
                                                                spacing: 6

                                                                readonly property string toolName: modelData.functionCall ? (modelData.functionCall.name || "") : ""
                                                                readonly property string toolDetail: {
                                                                    if (!modelData.functionCall || !modelData.functionCall.args)
                                                                        return "";
                                                                    let a = modelData.functionCall.args;
                                                                    if (a.command)
                                                                        return a.command;
                                                                    try {
                                                                        return JSON.stringify(a);
                                                                    } catch (e) {
                                                                        return String(a);
                                                                    }
                                                                }
                                                                readonly property string toolTitle: {
                                                                    if (modelData.functionPending === true)
                                                                        return "Approve tool?";
                                                                    if (modelData.functionApproved === true)
                                                                        return modelData.toolStatus === "completed" ? "Tool completed" : "Tool approved";
                                                                    if (modelData.functionApproved === false)
                                                                        return "Tool rejected";
                                                                    return toolName || "Tool";
                                                                }

                                                                Rectangle {
                                                                    Layout.fillWidth: true
                                                                    height: 1
                                                                    color: Colors.outline
                                                                    opacity: 0.2
                                                                    visible: (modelData.content || "").length > 0
                                                                }

                                                                RowLayout {
                                                                    Layout.fillWidth: true
                                                                    spacing: 8

                                                                    StyledText {
                                                                        text: Icons.terminal
                                                                        font.family: Icons.font
                                                                        font.pixelSize: Styling.fontSize(0)
                                                                        color: Styling.srItem("overprimary")
                                                                    }

                                                                    ColumnLayout {
                                                                        Layout.fillWidth: true
                                                                        spacing: 1

                                                                        StyledText {
                                                                            renderType: Text.NativeRendering
                                                                            Layout.fillWidth: true
                                                                            text: parent.parent.parent.toolTitle
                                                                            color: Colors.overSurface
                                                                            font.family: Config.theme.font
                                                                            font.pixelSize: Styling.fontSize(-1)
                                                                            font.weight: Font.Medium
                                                                            elide: Text.ElideRight
                                                                        }

                                                                        StyledText {
                                                                            renderType: Text.NativeRendering
                                                                            Layout.fillWidth: true
                                                                            visible: parent.parent.parent.toolDetail.length > 0
                                                                            text: parent.parent.parent.toolDetail
                                                                            color: Colors.outline
                                                                            font.family: "Monospace"
                                                                            font.pixelSize: Styling.fontSize(-3)
                                                                            elide: Text.ElideRight
                                                                        }
                                                                    }
                                                                }

                                                                RowLayout {
                                                                    visible: modelData.functionPending === true
                                                                    Layout.alignment: Qt.AlignRight
                                                                    spacing: 8

                                                                    Button {
                                                                        text: "Reject"
                                                                        highlighted: true
                                                                        flat: true
                                                                        onClicked: mainChatArea.session.rejectCommand(index)

                                                                        background: StyledRect {
                                                                            variant: "error"
                                                                            opacity: parent.hovered ? 0.8 : 0.5
                                                                            radius: Styling.radius(4)
                                                                        }

                                                                        contentItem: StyledText {
                                                                            text: parent.text
                                                                            color: Colors.overError
                                                                            font.family: Config.theme.font
                                                                            horizontalAlignment: Text.AlignHCenter
                                                                            verticalAlignment: Text.AlignVCenter
                                                                        }
                                                                    }

                                                                    Button {
                                                                        text: "Approve"
                                                                        highlighted: true
                                                                        flat: true
                                                                        onClicked: mainChatArea.session.approveCommand(index)

                                                                        background: StyledRect {
                                                                            variant: "primary"
                                                                            opacity: parent.hovered ? 1 : 0.8
                                                                            radius: Styling.radius(4)
                                                                        }

                                                                        contentItem: StyledText {
                                                                            text: parent.text
                                                                            color: Colors.overPrimary
                                                                            font.family: Config.theme.font
                                                                            horizontalAlignment: Text.AlignHCenter
                                                                            verticalAlignment: Text.AlignVCenter
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    StyledText {
                                                        renderType: Text.NativeRendering
                                                        font.hintingPreference: Font.PreferFullHinting
                                                        id: modelIndicator
                                                        visible: !isUser && !isSystem && (modelData.model ? true : false)
                                                        text: retryMode ? "Retry with another model " + Icons.caretRight : (modelData.model || "")
                                                        color: Colors.outline
                                                        font.family: Config.theme.font
                                                        font.pixelSize: Styling.fontSize(-2)
                                                        font.weight: Font.Medium

                                                        anchors.top: bubble.bottom
                                                        anchors.topMargin: 4
                                                        anchors.left: bubble.left
                                                        anchors.leftMargin: 4

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor

                                                            onClicked: {
                                                                if (retryMode) {
                                                                    mainChatArea.retryIndex = index;
                                                                    modelSelector.open();
                                                                    retryMode = false;
                                                                } else {
                                                                    retryMode = true;
                                                                    retryTimer.start();
                                                                }
                                                            }
                                                        }

                                                        Timer {
                                                            id: retryTimer
                                                            interval: 5000
                                                            onTriggered: retryMode = false
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    }

                                    AssistantQuestions {
                                        session: mainChatArea.session
                                        width: messageColumn.width
                                    }

                                    Item {
                                        width: chatView.width
                                        height: mainChatArea.session.isBusy ? Math.max(56, busyStatusRow.implicitHeight + 24) : 0
                                        visible: mainChatArea.session.isBusy

                                        RowLayout {
                                            id: busyStatusRow
                                            anchors.centerIn: parent
                                            width: Math.max(0, parent.width - 24)
                                            spacing: 12

                                            Row {
                                                spacing: 4

                                                Repeater {
                                                    model: 3

                                                    Rectangle {
                                                        width: 7
                                                        height: 7
                                                        radius: 4
                                                        color: Styling.srItem("overprimary")
                                                        opacity: 0.5

                                                        SequentialAnimation on opacity {
                                                            loops: Animation.Infinite
                                                            running: mainChatArea.session.isBusy

                                                            PauseAnimation {
                                                                duration: index * 200
                                                            }

                                                            PropertyAnimation {
                                                                to: 1
                                                                duration: 400
                                                            }

                                                            PropertyAnimation {
                                                                to: 0.5
                                                                duration: 400
                                                            }

                                                            PauseAnimation {
                                                                duration: 400 - (index * 200)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Flickable {
                                                id: busyStatusScroll
                                                objectName: "assistantStatusScroll"
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Math.min(112, busyStatusText.implicitHeight)
                                                contentWidth: width
                                                contentHeight: busyStatusText.implicitHeight
                                                clip: true
                                                boundsBehavior: Flickable.StopAtBounds
                                                onContentHeightChanged: {
                                                    if (!moving)
                                                        contentY = Math.max(0, contentHeight - height);
                                                }

                                                TextEdit {
                                                    id: busyStatusText
                                                    objectName: "assistantStatusText"
                                                    width: busyStatusScroll.width
                                                    text: mainChatArea.session.statusText || "Thinking through your request…"
                                                    textFormat: Text.PlainText
                                                    color: Colors.overSurface
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(0)
                                                    wrapMode: TextEdit.Wrap
                                                    readOnly: true
                                                    selectByMouse: true
                                                }
                                            }

                                            Button {
                                                flat: true
                                                padding: 6
                                                onClicked: mainChatArea.session.cancelGeneration(true)

                                                contentItem: Row {
                                                    spacing: 4
                                                    StyledText {
                                                        text: Icons.stop
                                                        font.family: Icons.font
                                                        font.pixelSize: Styling.fontSize(-2)
                                                        color: Colors.overError
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    StyledText {
                                                        text: "Stop"
                                                        font.family: Config.theme.font
                                                        font.pixelSize: Styling.fontSize(-2)
                                                        color: Colors.overError
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }

                                                background: StyledRect {
                                                    variant: "error"
                                                    opacity: parent.hovered ? 0.35 : 0.18
                                                    radius: Styling.radius(6)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ModelSelectorPopup {
                            id: modelSelector
                            parent: mainChatArea

                            onModelSelected: {
                                if (mainChatArea.retryIndex > -1) {
                                    mainChatArea.session.regenerateResponse(mainChatArea.retryIndex);
                                    mainChatArea.retryIndex = -1;
                                }
                            }
                        }

                        Connections {
                            target: mainChatArea.session

                            function onChatModelChanged() {
                                if (chatView.followBottom)
                                    chatScrollTimer.restart();
                            }

                            function onModelSelectionRequested() {
                                modelSelector.open();
                            }
                        }

                        Item {
                            id: inputContainer
                            property int attachmentPreviewHeight: attachmentPreview.visible ? Math.min(attachmentPreview.contentHeight, 120) + 8 : 0
                            height: attachmentPreviewHeight + Math.min(150, Math.max(48, inputField.contentHeight + 24))

                            anchors.bottom: parent.bottom
                            property real centerMargin: (parent.height / 2) - (height / 2)
                            anchors.bottomMargin: mainChatArea.isWelcome ? centerMargin : 20
                            anchors.horizontalCenter: parent.horizontalCenter

                            width: Math.min(600, parent.width - 40)

                            Behavior on anchors.bottomMargin {
                                NumberAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            StyledRect {
                                id: inputStyledRect
                                anchors.fill: parent
                                variant: "pane"
                                radius: Styling.radius(16)
                                border.color: Qt.alpha(Colors.primary, inputField.activeFocus ? 0.6 : 0.22)
                                border.width: 1
                                enableShadow: true

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.urls && drop.urls.length > 0) {
                                            for (let i = 0; i < drop.urls.length; i++)
                                                mainChatArea.addAttachmentFromFile(drop.urls[i]);
                                            drop.accepted = true;
                                            return;
                                        }
                                        if (drop.text && drop.text.length > 0) {
                                            mainChatArea.addAttachmentsFromUriList(drop.text);
                                            drop.accepted = true;
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    Flickable {
                                        id: attachmentPreview
                                        height: visible ? Math.min(contentHeight, 120) : 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 12
                                        Layout.rightMargin: 12
                                        Layout.topMargin: 8
                                        Layout.preferredHeight: height
                                        visible: mainChatArea.pendingAttachments.length > 0
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height

                                        contentWidth: width
                                        contentHeight: attachmentsFlow.height

                                        Flow {
                                            id: attachmentsFlow
                                            width: attachmentPreview.width
                                            spacing: 6

                                            Repeater {
                                                model: mainChatArea.pendingAttachments

                                                Item {
                                                    width: 48
                                                    height: 48

                                                    StyledRect {
                                                        anchors.fill: parent
                                                        variant: "surface"
                                                        radius: Styling.radius(6)

                                                        Image {
                                                            anchors.fill: parent
                                                            anchors.margins: 2
                                                            source: "data:" + modelData.mimeType + ";base64," + modelData.base64
                                                            fillMode: Image.PreserveAspectCrop
                                                            sourceSize.width: 48
                                                            sourceSize.height: 48
                                                        }
                                                    }

                                                    Button {
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.rightMargin: -4
                                                        anchors.topMargin: -4
                                                        width: 16
                                                        height: 16
                                                        flat: true
                                                        z: 1

                                                        contentItem: StyledText {
                                                            text: Icons.cancel
                                                            font.family: Icons.font
                                                            font.pixelSize: Styling.fontSize(-4)
                                                            color: Colors.overSurface
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        background: Rectangle {
                                                            color: Colors.surfaceBright
                                                            radius: 8
                                                        }

                                                        onClicked: mainChatArea.removeAttachment(index)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.leftMargin: 16
                                    Layout.rightMargin: 16
                                    Layout.topMargin: attachmentPreview.visible ? 0 : 8
                                    Layout.bottomMargin: 8

                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        TextArea {
                                            id: inputField
                                            focus: true
                                            activeFocusOnTab: true

                                            // TextArea accepts the press before the background
                                            // MouseArea can request keyboard ownership.
                                            TapHandler {
                                                onPressedChanged: {
                                                    if (pressed) {
                                                        root.wantsFocus = true;
                                                        inputField.forceActiveFocus();
                                                    }
                                                }
                                            }
                                            placeholderText: mainChatArea.isWelcome ? "Ask AI or type /help..." : "Message AI..."
                                            placeholderTextColor: Colors.outline
                                            font.pixelSize: Styling.fontSize(0)
                                            color: Colors.overBackground
                                            wrapMode: TextEdit.Wrap

                                            onTextChanged: {
                                                mainChatArea.session.inputDraft = text;
                                                mainChatArea.session.bridgeDirty = true;
                                                if (text.startsWith("/")) {
                                                    const query = text.substring(1).toLowerCase();
                                                    suggestionsModel.clear();
                                                    root.slashCommands.forEach(cmd => {
                                                        if (cmd.name.startsWith(query)) {
                                                            suggestionsModel.append(cmd);
                                                        }
                                                    });
                                                    if (suggestionsList.currentIndex < 0 || suggestionsList.currentIndex >= suggestionsModel.count)
                                                        suggestionsList.currentIndex = 0;
                                                } else {
                                                    suggestionsModel.clear();
                                                }
                                            }

                                            background: null

                                            Keys.onPressed: event => {
                                                if (suggestionsPopup.visible) {
                                                    if (event.key === Qt.Key_Up) {
                                                        suggestionsPopup.selectPrevious();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Down) {
                                                        suggestionsPopup.selectNext();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                        suggestionsPopup.executeSelection();
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                }
                                                if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                                    clipboardTypesProcess.running = true;
                                                    return;
                                                }
                                                if (event.key === Qt.Key_Escape) {
                                                    if (root.menuExpanded) {
                                                        root.menuExpanded = false;
                                                    } else {
                                                        // Never cancel the agent with Escape — that left broken
                                                        // tool_call history and "No response" on the next message.
                                                        // Use the Stop button to abort; Escape only releases focus.
                                                        root.wantsFocus = false;
                                                        inputField.focus = false;
                                                    }
                                                    event.accepted = true;
                                                    return;
                                                }
                                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                                    if (text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                        root.sendCurrentMessage();
                                                    }
                                                    event.accepted = true;
                                                }
                                            }
                                            Component.onCompleted: {
                                                if (root.active)
                                                    forceActiveFocus();
                                            }
                                        }
                                    }

                                    Button {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        flat: true

                                        contentItem: StyledText {
                                            text: Icons.plus
                                            font.family: Icons.font
                                            font.pixelSize: Styling.fontSize(6)
                                            color: Colors.outline
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            color: parent.hovered ? Colors.surfaceBright : "transparent"
                                            radius: 16
                                        }

                                        onClicked: zenityProcess.running = true
                                    }
                                    Button {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        flat: true
                                        visible: inputField.text.length > 0 || mainChatArea.pendingAttachments.length > 0

                                        contentItem: StyledText {
                                            text: Icons.paperPlane
                                            font.family: Icons.font
                                            font.pixelSize: Styling.fontSize(6)
                                            color: Styling.srItem("overprimary")
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            color: parent.hovered ? Colors.surfaceBright : "transparent"
                                            radius: 16
                                        }

                                        onClicked: {
                                            if (inputField.text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                root.sendCurrentMessage();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                            // Slash suggestions sit above the input (sibling of the input pane so
                            // they are not clipped by it). Not a Popup — avoids overlay ghost text.
                            StyledRect {
                                id: suggestionsPopup
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 8
                                height: visible ? Math.min(suggestionsModel.count * 40 + 8, mainChatArea.isWelcome ? 128 : 208) : 0
                                visible: inputField.text.startsWith("/") && suggestionsModel.count > 0
                                z: 20
                                variant: "popup"
                                radius: Styling.radius(12)
                                enableShadow: false
                                clip: true

                                function selectNext() {
                                    if (suggestionsModel.count === 0)
                                        return;
                                    suggestionsList.currentIndex = (suggestionsList.currentIndex + 1) % suggestionsModel.count;
                                }

                                function selectPrevious() {
                                    if (suggestionsModel.count === 0)
                                        return;
                                    suggestionsList.currentIndex = (suggestionsList.currentIndex - 1 + suggestionsModel.count) % suggestionsModel.count;
                                }

                                function executeSelection() {
                                    if (suggestionsList.currentIndex >= 0 && suggestionsList.currentIndex < suggestionsModel.count) {
                                        let item = suggestionsModel.get(suggestionsList.currentIndex);
                                        inputField.text = "/" + item.name + " ";
                                        inputField.cursorPosition = inputField.text.length;
                                        inputField.forceActiveFocus();
                                    }
                                }

                                ListView {
                                    id: suggestionsList
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    interactive: contentHeight > height
                                    currentIndex: 0

                                    model: ListModel {
                                        id: suggestionsModel
                                    }

                                    highlightMoveDuration: 0

                                    delegate: Button {
                                        id: suggestionDelegate
                                        width: suggestionsList.width
                                        height: 40
                                        flat: true
                                        highlighted: ListView.isCurrentItem

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 8

                                            StyledText {
                                                renderType: Text.NativeRendering
                                                font.hintingPreference: Font.PreferFullHinting
                                                text: "/" + model.name
                                                font.family: Config.theme.font
                                                font.weight: Font.Bold
                                                color: (suggestionDelegate.highlighted || suggestionDelegate.hovered)
                                                    ? Colors.primary
                                                    : Colors.overSurface
                                            }

                                            StyledText {
                                                renderType: Text.NativeRendering
                                                font.hintingPreference: Font.PreferFullHinting
                                                text: model.description
                                                font.family: Config.theme.font
                                                color: Colors.outline
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        background: StyledRect {
                                            variant: (suggestionDelegate.highlighted || suggestionDelegate.hovered) ? "focus" : "transparent"
                                            radius: Styling.radius(8)
                                        }

                                        onClicked: {
                                            suggestionsList.currentIndex = index;
                                            suggestionsPopup.executeSelection();
                                        }
                                    }
                                }
                            }
                        }

                    StyledText {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                            anchors.top: inputContainer.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: inputContainer.horizontalCenter

                            text: mainChatArea.session.currentModel ? mainChatArea.session.currentModel.name : ""
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelSelector.open()
                            }

                            visible: mainChatArea.isWelcome

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }

                            opacity: visible ? 1 : 0
                        }
                    }
                        }
                    }
                }
            }
        }
    }
}
