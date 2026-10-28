pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme

ColumnLayout {
    id: root
    objectName: "monitor-process-details"
    spacing: 8
    property int expandedPpid: -1
    readonly property string metric: SystemResources.detailMetric
    readonly property string gpuDevice: metric.startsWith("gpu:") ? metric.slice(4) : ""

    function value(row): real {
        if (gpuDevice) return row.gpu?.[gpuDevice] ?? 0;
        if (metric === "network") return row.sockets ?? 0;
        return row[metric] ?? 0;
    }
    function formatted(row): string {
        const v = value(row);
        if (metric === "cpu" || gpuDevice) return v.toFixed(1) + "%";
        if (metric === "network") return v + " sockets";
        return (v / 1024 / 1024).toFixed(1) + (metric === "disk" ? " MiB/s" : " MiB");
    }
    readonly property list<var> groups: {
        const rows = SystemResources.processes;
        const byPid = {};
        const byParent = {};
        for (const row of rows) byPid[row.pid] = row;
        for (const row of rows) {
            if (root.gpuDevice && !(root.gpuDevice in (row.gpu ?? {}))) continue;
            if (root.metric === "network" && !row.sockets) continue;
            const key = row.ppid;
            if (!byParent[key]) byParent[key] = {ppid: key, name: byPid[key]?.name ?? "Parent exited / unavailable", children: [], cpu: 0, ram: 0, disk: 0, sockets: 0, gpu: {}};
            const group = byParent[key];
            group.children.push(row);
            for (const metric of ["cpu", "ram", "disk", "sockets"]) group[metric] += row[metric] ?? 0;
            for (const dev of Object.keys(row.gpu ?? {})) group.gpu[dev] = (group.gpu[dev] ?? 0) + row.gpu[dev];
        }
        const result = Object.values(byParent);
        for (const group of result) group.children.sort((a, b) => root.value(b) - root.value(a) || a.pid - b.pid);
        return result.sort((a, b) => root.value(b) - root.value(a) || a.ppid - b.ppid);
    }

    RowLayout {
        Layout.fillWidth: true
        MetricAction { text: "← All stats"; onClicked: SystemResources.detailMetric = "" }
        Item { Layout.fillWidth: true }
        StyledText { text: "Live · by PPID"; font.pixelSize: Styling.fontSize(-3); color: Colors.overSurfaceVariant }
    }
    StyledText {
        Layout.fillWidth: true
        text: SystemResources.detailTitle
        font.bold: true
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        font.pixelSize: Styling.fontSize(-3)
        color: Colors.overSurfaceVariant
        wrapMode: Text.Wrap
        text: root.metric === "network" ? "Sorted by open sockets, including local sockets. Per-process network speeds are unavailable."
            : root.metric === "disk" ? "Read + write activity across all disks; this is not space occupied on the selected disk. Restricted processes may be unavailable."
            : root.gpuDevice ? "GPU engine time reported by the driver. Processes without accessible GPU counters are omitted."
            : root.metric === "cpu" ? "CPU uses 100% per core. Expand a parent to see its direct children."
            : "Resident memory of direct children, including shared pages. Expand a parent to see its processes."
    }
    ListView {
        id: list
        objectName: "monitor-process-list"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(340, Math.max(100, contentHeight))
        clip: true
        spacing: 6
        model: ScriptModel { values: root.groups; objectProp: "ppid" }
        ScrollBar.vertical: ScrollBar { }
        delegate: StyledRect {
            id: groupRow
            required property var modelData
            width: list.width - 12
            implicitHeight: groupColumn.implicitHeight + 16
            variant: "internalbg"
            radius: Styling.radius(2)
            ColumnLayout {
                id: groupColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                Item {
                    Layout.fillWidth: true
                    implicitHeight: groupLabel.implicitHeight
                    StyledText {
                        id: groupLabel
                        width: parent.width
                        font.pixelSize: Styling.fontSize(-2)
                        wrapMode: Text.Wrap
                        text: (root.expandedPpid === groupRow.modelData.ppid ? "▾ " : "▸ ")
                            + groupRow.modelData.name + " · PPID " + groupRow.modelData.ppid
                            + "\n" + groupRow.modelData.children.length + " processes · " + root.formatted(groupRow.modelData)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.expandedPpid = root.expandedPpid === groupRow.modelData.ppid ? -1 : groupRow.modelData.ppid
                    }
                }
                Repeater {
                    model: root.expandedPpid === groupRow.modelData.ppid ? groupRow.modelData.children : []
                    StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        font.pixelSize: Styling.fontSize(-3)
                        wrapMode: Text.Wrap
                        text: modelData.name + " · PID " + modelData.pid + " · " + root.formatted(modelData)
                    }
                }
            }
        }
        StyledText {
            anchors.centerIn: parent
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: list.count === 0
            text: SystemResources.processes.length === 0 ? "Collecting processes…" : "No accessible processes for this stat."
            font.pixelSize: Styling.fontSize(-2)
        }
    }
}
