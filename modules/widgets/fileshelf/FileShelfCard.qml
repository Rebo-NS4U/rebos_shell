pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme

StyledRect {
    id: root
    required property string fileUri
    required property string fileName
    required property string filePath
    required property bool directory
    required property bool preview
    readonly property bool shelfEntry: true
    objectName: "shelf-file-card"
    implicitHeight: Styling.fontSize(0) * 5
    variant: dragHandler.active ? "focus" : "common"
    radius: Styling.radius(-3)
    border.width: activeFocus ? 1 : 0
    border.color: Colors.primary
    Accessible.name: fileName
    Accessible.description: "Drag this file into another app. Removing its card keeps the original file."

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.proposedAction: Qt.CopyAction
    Drag.source: root
    Drag.hotSpot: Qt.point(24, 24)
    Drag.mimeData: ({ "text/uri-list": root.fileUri + "\r\n", "text/plain": root.filePath })
    Drag.onDragFinished: FileShelf.dragging = false

    DragHandler {
        id: dragHandler
        target: null
        enabled: !FileShelf.dragging || active
        onActiveChanged: {
            if (active) {
                FileShelf.dragging = true;
                root.grabToImage(result => {
                    if (!dragHandler.active) { FileShelf.dragging = false; return; }
                    root.Drag.imageSource = result.url;
                    root.Drag.active = true;
                });
            } else {
                root.Drag.active = false;
                FileShelf.dragging = false;
            }
        }
    }
    RowLayout {
        anchors.fill: parent
        anchors.margins: Styling.fontSize(-4)
        spacing: Styling.fontSize(-4)
        Item {
            Layout.preferredWidth: Styling.fontSize(0) * 3
            Layout.preferredHeight: width
            Image {
                id: thumbnail
                anchors.fill: parent
                source: root.preview ? root.fileUri : ""
                sourceSize: Qt.size(96, 96)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            StyledText {
                anchors.centerIn: parent
                visible: !thumbnail.visible
                text: root.directory ? Icons.folder : Icons.file
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(12)
                color: Colors.primary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                text: root.fileName
                textFormat: Text.PlainText
                font.bold: true
                elide: Text.ElideMiddle
            }
            StyledText {
                Layout.fillWidth: true
                text: root.directory ? "Folder" : root.filePath.substring(0, root.filePath.lastIndexOf("/")) || "/"
                textFormat: Text.PlainText
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                elide: Text.ElideMiddle
            }
        }
        ShelfAction {
            objectName: "shelf-remove"
            glyph: Icons.cancel
            description: "Remove from shelf"
            enabled: !FileShelf.dragging
            onClicked: FileShelf.remove(root.fileUri)
        }
    }
}
