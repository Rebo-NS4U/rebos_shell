pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme
import qs.config

// Compact scrollable meter used by the permanent bar controls.  Its arc
// deliberately matches BatteryIndicator's speedometer geometry.
Item {
    id: root

    required property Item bar
    property bool layerEnabled: false
    property bool flat: false
    readonly property color trackColor: flat ? Styling.withOpacity(Colors.overSurface, 0.14) : Colors.outlineVariant
    property int meterSize: 36

    property real startRadius: Styling.radius(0)
    property real endRadius: Styling.radius(0)
    property real value: 0
    property string icon: ""
    property color progressColor: Styling.srItem("overprimary")
    property string tooltipText: ""
    property string tooltipDescription: ""
    property bool clickEnabled: true
    property bool isHovered: false

    signal adjusted(real value)
    signal activated
    signal secondaryActivated

    readonly property real normalizedValue: Math.max(0, Math.min(1, value))

    Layout.preferredWidth: meterSize
    Layout.preferredHeight: meterSize
    Layout.fillHeight: !flat
    Layout.alignment: Qt.AlignVCenter

    implicitWidth: meterSize
    implicitHeight: meterSize

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        anchors.fill: parent
        variant: root.flat ? "transparent" : "bg"
        enableShadow: !root.flat && root.layerEnabled
        enableBorder: !root.flat
        topLeftRadius: root.flat ? (root.meterSize / 2) : root.startRadius
        topRightRadius: root.flat ? (root.meterSize / 2) : root.endRadius
        bottomLeftRadius: root.flat ? (root.meterSize / 2) : root.startRadius
        bottomRightRadius: root.flat ? (root.meterSize / 2) : root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.isHovered ? (root.flat ? 0.12 : 0.2) : 0
            radius: root.flat ? (width / 2) : buttonBg.topLeftRadius
            topLeftRadius: root.flat ? (width / 2) : buttonBg.topLeftRadius
            topRightRadius: root.flat ? (width / 2) : buttonBg.topRightRadius
            bottomLeftRadius: root.flat ? (width / 2) : buttonBg.bottomLeftRadius
            bottomRightRadius: root.flat ? (width / 2) : buttonBg.bottomRightRadius

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration / 2 }
            }
        }

        Item {
            id: progressMeter
            anchors.centerIn: parent
            width: root.flat ? (root.meterSize - 2) : 32
            height: width

            property real angle: root.normalizedValue * (360 - 2 * gapAngle)
            property real meterRadius: root.flat ? (root.meterSize / 2 - 4.5) : 12
            property real lineWidth: root.flat ? 2.2 : 3
            property real gapAngle: 45

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const centerX = width / 2;
                    const centerY = height / 2;
                    const start = Math.PI / 2 + progressMeter.gapAngle * Math.PI / 180;
                    const total = (360 - 2 * progressMeter.gapAngle) * Math.PI / 180;
                    const progress = progressMeter.angle * Math.PI / 180;

                    ctx.lineCap = "round";
                    ctx.lineWidth = progressMeter.lineWidth;
                    ctx.strokeStyle = root.trackColor;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, progressMeter.meterRadius, start + progress, start + total, false);
                    ctx.stroke();

                    if (progressMeter.angle > 0) {
                        ctx.strokeStyle = root.progressColor;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, progressMeter.meterRadius, start, start + progress, false);
                        ctx.stroke();
                    }
                }

                Connections {
                    target: progressMeter
                    function onAngleChanged() { canvas.requestPaint(); }
                }

                Connections {
                    target: root
                    function onTrackColorChanged() { canvas.requestPaint(); }
                    function onProgressColorChanged() { canvas.requestPaint(); }
                }
            }

            Behavior on angle {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Math.min(Config.animDuration, 160)
                    easing.type: Easing.OutCubic
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            text: root.icon
            font.family: Icons.font
            font.pixelSize: root.flat ? 11 : 14
            color: Colors.overBackground
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: root.clickEnabled ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
            cursorShape: root.clickEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    root.secondaryActivated();
                } else {
                    root.activated();
                }
            }

        }

        ScrollStepHandler {
            onStepped: steps => root.adjusted(Math.max(0, Math.min(1, root.normalizedValue + steps * 0.05)))
        }

        StyledToolTip {
            show: root.isHovered
            tooltipText: root.tooltipText
            description: root.tooltipDescription
        }
    }
}
