.pragma library

function arrange(paths, colors, group, order) {
    const result = paths.filter(path => group === "all" || (colors[path]?.group ?? "unknown") === group);
    if (order === "name")
        return result.sort((a, b) => a.split("/").pop().localeCompare(b.split("/").pop()) || a.localeCompare(b));
    const groups = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "white", "gray", "black", "unknown"];
    return result.sort((a, b) => {
        const ca = colors[a], cb = colors[b];
        if (!ca || ca.group === "unknown") return (!cb || cb.group === "unknown") ? a.localeCompare(b) : 1;
        if (!cb || cb.group === "unknown") return -1;
        if (order === "dark" || order === "light")
            return (ca.brightness - cb.brightness) * (order === "dark" ? 1 : -1) || a.localeCompare(b);
        return groups.indexOf(ca.group) - groups.indexOf(cb.group)
            || ca.hue - cb.hue || ca.brightness - cb.brightness || a.localeCompare(b);
    });
}
