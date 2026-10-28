.pragma library

function parentDirectory(path) {
    return path.substring(0, path.lastIndexOf("/"));
}

function groups(paths, baseDirectory) {
    const base = baseDirectory.replace(/\/+$/, "");
    const counts = new Map();
    for (const path of paths) {
        const directory = parentDirectory(path);
        counts.set(directory, (counts.get(directory) || 0) + 1);
    }
    const names = Array.from(counts.keys()).map(directory => directory.split("/").pop());
    const folders = Array.from(counts.keys()).map(directory => {
        const name = directory.split("/").pop();
        const relative = directory.startsWith(base + "/") ? directory.substring(base.length + 1) : directory;
        const label = directory === base ? "Loose wallpapers"
            : (names.filter(item => item === name).length > 1 ? relative : name);
        return { id: directory, label: label, count: counts.get(directory),
                 display: label + " (" + counts.get(directory) + ")" };
    }).sort((a, b) => {
        if (a.id === base) return -1;
        if (b.id === base) return 1;
        return a.label.localeCompare(b.label);
    });
    return [{ id: "*", label: "All wallpapers", count: paths.length,
              display: "All wallpapers (" + paths.length + ")" }].concat(folders);
}

function filter(paths, folder, query) {
    const search = query.trim().toLowerCase();
    return paths.filter(path => (folder === "*" || parentDirectory(path) === folder)
        && path.split("/").pop().toLowerCase().includes(search));
}
