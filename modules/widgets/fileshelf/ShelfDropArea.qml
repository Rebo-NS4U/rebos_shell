pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services

DropArea {
    id: root
    required property string screenName
    signal fileEntered
    signal fileExited
    signal filesDropped

    function accepts(event): bool {
        return !event.source?.shelfEntry && (event.supportedActions & Qt.CopyAction) !== 0
            && event.hasUrls && event.urls.some(uri => uri.toString().startsWith("file:"));
    }
    onEntered: event => {
        event.accepted = accepts(event);
        if (event.accepted) {
            event.accept(Qt.CopyAction);
            root.fileEntered();
        }
    }
    onExited: root.fileExited()
    onDropped: event => {
        if (!accepts(event)) { event.accepted = false; return; }
        FileShelf.addUrls(event.urls.map(uri => uri.toString()));
        event.accept(Qt.CopyAction);
        root.filesDropped();
    }
}
