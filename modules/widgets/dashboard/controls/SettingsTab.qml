pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import QtQuick.Effects
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.globals
import "SettingsCrawler.js" as SettingsCrawler

Item {
    id: root
    implicitWidth: 400
    implicitHeight: 300
    // 0: Network, 1: Bluetooth, 2: Mixer, 3: AI, 4: Theme, 5: System, 6: Shell, 7: Keybindings

    property int currentSection: GlobalStates.settingsCurrentTab
    property int selectedIndex: GlobalStates.settingsCurrentTab
    property string searchQuery: ""

    onFilteredSectionsChanged: {
        if (searchQuery.length > 0) {
            selectedIndex = 0;
        } else {
            const index = filteredSections.findIndex(section => section.section === root.currentSection);
            selectedIndex = index >= 0 ? index : 0;
        }
        activateSelection();
    }

    // Timer to restore focus after panel transitions
    Timer {
        id: focusRestoreTimer
        interval: 50
        onTriggered: searchInput.focusInput()
    }

    onSelectedIndexChanged: activateSelection()

    function activateSelection(): void {
        if (!filteredSections || selectedIndex < 0 || selectedIndex >= filteredSections.length)
            return;
        const item = filteredSections[selectedIndex];
        root.currentSection = item.section;
        GlobalStates.settingsCurrentTab = item.section;
        root.dispatchSubSection(item.section, item.subSection);
        root.scrollSidebarToSelection();
        focusRestoreTimer.restart();
    }

    Connections {
        target: GlobalStates
        function onSettingsCurrentTabChanged() {
            if (root.currentSection !== GlobalStates.settingsCurrentTab) {
                const index = root.filteredSections.findIndex(item => item.section === GlobalStates.settingsCurrentTab);
                if (index >= 0)
                    root.selectedIndex = index;
            }
        }
    }

    // Focus the search input (called from parent Dashboard)
    function focusSearchInput() {
        searchInput.focusInput();
    }

    SettingsIndex {
        id: searchIndex
    }

    // Dynamic Settings Indexer
    Item {
        id: settingsIndexer
        visible: false // Headless

        property int currentPanelIndex: 0
        property var aggregatedItems: []
        property bool isIndexing: false

        // Helper to load panels one by one
        Loader {
            id: indexerLoader
            active: settingsIndexer.isIndexing
            asynchronous: true
            source: settingsIndexer.isIndexing && settingsIndexer.currentPanelIndex < contentArea.panelComponents.length ? contentArea.panelComponents[settingsIndexer.currentPanelIndex].component : ""

            onStatusChanged: {
                if (status === Loader.Ready && item) {
                    // Scrape
                    const sectionId = contentArea.panelComponents[settingsIndexer.currentPanelIndex].section;
                    const newItems = SettingsCrawler.crawl(item, sectionId);
                    settingsIndexer.aggregatedItems = settingsIndexer.aggregatedItems.concat(newItems);

                    // Move to next
                    settingsIndexer.currentPanelIndex++;
                } else if (status === Loader.Error) {
                    console.warn("Failed to load panel for indexing:", source);
                    settingsIndexer.currentPanelIndex++;
                }
            }
        }

        onCurrentPanelIndexChanged: {
            if (currentPanelIndex >= contentArea.panelComponents.length) {
                // Done
                if (isIndexing) {
                    isIndexing = false;
                    searchIndex.addDynamicItems(aggregatedItems);
                }
            }
        }

        Component.onCompleted: {
            // Start indexing after a short delay to allow UI to settle
            indexingTimer.start();
        }

        Timer {
            id: indexingTimer
            interval: 500
            onTriggered: {
                settingsIndexer.isIndexing = true;
            }
        }
    }

    // Store pending subsection to apply when panel loads
    property string pendingSubSection: ""

    function dispatchSubSection(sectionId, subSectionId) {
        root.pendingSubSection = subSectionId || "";
        if ([4, 5, 6].includes(sectionId)
                && root.currentSection === sectionId
                && panelLoader.status === Loader.Ready
                && panelLoader.source.toString().endsWith(contentArea.panelComponents[sectionId].component)
                && panelLoader.item?.currentSection !== undefined) {
            panelLoader.item.currentSection = root.pendingSubSection;
            root.pendingSubSection = "";
        }
    }

    // Scroll sidebar to ensure visible selection
    function scrollSidebarToSelection() {
        if (sidebarFlickable.height <= 0)
            return;

        const tabHeight = 48;
        const tabSpacing = 0;
        const itemY = root.selectedIndex * (tabHeight + tabSpacing);

        // Check bounds and scroll if needed
        if (itemY < sidebarFlickable.contentY) {
            sidebarFlickable.contentY = itemY;
        } else if (itemY + tabHeight > sidebarFlickable.contentY + sidebarFlickable.height) {
            sidebarFlickable.contentY = itemY + tabHeight - sidebarFlickable.height;
        }
    }

    // Fuzzy match: checks if all characters of query appear in order in target
    function fuzzyMatch(query, target) {
        if (query.length === 0)
            return true;
        if (target.length === 0)
            return false;
        const lowerQuery = query.toLowerCase();
        const lowerTarget = target.toLowerCase();
        let queryIndex = 0;
        for (let i = 0; i < lowerTarget.length && queryIndex < lowerQuery.length; i++) {
            if (lowerTarget[i] === lowerQuery[queryIndex]) {
                queryIndex++;
            }
        }
        return queryIndex === lowerQuery.length;
    }

    // Score a fuzzy match (higher is better)
    function fuzzyScore(query, target) {
        if (query.length === 0)
            return 0;
        if (target.length === 0)
            return -1;
        const lowerQuery = query.toLowerCase();
        const lowerTarget = target.toLowerCase();

        // Exact match gets highest score
        if (lowerTarget.includes(lowerQuery))
            return 1000 + (100 - target.length);

        // Fuzzy scoring
        let queryIndex = 0, score = 0, consecutive = 0, maxConsecutive = 0;
        for (let i = 0; i < lowerTarget.length && queryIndex < lowerQuery.length; i++) {
            if (lowerTarget[i] === lowerQuery[queryIndex]) {
                queryIndex++;
                consecutive++;
                maxConsecutive = Math.max(maxConsecutive, consecutive);
                if (i === 0 || " -_".includes(lowerTarget[i - 1]))
                    score += 10;
            } else {
                consecutive = 0;
            }
        }
        return queryIndex === lowerQuery.length ? score + maxConsecutive * 5 : -1;
    }

    // Original sections model
    readonly property var sectionModel: [
        {
            icon: Icons.wifiHigh,
            label: "Network",
            section: 0,
            isIcon: true
        },
        {
            icon: Icons.bluetooth,
            label: "Bluetooth",
            section: 1,
            isIcon: true
        },
        {
            icon: Icons.faders,
            label: "Sound",
            section: 2,
            isIcon: true
        },
        {
            icon: Icons.robot,
            label: "Assistant",
            section: 3,
            isIcon: true
        },
        {
            icon: Icons.paintBrush,
            label: "Appearance",
            section: 4,
            isIcon: true
        },
        {
            icon: Icons.circuitry,
            label: "System",
            section: 5,
            isIcon: true
        },
        {
            icon: Icons.gear,
            label: "Shell",
            section: 6,
            isIcon: true
        },
        {
            icon: Icons.keyboard,
            label: "Keyboard shortcuts",
            section: 7,
            isIcon: true
        },
        {
            icon: Icons.layout,
            label: "Window rules",
            section: 8,
            isIcon: true
        },
        {
            icon: Icons.layout,
            label: "Display",
            section: 9,
            isIcon: true
        }
    ]

    // Filtered sections based on search query
    readonly property var filteredSections: {
        if (searchQuery.length === 0)
            return sectionModel;

        const query = searchQuery.toLowerCase();
        return searchIndex.items.filter(item => {
            return fuzzyMatch(query, item.label) || (item.keywords && item.keywords.includes(query));
        }).map(item => {
            // Find section metadata
            const sectionMeta = sectionModel.find(s => s.section === item.section) || {};
            return {
                label: item.label,
                section: item.section,
                subSection: item.subSection || "",
                subLabel: item.subLabel || "",
                // Use section icon instead of item icon
                icon: sectionMeta.icon || item.icon,
                isIcon: sectionMeta.isIcon !== undefined ? sectionMeta.isIcon : (item.isIcon !== undefined ? item.isIcon : true),
                score: fuzzyScore(query, item.label)
            };
        }).sort((a, b) => b.score - a.score);
    }

    // Find the index of current section in filtered list
    function getFilteredIndex(sectionId) {
        for (let i = 0; i < filteredSections.length; i++) {
            if (filteredSections[i].section === sectionId)
                return i;
        }
        return -1;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 24

        // Sidebar area: search + list
        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.maximumWidth: 220
            Layout.fillHeight: true
            spacing: 4

            StyledText {
                text: "Settings"
                font.pixelSize: Styling.fontSize(14)
                font.bold: true
                Layout.topMargin: 12
            }
            StyledText {
                text: "System and app settings"
                color: Colors.overSurfaceVariant
                Layout.bottomMargin: 18
            }
            // Search input (separate from panel list)
            SearchInput {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: "Find a setting…"
                clearOnEscape: true

                onSearchTextChanged: text => {
                    root.searchQuery = text;
                }
                // ESC to escape dashboard
                onEscapePressed: {
                    searchInput.focus = false;
                    root.forceActiveFocus();
                }

                onAccepted: {
                    // If single result, select it; if multiple, select top one
                    if (root.filteredSections.length > 0) {
                        const item = root.filteredSections[root.selectedIndex];
                        root.currentSection = item.section;
                        root.dispatchSubSection(item.section, item.subSection);
                    }
                }

                onDownPressed: {
                    if (root.selectedIndex < root.filteredSections.length - 1) {
                        root.selectedIndex++;
                    } else {
                        root.selectedIndex = 0;
                    }
                }

                onUpPressed: {
                    if (root.selectedIndex > 0) {
                        root.selectedIndex--;
                    } else {
                        root.selectedIndex = root.filteredSections.length - 1;
                    }
                }
            }

            // Sidebar container with background
            StyledRect {
                id: sidebarContainer
                variant: "common"
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: sidebarFlickable
                    anchors.fill: parent
                    anchors.margins: 4
                    contentWidth: width
                    contentHeight: sidebar.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Behavior on contentY {
                        enabled: Config.animDuration > 0 && !sidebarFlickable.moving
                        NumberAnimation {
                            duration: Motion.feedback
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Sliding highlight behind tabs
                    StyledRect {
                        id: tabHighlight
                        variant: "focus"
                        width: parent.width
                        height: 48
                        radius: Styling.radius(-6)
                        z: 0

                        readonly property int tabHeight: 48
                        readonly property int tabSpacing: 0

                        x: 0
                        y: {
                            const idx = root.selectedIndex;
                            return idx >= 0 ? idx * (tabHeight + tabSpacing) : 0;
                        }
                        visible: root.selectedIndex >= 0 && root.selectedIndex < root.filteredSections.length

                        Behavior on y {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Motion.feedback
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Column {
                        id: sidebar
                        width: parent.width
                        spacing: 0
                        z: 1

                        Repeater {
                            model: root.filteredSections

                            delegate: Button {
                                id: sidebarButton
                                required property var modelData
                                required property int index

                                width: sidebar.width
                                height: 48
                                flat: true
                                hoverEnabled: true

                                property bool isActive: index === root.selectedIndex

                                background: Item {}

                                contentItem: Row {
                                    spacing: 8

                                    // Icon on the left (font icon)
                                    StyledText {
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting
                                        id: iconText
                                        text: sidebarButton.modelData.isIcon ? sidebarButton.modelData.icon : ""
                                        font.family: Icons.font
                                        font.pixelSize: Styling.fontSize(6)
                                        color: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")
                                        anchors.verticalCenter: parent.verticalCenter
                                        leftPadding: 10
                                        visible: sidebarButton.modelData.isIcon && (root.searchQuery.length === 0 || !sidebarButton.modelData.subSection)

                                        Behavior on color {
                                            enabled: Config.animDuration > 0
                                            ColorAnimation {
                                                duration: Config.animDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    // SVG icon
                                    Item {
                                        width: 30
                                        height: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !sidebarButton.modelData.isIcon && (root.searchQuery.length === 0 || !sidebarButton.modelData.subSection)

                                        Image {
                                            id: svgIcon
                                            width: 20
                                            height: 20
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 5
                                            source: !sidebarButton.modelData.isIcon ? sidebarButton.modelData.icon : ""
                                            sourceSize: Qt.size(width * 2, height * 2)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                brightness: 1.0
                                                colorization: 1.0
                                                colorizationColor: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")
                                            }
                                        }
                                    }

                                    // Text
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter

                                        StyledText {
                                            renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferFullHinting
                                            text: sidebarButton.modelData.label
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: sidebarButton.isActive ? Font.Bold : Font.Normal
                                            color: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")

                                            Behavior on color {
                                                enabled: Config.animDuration > 0
                                                ColorAnimation {
                                                    duration: Config.animDuration
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        StyledText {
                                            renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferFullHinting
                                            visible: !!sidebarButton.modelData.subLabel
                                            text: sidebarButton.modelData.subLabel || ""
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-2)
                                            color: Colors.overSurfaceVariant
                                        }
                                    }
                                }

                                onClicked: {
                                    root.selectedIndex = index;
                                    // currentSection updates via binding on selectedIndex
                                    root.dispatchSubSection(sidebarButton.modelData.section, sidebarButton.modelData.subSection);
                                }
                            }
                        }
                    }

                    // Scroll wheel navigation between sections
                    WheelHandler {
                        enabled: sidebarFlickable.contentHeight <= sidebarFlickable.height
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            if (event.angleDelta.y > 0 && root.selectedIndex > 0) {
                                root.selectedIndex--;
                            } else if (event.angleDelta.y < 0 && root.selectedIndex < root.filteredSections.length - 1) {
                                root.selectedIndex++;
                            }
                        }
                    }
                }
            }
        }

        // Content area with animated transitions
        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            property int previousSection: 0
            readonly property int maxContentWidth: Math.min(760, width - 24)

            // Track section changes for animation direction
            onVisibleChanged: {
                if (visible) {
                    contentArea.previousSection = root.currentSection;
                }
            }

            Connections {
                target: root
                function onCurrentSectionChanged() {
                    contentArea.previousSection = root.currentSection;
                }
            }

            // Panel definitions for Loader
            readonly property var panelComponents: [
                {
                    component: "WifiPanel.qml",
                    section: 0
                },
                {
                    component: "BluetoothPanel.qml",
                    section: 1
                },
                {
                    component: "AudioMixerPanel.qml",
                    section: 2
                },
                {
                    component: "../../config/AiPanel.qml",
                    section: 3
                },
                {
                    component: "ThemePanel.qml",
                    section: 4
                },
                {
                    component: "SystemPanel.qml",
                    section: 5
                },
                {
                    component: "ShellPanel.qml",
                    section: 6
                },
                {
                    component: "KeybindingsPanel.qml",
                    section: 7
                },
                {
                    component: "WindowRulesPanel.qml",
                    section: 8
                },
                {
                    component: "DisplayPanel.qml",
                    section: 9
                }
            ]

            // Lazy-loaded panel using Loader
            Loader {
                id: panelLoader
                objectName: "settings-panel-loader"
                anchors.fill: parent
                asynchronous: true
                source: contentArea.panelComponents[root.currentSection]?.component ?? ""

                // Fade in animation
                opacity: status === Loader.Ready ? 1 : 0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                onLoaded: {
                    if (item) {
                        item.maxContentWidth = contentArea.maxContentWidth;
                        // Apply pending subsection if any
                        if (item.currentSection !== undefined) {
                            item.currentSection = root.pendingSubSection;
                            root.pendingSubSection = "";
                        }
                    }
                }
            }
        }
    }
}
