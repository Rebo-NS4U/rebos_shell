import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors)
            return;
        const fmt = c => c.toString();

        const cursor = fmt(Colors.overSurface);
        const cursorText = fmt(Colors.background);

        const foreground = fmt(Colors.overSurface);
        const background = fmt(Colors.background);
        const selectionForeground = fmt(Colors.overPrimary);
        const selectionBackground = fmt(Colors.primary);
        const urlColor = fmt(Colors.primary);
        const backgroundOpacity = Colors.opacity;

        // black
        const color0 = fmt(Colors.surfaceContainerLow);
        const color8 = fmt(Colors.outline);

        // red
        const color1 = fmt(Colors.red);
        const color9 = fmt(Colors.lightRed);

        // green
        const color2 = fmt(Colors.green);
        const color10 = fmt(Colors.lightGreen);

        // yellow
        const color3 = fmt(Colors.yellow);
        const color11 = fmt(Colors.lightYellow);

        // blue
        // User requested primary for color4
        const color4 = fmt(Colors.primary);
        const color12 = fmt(Colors.lightBlue);

        // magenta
        const color5 = fmt(Colors.magenta);
        const color13 = fmt(Colors.lightMagenta);

        // cyan
        const color6 = fmt(Colors.cyan);
        const color14 = fmt(Colors.lightCyan);

        // white
        const color7 = fmt(Colors.overSurfaceVariant);
        const color15 = fmt(Colors.overSurface);

        let conf = "";
        conf += `cursor ${cursor}\n`;
        conf += `cursor_text_color ${cursorText}\n\n`;

        conf += `foreground ${foreground}\n`;
        conf += `background ${background}\n`;
        conf += `background_opacity ${backgroundOpacity}\n`;
        conf += `selection_foreground ${selectionForeground}\n`;
        conf += `selection_background ${selectionBackground}\n`;
        conf += `url_color ${urlColor}\n\n`;

        conf += `active_border_color ${fmt(Colors.primary)}\n`;
        conf += `inactive_border_color ${fmt(Colors.outlineVariant)}\n`;
        conf += `bell_border_color ${fmt(Colors.error)}\n`;
        conf += `tab_bar_background ${background}\n`;
        conf += `tab_bar_margin_color ${background}\n`;
        conf += `active_tab_background ${fmt(Colors.primary)}\n`;
        conf += `active_tab_foreground ${fmt(Colors.overPrimary)}\n`;
        conf += `inactive_tab_background ${fmt(Colors.surface)}\n`;
        conf += `inactive_tab_foreground ${fmt(Colors.overSurfaceVariant)}\n`;
        conf += `mark1_background ${fmt(Colors.primary)}\n`;
        conf += `mark1_foreground ${fmt(Colors.overPrimary)}\n`;
        conf += `mark2_background ${fmt(Colors.secondary)}\n`;
        conf += `mark2_foreground ${fmt(Colors.overSecondary)}\n`;
        conf += `mark3_background ${fmt(Colors.tertiary)}\n`;
        conf += `mark3_foreground ${fmt(Colors.overTertiary)}\n\n`;

        conf += `# black\n`;
        conf += `color0 ${color0}\n`;
        conf += `color8 ${color8}\n\n`;

        conf += `# red\n`;
        conf += `color1 ${color1}\n`;
        conf += `color9 ${color9}\n\n`;

        conf += `# green\n`;
        conf += `color2 ${color2}\n`;
        conf += `color10 ${color10}\n\n`;

        conf += `# yellow\n`;
        conf += `color3 ${color3}\n`;
        conf += `color11 ${color11}\n\n`;

        conf += `# blue\n`;
        conf += `color4 ${color4}\n`;
        conf += `color12 ${color12}\n\n`;

        conf += `# magenta\n`;
        conf += `color5 ${color5}\n`;
        conf += `color13 ${color13}\n\n`;

        conf += `# cyan\n`;
        conf += `color6 ${color6}\n`;
        conf += `color14 ${color14}\n\n`;

        conf += `# white\n`;
        conf += `color7 ${color7}\n`;
        conf += `color15 ${color15}\n`;

        const kittyConfPath = Quickshell.env("HOME") + "/.cache/rebos_shell/kitty.conf";

        // Ensure directory exists and write file
        const cmd = `
            mkdir -p "$(dirname "${kittyConfPath}")" && \\
            echo "${conf}" > "${kittyConfPath}" && \\
            pkill -SIGUSR1 -x kitty || true
        `;

        writerProcess.submit(["sh", "-c", cmd]);
    }

    property ThemeWriter writerProcess: ThemeWriter {}
}
