import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.widgets.projects
import qs.config

Item {
    id: root

    property point lastPointerPosition: Qt.point(-1, -1)

    function rememberPointer(area: Item, x: real, y: real) {
        lastPointerPosition = area.mapToGlobal(x, y);
    }

    function pointerMoved(area: Item, x: real, y: real): bool {
        const position = area.mapToGlobal(x, y);
        const moved = position.x !== lastPointerPosition.x || position.y !== lastPointerPosition.y;
        lastPointerPosition = position;
        return moved;
    }
    
    implicitWidth: 464
    implicitHeight: 368
    
    focus: true

    onActiveFocusChanged: {
        if (activeFocus) {
            focusSearchInput();
        }
    }

    function switchMode() {
        appLauncher.expandedItemIndex = -1;
        appLauncher.selectedOptionIndex = 0;
        appLauncher.keyboardNavigation = false;
        GlobalStates.launcherMode =
            GlobalStates.launcherMode === "projects" ? "apps" : "projects";
        Qt.callLater(() => root.focusSearchInput());
    }

    // Focus on the next frame; retry only while the layer is acquiring focus.
    Timer {
        id: focusRetryTimer
        interval: 16
        repeat: true
        property int retries: 0
        onTriggered: {
            if (root.focusActiveSearchInput() || ++retries >= 10)
                stop();
        }
    }

    function focusSearchInput() {
        Qt.callLater(() => {
            if (!root.focusActiveSearchInput()) {
                focusRetryTimer.retries = 0;
                focusRetryTimer.restart();
            }
        });
    }

    function focusActiveSearchInput(): bool {
        if (!root.visible || !root.enabled)
            return false;
        if (GlobalStates.launcherMode === "projects") {
            projectPicker.focusSearchInput();
            return projectPicker.activeFocus;
        }
        return appLauncher.focusSearchInput();
    }

    Connections {
        target: GlobalStates

        function onLauncherModeChanged() {
            root.focusSearchInput();
        }
    }

    Component.onCompleted: {
        focusSearchInput();
    }

    // App launcher / run menu.
    Item {
        id: appLauncher
        objectName: "launcher-apps"
        anchors.fill: parent
        visible: GlobalStates.launcherMode === "apps"
        enabled: visible


        readonly property string searchText: GlobalStates.launcherSearchText
        property bool showResults: searchText.length > 0
        readonly property int selectedIndex: GlobalStates.launcherSelectedIndex

        // Options menu state (expandable list)
        property int expandedItemIndex: -1
        property int selectedOptionIndex: 0
        property bool keyboardNavigation: false

        // Animated model for smooth filtering
        property var filteredApps: []
        property var appsById: ({})

        function updateFilteredApps() {
            if (searchText.length > 0) {
                filteredApps = AppSearch.fuzzyQuery(searchText);
            } else {
                filteredApps = AppSearch.getAllApps();
            }
        }

        onFilteredAppsChanged: {
            resultsList.enableScrollAnimation = false;
            resultsList.contentY = 0;
            updateAppsModel();
            Qt.callLater(() => {
                resultsList.enableScrollAnimation = true;
            });
        }

        function updateAppsModel() {
            // Keep unchanged rows alive instead of destroying every delegate per keypress.
            const nextApps = filteredApps;
            const nextById = {};
            for (let i = 0; i < nextApps.length; i++) {
                const app = nextApps[i];
                nextById[app.id] = app;
                const row = {
                    appId: app.id, appName: app.name, appIcon: app.icon,
                    appComment: app.comment, appExecString: app.execString,
                    appCategories: app.categories, appRunInTerminal: app.runInTerminal
                };
                if (i < appsModel.count && appsModel.get(i).appId === app.id) {
                    appsModel.set(i, row);
                    continue;
                }
                let existing = -1;
                for (let j = i + 1; j < appsModel.count; j++) {
                    if (appsModel.get(j).appId === app.id) {
                        existing = j;
                        break;
                    }
                }
                if (existing >= 0) {
                    appsModel.move(existing, i, 1);
                    appsModel.set(i, row);
                } else {
                    appsModel.insert(i, row);
                }
            }
            if (appsModel.count > nextApps.length)
                appsModel.remove(nextApps.length, appsModel.count - nextApps.length);
            appsById = nextById;
            // ListView can clamp its index during model changes; selection stays
            // owned by GlobalStates instead of feeding model changes back into it.
            if (GlobalStates.launcherSelectedIndex >= appsModel.count)
                GlobalStates.launcherSelectedIndex = appsModel.count - 1;
        }

        function executeApp(appId) {
            let app = appsById[appId];
            if (app && app.execute) {
                app.execute();
                // Record usage for sorting priority
                UsageTracker.recordUsage(appId);
            }
        }

        ListModel {
            id: appsModel
        }

        Component.onCompleted: Qt.callLater(updateFilteredApps)

        Connections {
            target: UsageTracker
            function onUsageDataReady() {
                AppSearch.invalidateCache();
                appLauncher.updateFilteredApps();
            }
        }

        Connections {
            target: AppSearch
            function onListChanged() {
                Qt.callLater(appLauncher.updateFilteredApps);
            }
        }

        onSearchTextChanged: {
            updateFilteredApps();
        }

        onSelectedIndexChanged: {
            if (selectedIndex === -1 && resultsList.count > 0) {
                resultsList.contentY = 0;
            }

            // Close expanded options when selection changes to a different item
            if (expandedItemIndex >= 0 && selectedIndex !== expandedItemIndex) {
                expandedItemIndex = -1;
                selectedOptionIndex = 0;
                keyboardNavigation = false;
            }
        }

        function clearSearch() {
            GlobalStates.clearLauncherState();
            searchInput.focusInput();
        }

        function focusSearchInput() {
            return searchInput.focusInput();
        }

        function adjustScrollForExpandedItem(index) {
            if (index < 0 || index >= appsModel.count)
                return;

            // Calculate Y position of the item
            var itemY = 0;
            for (var i = 0; i < index; i++) {
                itemY += 48; // All items before are collapsed (base height)
            }

            // Calculate expanded item height - 2 options (Launch, Create Shortcut)
            var listHeight = 36 * 2;
            var expandedHeight = 48 + 4 + listHeight + 8;


            // Calculate max valid scroll position
            var maxContentY = Math.max(0, resultsList.contentHeight - resultsList.height);

            // Current viewport bounds
            var viewportTop = resultsList.contentY;
            var viewportBottom = viewportTop + resultsList.height;

            // Only scroll if item is not fully visible
            var itemBottom = itemY + expandedHeight;

            if (itemY < viewportTop) {
                // Item top is above viewport - scroll up to show it
                resultsList.contentY = itemY;
            } else if (itemBottom > viewportBottom) {
                // Item bottom is below viewport - scroll down to show it
                resultsList.contentY = Math.min(itemBottom - resultsList.height, maxContentY);
            }
        // Otherwise, item is already fully visible - no scroll needed
        }

        Behavior on height {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Item {
            id: mainLayout
            anchors.fill: parent

            // Search input
            SearchInput {
                id: searchInput
                objectName: "launcher-search"
                variant: "internalbg"
                width: parent.width
                anchors.top: parent.top
                text: GlobalStates.launcherSearchText
                placeholderText: "Type to find an app…"
                iconText: Icons.magnifyingGlass
                handleTabNavigation: true
                clearOnEscape: false

                onSearchTextChanged: text => {

                    GlobalStates.launcherSearchText = text;

                    resultsList.enableScrollAnimation = false;

                    if (text.length > 0) {
                        GlobalStates.launcherSelectedIndex = appsModel.count > 0 ? 0 : -1;

                        resultsList.contentY = 0;
                    } else {
                        GlobalStates.launcherSelectedIndex = -1;

                        resultsList.contentY = 0;
                    }

                    Qt.callLater(() => {
                        resultsList.enableScrollAnimation = true;
                    });
                }

                onTabPressed: root.switchMode()
                onShiftTabPressed: root.switchMode()

                onAccepted: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        // Execute selected option when menu is expanded
                        let selectedApp = appsModel.get(appLauncher.expandedItemIndex);
                        if (selectedApp) {
                            // Build options array
                            let options = [function () {
                                    appLauncher.executeApp(selectedApp.appId);
                                    Visibilities.setActiveModule("");
                                }, function () {
                                    // Create shortcut
                                    let desktopDir = Quickshell.env("XDG_DESKTOP_DIR") || Quickshell.env("HOME") + "/Desktop";
                                    let timestamp = Date.now();
                                    let fileName = selectedApp.appId + "-" + timestamp + ".desktop";
                                    let filePath = desktopDir + "/" + fileName;

                                    let desktopContent = "[Desktop Entry]\n" + "Version=1.0\n" + "Type=Application\n" + "Name=" + selectedApp.appName + "\n" + "Exec=" + selectedApp.appExecString + "\n" + "Icon=" + selectedApp.appIcon + "\n" + (selectedApp.appComment ? "Comment=" + selectedApp.appComment + "\n" : "") + (selectedApp.appCategories.length > 0 ? "Categories=" + selectedApp.appCategories.join(";") + ";\n" : "") + (selectedApp.appRunInTerminal ? "Terminal=true\n" : "Terminal=false\n");

                                    let writeCmd = "printf '%s' '" + desktopContent.replace(/'/g, "'\\''") + "' > \"" + filePath + "\" && chmod 755 \"" + filePath + "\" && gio set \"" + filePath + "\" metadata::trusted true";
                                    copyProcess.command = ["sh", "-c", writeCmd];
                                    copyProcess.running = true;
                                    appLauncher.expandedItemIndex = -1;
                                }];

                            if (appLauncher.selectedOptionIndex >= 0 && appLauncher.selectedOptionIndex < options.length) {
                                options[appLauncher.selectedOptionIndex]();
                            }
                        }
                    } else {
                        if (appLauncher.selectedIndex >= 0 && appLauncher.selectedIndex < appsModel.count) {
                            let selectedApp = appsModel.get(appLauncher.selectedIndex);
                            if (selectedApp) {
                                appLauncher.executeApp(selectedApp.appId);
                                Visibilities.setActiveModule("");
                            }
                        }
                    }
                }

                onShiftAccepted: {
                    if (appLauncher.selectedIndex >= 0 && appLauncher.selectedIndex < resultsList.count) {
                        // Toggle expanded state
                        if (appLauncher.expandedItemIndex === appLauncher.selectedIndex) {
                            appLauncher.expandedItemIndex = -1;
                            appLauncher.selectedOptionIndex = 0;
                            appLauncher.keyboardNavigation = false;
                        } else {
                            appLauncher.expandedItemIndex = appLauncher.selectedIndex;
                            appLauncher.selectedOptionIndex = 0;
                            appLauncher.keyboardNavigation = true;
                        }
                    }
                }

                onEscapePressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        appLauncher.expandedItemIndex = -1;
                        appLauncher.selectedOptionIndex = 0;
                        appLauncher.keyboardNavigation = false;
                    } else if (searchInput.text.length > 0) {
                        searchInput.text = "";
                    } else {
                        Visibilities.setActiveModule("");
                    }
                }

                onDownPressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        // Navigate options when menu is expanded (2 options)
                        if (appLauncher.selectedOptionIndex < 1) {
                            appLauncher.selectedOptionIndex++;
                            appLauncher.keyboardNavigation = true;
                        }
                    } else if (resultsList.count > 0) {

                        if (appLauncher.selectedIndex === -1) {
                            GlobalStates.launcherSelectedIndex = 0;
                        } else if (appLauncher.selectedIndex < resultsList.count - 1) {
                            GlobalStates.launcherSelectedIndex++;
                        }
                    }
                }

                onUpPressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        // Navigate options when menu is expanded
                        if (appLauncher.selectedOptionIndex > 0) {
                            appLauncher.selectedOptionIndex--;
                            appLauncher.keyboardNavigation = true;
                        }
                    } else if (appLauncher.selectedIndex > 0) {
                        GlobalStates.launcherSelectedIndex--;
                    } else if (appLauncher.selectedIndex === 0 && appLauncher.searchText.length === 0) {
                        GlobalStates.launcherSelectedIndex = -1;
                    }
                }

                onPageDownPressed: {
                    if (resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 48);
                        let newIndex = Math.min(appLauncher.selectedIndex + visibleItems, resultsList.count - 1);
                        if (appLauncher.selectedIndex === -1) {
                            newIndex = Math.min(visibleItems - 1, resultsList.count - 1);
                        }
                        GlobalStates.launcherSelectedIndex = newIndex;
                    }
                }

                onPageUpPressed: {
                    if (resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 48);
                        let newIndex = Math.max(appLauncher.selectedIndex - visibleItems, 0);
                        if (appLauncher.selectedIndex === -1) {
                            newIndex = Math.max(resultsList.count - visibleItems, 0);
                        }
                        GlobalStates.launcherSelectedIndex = newIndex;
                    }
                }

                onHomePressed: {
                    if (resultsList.count > 0) {
                        GlobalStates.launcherSelectedIndex = 0;
                    }
                }

                onEndPressed: {
                    if (resultsList.count > 0) {
                        GlobalStates.launcherSelectedIndex = resultsList.count - 1;
                    }
                }
            }

            RowLayout {
                id: keyboardHints
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 24
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: appLauncher.searchText.length > 0
                        ? appsModel.count + (appsModel.count === 1 ? " match" : " matches")
                        : "Applications"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                }
                Text {
                    text: "↵ Open   ·   Tab Projects   ·   Esc Back"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                }
            }

            Column {
                anchors.centerIn: resultsList
                width: resultsList.width - 32
                spacing: 8
                visible: appsModel.count === 0

                Text {
                    width: parent.width
                    text: "No applications found"
                    horizontalAlignment: Text.AlignHCenter
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                }
                Text {
                    width: parent.width
                    text: "Try another name or press Esc to clear"
                    horizontalAlignment: Text.AlignHCenter
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                }
            }

            // Results list
            ListView {
                id: resultsList
                objectName: "launcher-results"
                width: parent.width
                anchors.top: searchInput.bottom
                anchors.bottom: keyboardHints.top
                anchors.bottomMargin: 8
                anchors.topMargin: 8
                visible: true

                clip: true
                interactive: appLauncher.expandedItemIndex === -1
                cacheBuffer: 96
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds

                property bool isScrolling: dragging || flicking

                model: appsModel
                currentIndex: appLauncher.selectedIndex

                property bool enableScrollAnimation: true

                Behavior on contentY {
                    enabled: Config.animDuration > 0 && resultsList.enableScrollAnimation && !resultsList.moving
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }

                onCurrentIndexChanged: {
                    // Manual smooth auto-scroll accounting for variable height items
                    if (currentIndex >= 0) {
                        var itemY = 0;
                        for (var i = 0; i < currentIndex && i < appsModel.count; i++) {
                            var itemHeight = 48;
                            if (i === appLauncher.expandedItemIndex) {
                                var listHeight = 36 * 2;
                                itemHeight = 48 + 4 + listHeight + 8;
                            }
                            itemY += itemHeight;
                        }

                        var currentItemHeight = 48;
                        if (currentIndex === appLauncher.expandedItemIndex) {
                            var listHeight = 36 * 2;
                            currentItemHeight = 48 + 4 + listHeight + 8;
                        }

                        var viewportTop = resultsList.contentY;
                        var viewportBottom = viewportTop + resultsList.height;

                        if (itemY < viewportTop) {
                            // Item is above viewport, scroll up
                            resultsList.contentY = itemY;
                        } else if (itemY + currentItemHeight > viewportBottom) {
                            // Item is below viewport, scroll down
                            resultsList.contentY = itemY + currentItemHeight - resultsList.height;
                        }
                    }
                }

                delegate: Item {
                    required property string appId
                    required property string appName
                    required property string appIcon
                    required property string appComment
                    required property string appExecString
                    required property var appCategories
                    required property bool appRunInTerminal
                    required property int index

                    property bool isExpanded: index === appLauncher.expandedItemIndex

                    width: resultsList.width
                    height: {
                        let baseHeight = 48;
                        if (isExpanded) {
                            var listHeight = 36 * 2;
                            return baseHeight + 4 + listHeight + 8;
                        }
                        return baseHeight;
                    }


                    Behavior on height {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration
                            easing.type: Easing.OutQuart
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: isExpanded ? 48 : parent.height
                        hoverEnabled: !resultsList.isScrolling
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        cursorShape: Qt.PointingHandCursor

                        onEntered: root.rememberPointer(mouseArea, mouseX, mouseY)
                        onPositionChanged: mouse => {
                            if (!root.pointerMoved(mouseArea, mouse.x, mouse.y) || resultsList.isScrolling)
                                return;
                            if (appLauncher.expandedItemIndex === -1) {
                                GlobalStates.launcherSelectedIndex = index;
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                if (!isExpanded) {
                                    appLauncher.executeApp(appId);
                                    Visibilities.setActiveModule("");
                                }
                            } else if (mouse.button === Qt.RightButton) {
                                // Toggle expanded state
                                if (appLauncher.expandedItemIndex === index) {
                                    appLauncher.expandedItemIndex = -1;
                                    appLauncher.selectedOptionIndex = 0;
                                    appLauncher.keyboardNavigation = false;
                                    // Update selection to current hover position after closing
                                    GlobalStates.launcherSelectedIndex = index;
                                } else {
                                    appLauncher.expandedItemIndex = index;
                                    GlobalStates.launcherSelectedIndex = index;
                                    appLauncher.selectedOptionIndex = 0;
                                    appLauncher.keyboardNavigation = false;
                                }
                            }
                        }
                    }

                    // App content (icon and text)
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        height: 32
                        spacing: 12

                        // App icon
                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            Image {
                                mipmap: true
                                id: appIconImage
                                anchors.fill: parent
                                sourceSize: Qt.size(32, 32)
                                source: Quickshell.iconPath(appIcon, "application-x-executable")
                                fillMode: Image.PreserveAspectFit
                                
                                onStatusChanged: {
                                    if (status === Image.Error) {
                                        source = "image://icon/image-missing";
                                    }
                                }
                            }

                            Tinted {
                                anchors.fill: parent
                                sourceItem: appIconImage
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                width: parent.width
                                text: appName
                                color: {
                                    if (isExpanded) {
                                        return Styling.srItem("pane");
                                    } else if (appLauncher.selectedIndex === index) {
                                        return Styling.srItem("primary");
                                    } else {
                                        return Colors.overBackground;
                                    }
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize
                                font.weight: Font.Bold
                                elide: Text.ElideRight

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                width: parent.width
                                text: appComment || ""
                                color: {
                                    if (isExpanded) {
                                        return Styling.srItem("pane");
                                    } else if (appLauncher.selectedIndex === index) {
                                        return Styling.srItem("primary");
                                    } else {
                                        return Colors.outline;
                                    }
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                elide: Text.ElideRight
                                visible: text !== ""

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    // Expandable options list
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 4
                        visible: isExpanded
                        opacity: isExpanded ? 1 : 0

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36 * 2
                            color: Colors.background
                            radius: Styling.radius(0)

                            ListView {
                                id: optionsListView
                                anchors.fill: parent
                                clip: true
                                interactive: false
                                boundsBehavior: Flickable.StopAtBounds
                                model: [
                                    {
                                        text: "Launch",
                                        icon: Icons.launch,
                                        highlightColor: Styling.srItem("overprimary"),
                                        textColor: Styling.srItem("primary"),
                                        action: function () {
                                            appLauncher.executeApp(appId);
                                            Visibilities.setActiveModule("");
                                        }
                                    },
                                    {
                                        text: "Create Shortcut",
                                        icon: Icons.shortcut,
                                        highlightColor: Colors.secondary,
                                        textColor: Styling.srItem("secondary"),
                                        action: function () {
                                            let desktopDir = Quickshell.env("XDG_DESKTOP_DIR") || Quickshell.env("HOME") + "/Desktop";
                                            let timestamp = Date.now();
                                            let fileName = appId + "-" + timestamp + ".desktop";
                                            let filePath = desktopDir + "/" + fileName;

                                            let desktopContent = "[Desktop Entry]\n" + "Version=1.0\n" + "Type=Application\n" + "Name=" + appName + "\n" + "Exec=" + appExecString + "\n" + "Icon=" + appIcon + "\n" + (appComment ? "Comment=" + appComment + "\n" : "") + (appCategories.length > 0 ? "Categories=" + appCategories.join(";") + ";\n" : "") + (appRunInTerminal ? "Terminal=true\n" : "Terminal=false\n");

                                            let writeCmd = "printf '%s' '" + desktopContent.replace(/'/g, "'\\''") + "' > \"" + filePath + "\" && chmod 755 \"" + filePath + "\" && gio set \"" + filePath + "\" metadata::trusted true";
                                            copyProcess.command = ["sh", "-c", writeCmd];
                                            copyProcess.running = true;
                                            appLauncher.expandedItemIndex = -1;
                                        }
                                    }
                                ]
                                currentIndex: appLauncher.selectedOptionIndex
                                highlightFollowsCurrentItem: true
                                highlightRangeMode: ListView.ApplyRange
                                preferredHighlightBegin: 0
                                preferredHighlightEnd: height

                                highlight: StyledRect {
                                    variant: {
                                        if (optionsListView.currentIndex >= 0 && optionsListView.currentIndex < optionsListView.count) {
                                            var item = optionsListView.model[optionsListView.currentIndex];
                                            if (item && item.highlightColor) {
                                                if (item.highlightColor === Colors.secondary)
                                                    return "secondary";
                                                if (item.highlightColor === Colors.tertiary)
                                                    return "tertiary";
                                                if (item.highlightColor === Colors.error)
                                                    return "error";
                                                return "primary";
                                            }
                                        }
                                        return "primary";
                                    }
                                    radius: Styling.radius(0)
                                    visible: optionsListView.currentIndex >= 0
                                    z: -1
                                }

                                highlightMoveDuration: Config.animDuration > 0 ? Config.animDuration / 2 : 0
                                highlightMoveVelocity: -1
                                highlightResizeDuration: Config.animDuration / 2
                                highlightResizeVelocity: -1

                                delegate: Item {
                                    required property var modelData
                                    required property int index

                                    width: optionsListView.width
                                    height: 36

                                    Item {
                                        anchors.fill: parent

                                        RowLayout {

                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 8

                                            Text {
                                                renderType: Text.NativeRendering
                                                font.hintingPreference: Font.PreferFullHinting
                                                text: modelData && modelData.icon ? modelData.icon : ""
                                                font.family: Icons.font
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                textFormat: Text.RichText
                                                color: {
                                                    if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                        return modelData.textColor;
                                                    }
                                                    return Colors.overSurface;
                                                }

                                                Behavior on color {
                                                    enabled: Config.animDuration > 0
                                                    ColorAnimation {
                                                        duration: Config.animDuration / 2
                                                        easing.type: Easing.OutQuart
                                                    }
                                                }
                                            }

                                            Text {
                                                renderType: Text.NativeRendering
                                                font.hintingPreference: Font.PreferFullHinting
                                                Layout.fillWidth: true
                                                text: modelData && modelData.text ? modelData.text : ""
                                                font.family: Config.theme.font
                                                font.pixelSize: Config.theme.fontSize
                                                font.weight: optionsListView.currentIndex === index ? Font.Bold : Font.Normal
                                                color: {
                                                    if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                        return modelData.textColor;
                                                    }
                                                    return Colors.overSurface;
                                                }
                                                elide: Text.ElideRight
                                                maximumLineCount: 1

                                                Behavior on color {
                                                    enabled: Config.animDuration > 0
                                                    ColorAnimation {
                                                        duration: Config.animDuration / 2
                                                        easing.type: Easing.OutQuart
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: optionMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor

                                            onEntered: root.rememberPointer(optionMouseArea, mouseX, mouseY)
                                            onPositionChanged: mouse => {
                                                if (!root.pointerMoved(optionMouseArea, mouse.x, mouse.y))
                                                    return;
                                                optionsListView.currentIndex = index;
                                                appLauncher.selectedOptionIndex = index;
                                                appLauncher.keyboardNavigation = false;
                                            }

                                            onClicked: {
                                                if (modelData && modelData.action) {
                                                    modelData.action();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                highlight: Item {
                    width: resultsList.width
                    height: resultsList.currentItem?.height ?? 0
                    // Model changes can shift the list origin; follow the actual row.
                    y: resultsList.currentItem?.y ?? 0

                    Behavior on y {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    onHeightChanged: {
                        if (appLauncher.expandedItemIndex >= 0 && height > 48) {
                            Qt.callLater(() => {
                                appLauncher.adjustScrollForExpandedItem(appLauncher.expandedItemIndex);
                            });
                        }
                    }

                    StyledRect {
                        anchors.fill: parent
                        variant: {
                            if (appLauncher.expandedItemIndex >= 0 && appLauncher.selectedIndex === appLauncher.expandedItemIndex) {
                                return "pane";
                            } else {
                                return "primary";
                            }
                        }
                        radius: Styling.radius(4)
                        visible: appLauncher.selectedIndex >= 0
                    }
                }

                highlightFollowsCurrentItem: false
            }
        }

        Process {
            id: copyProcess
            running: false

            onExited: function (code) {}
        }
    }

    ProjectPickerView {
        id: projectPicker
        anchors.fill: parent
        visible: GlobalStates.launcherMode === "projects"
        enabled: visible

        onModeSwitchRequested: root.switchMode()
    }

}
