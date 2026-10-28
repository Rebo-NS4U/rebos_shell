import QtQuick
import Quickshell
import qs.config

QtObject {
    id: root

    function generate(colors: var): void {
        if (!colors)
            return;
        const palette = {};
        for (const name of colors.availableColorNames)
            palette[name] = colors[name].toString();
        palette.opacity = colors.opacity;
        palette.style = colors.style;
        writer.submit(["python3", Quickshell.shellPath("scripts/apply_desktop_palette.py"), JSON.stringify(palette)]);
    }

    property ThemeWriter writer: ThemeWriter {}
}
