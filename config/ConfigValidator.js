.pragma library

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

function validate(current, defaults, keyName) {
    if (current === undefined || current === null) {
        return clone(defaults);
    }

    if (Array.isArray(defaults)) {
        if (!Array.isArray(current)) {
            return clone(defaults);
        }
        return current;
    }

    if (typeof defaults === 'object') {
        if (typeof current !== 'object' || Array.isArray(current)) {
            return clone(defaults);
        }

        const result = {};
        for (const key in defaults) {
            result[key] = validate(current[key], defaults[key], key);
        }
        return result;
    }

    if (typeof current !== typeof defaults) {
        return defaults;
    }

    if (keyName === "shellStyle" && ["glass", "quiet", "colorful", "dithered", "custom"].indexOf(current) === -1) {
        return defaults;
    }
    if (keyName === "desktopBlur" && ["medium", "light", "shell", "off"].indexOf(current) === -1) return defaults;
    if (keyName === "ditherPalette" && ["original", "teal-orange", "tint"].indexOf(current) === -1) return defaults;
    if (keyName === "ditherTintColor") return /^#[0-9a-f]{6}$/i.test(current) ? current.toLowerCase() : defaults;
    if (keyName === "ditherBorder" && ["band", "dotted", "double"].indexOf(current) === -1) return defaults;
    if (keyName === "wallpaperDitherStrength" && ["normal", "strong", "intense"].indexOf(current) === -1) return defaults;
    if (keyName === "ditherStrength") {
        return Number.isFinite(current) ? Math.round(Math.max(0, Math.min(100, current))) : defaults;
    }

    if (keyName === "islandAppearance" && ["glass", "classic"].indexOf(current) === -1) {
        return defaults;
    }
    if (keyName === "islandOpacity" || keyName === "islandAccent") {
        if (!Number.isFinite(current)) return defaults;
        return Math.round(Math.max(keyName === "islandOpacity" ? 20 : 0, Math.min(100, current)));
    }

    if (keyName === "gradientType") {
        const validTypes = ["linear", "radial", "halftone"];
        if (validTypes.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "position") {
        const validPositions = ["top", "bottom"];
        if (validPositions.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "style") {
        const validStyles = ["default", "island"];
        if (validStyles.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "sidebarPosition") {
        const validSidebarPositions = ["left", "right"];
        if (validSidebarPositions.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "unit") {
        const validUnits = ["C", "F"];
        if (validUnits.indexOf(current) === -1) {
            return defaults;
        }
    }

    return current;
}
