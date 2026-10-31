.pragma library

var styles = [
    {id: "glass", label: "Transparent", description: "Dark transparent backgrounds with light wallpaper colors."},
    {id: "quiet", label: "Opaque", description: "Solid backgrounds with less wallpaper color."},
    {id: "colorful", label: "Tinted", description: "Transparent backgrounds with more wallpaper color."},
    {id: "dithered", label: "Dithered", description: "Dithered wallpapers, fine shell texture and matching app colors."},
    {id: "custom", label: "Custom", description: "Use your saved background and border settings."}
];

function mix(a, b, amount) {
    function rgb(hex) {
        var value = hex.replace("#", "");
        if (value.length === 8) value = value.slice(2);
        return [parseInt(value.slice(0,2),16), parseInt(value.slice(2,4),16), parseInt(value.slice(4,6),16)];
    }
    var x = rgb(a), y = rgb(b);
    return "#" + x.map(function(channel, i) {
        return Math.round(channel * (1 - amount) + y[i] * amount).toString(16).padStart(2, "0");
    }).join("");
}

function contrast(a, b) {
    function luminance(hex) {
        var channels = hex.slice(-6).match(/../g).map(function(c) {
            var v = parseInt(c, 16) / 255;
            return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }
    var x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

function dotColor(fill, text, amount) {
    // Texture must stay readable even on bright accent buttons and light themes.
    for (var i = 0; i < 12; i++) {
        var color = mix(fill, text, amount);
        if (contrast(color, text) >= 4.5) return color;
        amount *= 0.75;
    }
    return fill;
}

// Every surface uses one hierarchy, with the wallpaper palette supplying all color.
function ditherCellSize(strength) {
    var value = Number.isFinite(strength) ? Math.max(0, Math.min(100, strength)) : 20;
    // A fine shared grid stays restrained even at higher strengths.
    return 1 + value * 0.02;
}

function surface(style, variant, p, ditherStrength) {
    var strength = Number.isFinite(ditherStrength) ? Math.max(0, Math.min(100, ditherStrength)) : 20;
    var colorful = style === "colorful", dithered = style === "dithered", quiet = style === "quiet" || dithered;
    var tint = colorful ? 0.10 : (quiet ? 0.015 : 0.035);
    var base = mix(p.background, p.foreground, dithered ? 0.025 : 0.035);
    var fill = mix(base, p.primary, tint), item = p.foreground;
    var opacity = quiet ? 1 : 0.92;
    var border = [mix(base, p.primary, dithered ? 0.24 : (colorful ? 0.32 : 0.18)), 0];
    switch (variant) {
    case "transparent": opacity = 0; break;
    case "barbg": opacity = dithered && strength > 0 ? 1 : 0; break;
    case "bg":
        opacity = quiet ? 1 : (colorful ? 0.82 : 0.86);
        border[1] = 1; break;
    case "popup":
        opacity = quiet ? 1 : 0.94;
        border[1] = 1; break;
    case "bar": case "pane": case "surface": case "surfaceContainer":
        fill = mix(base, p.primary, tint + (dithered ? 0.045 : 0.02));
        opacity = quiet ? 1 : 0.90; break;
    case "internalbg":
        fill = mix(p.background, p.primary, tint * 0.6);
        opacity = quiet ? 1 : 0.72; break;
    case "focus": case "surfaceVariant":
        fill = mix(base, p.primary, colorful ? 0.28 : (dithered ? 0.14 : (quiet ? 0.10 : 0.16)));
        border[1] = 1; break;
    case "primary": case "primaryfocus":
        fill = variant === "primaryfocus" ? mix(p.primary, p.foreground, 0.12) : p.primary;
        item = p.onPrimary; opacity = 1; break;
    case "overprimary": fill = base; item = p.primary; break;
    case "secondary": case "secondaryfocus": fill = p.secondary; item = p.onSecondary; opacity = 1; break;
    case "oversecondary": item = p.secondary; break;
    case "tertiary": case "tertiaryfocus": fill = p.tertiary; item = p.onTertiary; opacity = 1; break;
    case "overtertiary": item = p.tertiary; break;
    case "error": case "errorfocus": fill = p.error; item = p.onError; opacity = 1; break;
    case "overerror": item = p.error; break;
    }
    var containers = ["bg", "popup", "pane", "surface", "surfaceContainer", "common", "internalbg", "focus", "surfaceVariant", "bar", "barbg"];
    var controls = ["primary", "primaryfocus", "overprimary", "secondary", "secondaryfocus", "oversecondary", "tertiary", "tertiaryfocus", "overtertiary", "error", "errorfocus", "overerror"];
    var dotted = dithered && strength > 0 && (containers.indexOf(variant) !== -1 ||
        (strength > 20 && controls.indexOf(variant) !== -1));
    // Strength increases the shared grain scale and contrast smoothly; zero
    // disables texture. Keep text and selected controls clearly legible.
    var dotMax = ditherCellSize(strength);
    // Inner dividers recede; outer edges and focused controls retain definition.
    if (dithered && ["pane", "surface", "surfaceContainer", "common", "internalbg"].indexOf(variant) !== -1)
        border[0] = mix(fill, p.primary, 0.12);
    if (dotted && containers.indexOf(variant) !== -1) border[1] = 1;
    return {
        gradient: [[fill, 0]], gradientType: dotted ? "halftone" : "linear", gradientAngle: 0,
        gradientCenterX: 0.5, gradientCenterY: 0.5,
        halftoneDotMin: dotted ? dotMax : 0, halftoneDotMax: dotted ? dotMax : 0, halftoneStart: 0, halftoneEnd: 1,
        halftoneDotColor: dotted ? dotColor(fill, item, strength * 0.001) : fill, halftoneBackgroundColor: fill,
        border: border, itemColor: item, opacity: opacity
    };
}

// Export the same surface hierarchy to native and themed applications.
function appPalette(style, palette, customOpacity) {
    var result = Object.assign({}, palette);
    result.style = style;
    result.opacity = customOpacity;
    if (style === "custom") return result;
    var roles = {background: palette.background.toString(), foreground: palette.overBackground.toString(),
        primary: palette.primary.toString(), onPrimary: palette.overPrimary.toString(),
        secondary: palette.secondary.toString(), onSecondary: palette.overSecondary.toString(),
        tertiary: palette.tertiary.toString(), onTertiary: palette.overTertiary.toString(),
        error: palette.error.toString(), onError: palette.overError.toString()};
    result.background = surface(style, "bg", roles).gradient[0][0];
    result.surface = result.surfaceContainer = surface(style, "pane", roles).gradient[0][0];
    result.surfaceContainerHigh = surface(style, "focus", roles).gradient[0][0];
    result.surfaceContainerLowest = surface(style, "internalbg", roles).gradient[0][0];
    result.surfaceContainerLow = result.surfaceContainer;
    result.surfaceContainerHighest = result.surfaceContainerHigh;
    result.surfaceVariant = result.surfaceContainerHigh;
    result.surfaceDim = result.surfaceContainerLowest;
    result.surfaceBright = result.surfaceContainerHigh;
    result.outlineVariant = surface(style, "bg", roles).border[0];
    result.opacity = surface(style, "bg", roles).opacity;
    return result;
}
