// Shared by fills and outlines. Coordinates and cell size are logical pixels,
// so resizing a panel never stretches the texture or changes its dot size.
float ditherMask(vec2 pixel, float cellSize) {
    vec2 cell = floor(pixel / max(cellSize, 0.5));
    return mod(cell.x + cell.y, 2.0);
}
