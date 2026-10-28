pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.theme

FocusScope {
    id: root
    required property ShellScreen screen
    readonly property real unit: Styling.fontSize(0)
    property bool dragPeek: false
    readonly property bool open: dragPeek || (FileShelf.visible && FileShelf.screenName === screen.name)
    readonly property Item handleHitbox: visible ? (open ? handle : edgeTrigger) : null
    readonly property Item shelfHitbox: visible && open ? reveal : null
    readonly property Item blurTarget: visible && reveal.visible ? card : null
    visible: !GlobalStates.lockscreenVisible
    Keys.onEscapePressed: FileShelf.close()
    onVisibleChanged: {
        if (!visible) { dragPeek = false; dismissTimer.stop(); }
    }

    // A narrow, unpainted target is needed for Wayland to offer an incoming
    // file drag. Ordinary hovering never reveals or opens the shelf.
    Item {
        id: edgeTrigger
        objectName: "file-shelf-trigger"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.unit * 10
        z: 2
        ShelfDropArea {
            anchors.fill: parent
            screenName: root.screen.name
            onFileEntered: { dismissTimer.stop(); root.dragPeek = true; }
            onFileExited: dismissTimer.restart()
            onFilesDropped: root.dragPeek = false
        }
    }
    Timer {
        id: dismissTimer
        // Allow a drag to cross from the edge handle into the shelf card.
        interval: 200
        onTriggered: root.dragPeek = false
    }

    StyledRect {
        id: handle
        objectName: "file-shelf-handle"
        visible: root.open
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.unit * 1.9
        height: root.unit * 7
        variant: handleDrop.containsDrag || root.open ? "focus" : "popup"
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: Styling.radius(-2)
        bottomRightRadius: Styling.radius(-2)
        border.width: 1
        border.color: Qt.alpha(Colors.primary, handleDrop.containsDrag ? 0.8 : 0.3)
        Column {
            anchors.centerIn: parent
            spacing: root.unit * 0.6
            StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: Icons.folder; font.family: Icons.font; color: Colors.primary }
            StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: FileShelf.count || "+"; font.pixelSize: Styling.fontSize(-2) }
        }
        MouseArea {
            id: handleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Accessible.name: "File shelf"
            onClicked: { FileShelf.toggle(root.screen.name); root.forceActiveFocus(); }
        }
        ShelfDropArea {
            id: handleDrop
            anchors.fill: parent
            screenName: root.screen.name
            onFileEntered: { dismissTimer.stop(); root.dragPeek = true; }
            onFileExited: dismissTimer.restart()
            onFilesDropped: root.dragPeek = false
        }
        StyledToolTip { show: handleMouse.containsMouse && !handleDrop.containsDrag; description: "File shelf · Super+Alt+F\nDrop files here to keep them handy" }
    }

    MotionReveal {
        id: reveal
        objectName: "file-shelf-reveal"
        open: root.open
        horizontal: true
        direction: -1
        x: handle.width + root.unit * 0.6
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(root.unit * 25, root.width - x - root.unit))
        height: Math.max(0, Math.min(root.unit * 36, root.height - root.unit * 6))

        StyledRect {
            id: card
            anchors.fill: parent
            variant: "popup"
            radius: Styling.radius(4)
            border.width: 1
            border.color: Qt.alpha(Colors.primary, shelfDrop.containsDrag ? 0.8 : 0.28)
            ShelfDropArea {
                id: shelfDrop
                anchors.fill: parent
                screenName: root.screen.name
                onFileEntered: { dismissTimer.stop(); root.dragPeek = true; }
                onFileExited: dismissTimer.restart()
                onFilesDropped: root.dragPeek = false
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.unit
                spacing: root.unit * 0.7
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: "File shelf"; font.bold: true; font.pixelSize: Styling.fontSize(3); Layout.fillWidth: true }
                    ShelfAction { objectName: "shelf-clear"; glyph: Icons.trash; description: "Clear shelf · keeps original files"; enabled: FileShelf.count > 0 && !FileShelf.dragging; onClicked: FileShelf.clear() }
                    ShelfAction { objectName: "shelf-close"; glyph: Icons.cancel; description: "Close shelf"; enabled: !FileShelf.dragging; onClicked: FileShelf.close() }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: shelfDrop.containsDrag ? "Release to add files" : "Drop files here, then drag a card into an app."
                    wrapMode: Text.WordWrap
                    color: shelfDrop.containsDrag ? Colors.primary : Colors.overSurfaceVariant
                    font.pixelSize: Styling.fontSize(-1)
                }
                Flickable {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: cards.height
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !FileShelf.dragging
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: cards
                        width: list.width
                        spacing: root.unit * 0.5
                        Repeater {
                            model: FileShelf.files
                            delegate: FileShelfCard {
                                required property string uri
                                required property string name
                                required property string path
                                width: cards.width
                                fileUri: uri
                                fileName: name
                                filePath: path
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - root.unit * 2
                        spacing: root.unit
                        visible: FileShelf.count === 0
                        StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: Icons.folder; font.family: Icons.font; font.pixelSize: Styling.fontSize(25); color: Colors.primary }
                        StyledText { width: parent.width; text: FileShelf.busy ? "Reading files…" : "Your shelf is empty"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                        StyledText { width: parent.width; text: "Drag files or folders onto the left handle."; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Colors.overSurfaceVariant; font.pixelSize: Styling.fontSize(-1) }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: FileShelf.error.length > 0
                    text: FileShelf.error
                    wrapMode: Text.WordWrap
                    color: Colors.error
                    font.pixelSize: Styling.fontSize(-2)
                }
                StyledText {
                    Layout.fillWidth: true
                    text: FileShelf.count + " / " + FileShelf.limit + " · Original files stay in place"
                    color: Colors.overSurfaceVariant
                    font.pixelSize: Styling.fontSize(-2)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
