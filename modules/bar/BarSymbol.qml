pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.components
import qs.modules.theme

// Center the drawn glyph, rather than the font's asymmetric line box.
Item {
    id: root
    property string symbol: ""
    property real size: 18
    property color color: BarAppearance.foregroundColor
    implicitWidth: size
    implicitHeight: size

    FontMetrics {
        id: metrics
        font: glyph.font
    }
    readonly property rect inkBounds: metrics.tightBoundingRect(symbol)

    StyledText {
        id: glyph
        text: root.symbol
        font.family: Icons.font
        font.pixelSize: root.size
        color: root.color
        x: (root.width - root.inkBounds.width) / 2 - root.inkBounds.x
        y: (root.height - root.inkBounds.height) / 2 - root.inkBounds.y - baselineOffset
    }
}
