# Dithered desktop style

Select **Settings → Appearance → Theme style → Dithered**. Choose **Keep photo
colors** or **Teal and orange** below the style cards. The gallery, wallpaper
shortcuts, CLI selection and individual monitor wallpapers all use the same
conversion service. Changing to another theme restores the original wallpaper.

**Border style** offers **Dithered edge** (active default), **Round dots** and
**Double line**. Dithered edge uses one uniform logical-pixel width across all
panels: `Styling.ditherEdgeWidth = max(1, round(ditherCellSize * 1.5))`.
A quiet base keeps the width visually continuous, with repeating light/dark
pixel marks following the perimeter instead of scattered grain. Corner arcs use
the same spacing as straight edges. Native focus widths are cleared beneath the
shared-width overlay so they cannot leave thicker strips. Pixels use the shared
shell cell size, and gaps preserve the exact panel fill texture. Rounded corners,
focus colors and text/input behavior are preserved. This replaces the rejected
double-line trial as the active style.
Double line draws two fine antialiased outlines with a quieter inner line and
a gap derived from the shared shell cell size. Both remain inside the existing
panel bounds. Round dots retains the previous perimeter-based style.
**Wallpaper conversion** separately offers **Normal** (24 photo colors, original
pixel size), **Strong** (active default: 6 colors, 2×2 dither pixels), and
**Intense** (4 colors, 3×3 dither pixels). Changing it regenerates the current
wallpaper and matching palette without changing the shell strength slider.

The balanced preset uses opaque, palette-derived surfaces with a shared 3px
dither pattern, stronger accent borders and the existing fonts and motion.
Text, icons and accent buttons stay crisp. Existing theme exporters send its
matching background, surface, accent and border colors to GTK, Qt/KDE, Kitty,
Fish/fzf, Neovim, Zen, Spotify, VS Code, Sioyek and the other supported targets.
App support/reload limitations remain the same as the other presets; a matching
color export does not add dithering to app content or web pages.

**Shell dithering** in the same Appearance card controls shell texture strength
from 0–100%. The default **20%** uses a subtle 3px repeat. Higher
values increase dot contrast and spacing (up to 9px) and extend halftone texture
to accent buttons and selected controls. Zero removes shell texture. Text/icon
rendering and wallpaper conversion are independent of this slider. Dot colors
are limited to preserve at least 4.5:1 contrast with the surface's text color
when the underlying palette already provides that contrast. Strength saves
through reactive `theme.ditherStrength` and updates the shell immediately.

The island and default bars, expanded panels, menus, controls and outlines all
use one shared scale. `ShellStyles.ditherCellSize` defines one cell
size in logical pixels, passed through Styling to both shaders. Fill shaders use
the shared `dither_pattern.glsl` mask; panel dimensions never stretch it.
Round-dot outlines place antialiased circular dots along the rounded perimeter, with dot
diameter from that same cell size. The dot count is rounded to close the loop
with even gaps, avoiding checker fragments at corners and an uneven seam.
The outline band grows inward only as much as needed to fit the dots, honoring
wider focus borders. At 20%, each cell is 1.5 logical
pixels and the repeat is 3px. Bar contrast is stronger to remain visible, without
changing the pattern size. Wallpaper diffusion remains a separate image effect.
Shared shell containers receive
dotted outlines. The outline shader paints an antialiased stippled
ring above the native solid border, respecting per-corner radii, border widths
and selected/focus colors. It has no input handlers and does not capture text.
Disabled borders, strength zero and other styles keep their native behavior.
App window borders remain managed by Niri and are unaffected by this shader.

Shader sources and compiled bundles: `modules/components/dotted_outline.*`,
`dither_uniform_edge.*` and `outline_position.glsl` for the uniform textured band,
`double_outline.frag` (uses the dotted-outline vertex shader),
`dither_fill.*`, and the shared `dither_pattern.glsl`. Custom halftone gradients
retain their saved settings and existing renderer.
Rebuild each with Qt's `qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 -o OUTPUT INPUT`.

## Wallpaper processing

`scripts/dither_wallpaper.py IMAGE [--palette original|teal-orange] [--strength normal|strong|intense]` prints JSON
with the converted path, or a structured error and a failing exit status. Uses
Pillow (already needed by the wallpaper indexer). No website or upload needed.
The default samples six colors, applies explicit Floyd–Steinberg quantization
at half the EXIF-oriented source resolution, then expands with nearest-neighbor
sampling to preserve visible 2×2 grain. All modes output the original oriented
dimensions. PNG preserves the resulting texture without JPEG artifacts.

Copies live in `$XDG_CACHE_HOME/rebos_shell/dithered` (default `~/.cache/…`),
keyed by source path, size, nanosecond timestamp, palette, strength and converter version.
Writes are atomic and do not modify originals. Cache copies may be removed when
the shell is stopped; selecting the wallpaper again regenerates them. Videos,
GIFs and unsupported files stay unchanged; animated WebP/PNG files fail safely
back to the original with an error in Appearance.

`DitheredWallpapers.qml` serializes and deduplicates queued requests, keys results
by palette, strength and original path, and exposes only current-style results. The
wallpaper manager uses the converted image for display and static lockscreen
fallback. Matugen waits for the current conversion and uses the adjusted image,
so shell and supported app accents follow the tint and dither palette. Other styles
restore the original color source; videos keep their thumbnail source. Saved gallery
selection and per-monitor paths remain originals.

IPC: `qs ipc call rebos_shell themeStyle dithered`; `themeStatus` reports current
style, source/rendered wallpaper, conversion state and error. Style writes use
the reactive Config adapter. No manual shell/compositor restart is needed.

## Validation

- `python3 -m unittest discover -s tests/integration -p test_dither_wallpaper.py`
- `python3 -m unittest discover -s tests/integration -p test_shell_style.py`
- `python3 -m unittest discover -s tests/integration -p test_unified_app_theme.py`
- `node tests/schema/test_shell_style_schema.js`
- With graphics access: `REBOS_GPU_RENDER_TEST=1 python3 -m unittest discover -s tests/integration -p test_dotted_outline_render.py` uses an invisible OpenGL window and checks actual shader pixels for circular dots, gaps, square/rounded corners and an untouched center.

These exercise real image conversion/cache/error behavior, the real QML async
service (queue, stale palette results, restore and failure), Settings selection
and persistence, app-file generation and both dark/light text contrast.

## Main color tint

Appearance → Dithered → wallpaper palette → Main color offers a native color picker and six-digit hex input. `theme.ditherTintColor` saves the chosen color (default `#4c9cbd`); `theme.ditherPalette: "tint"` enables it. Luminance maps through dark, main-color and pale highlight shades before Floyd–Steinberg dithering at the selected wallpaper strength. Original files remain unchanged. Color-specific cache/queue keys prevent outdated conversions replacing newer selections; the shared wallpaper service updates per-screen images and lockscreen sources. Theme colors follow the adjusted image. Tint swatches sample up to eight frequent, distinct colors from that original, refresh when it changes, and apply on click. Custom picker and hex entry remain available.

### Color samples and hover hints

`StyledRect.fillColor` paints an explicit color sample without surface fill shaders. Wallpaper tint swatches, selected tint preview and theme palette samples use it at full opacity; regular themed surfaces keep their texture. All four former attached native tooltip sites (wallpaper swatches, palette samples, shortcut source rows and wallpaper folder selector) use `StyledToolTip` to follow shell colors.

Verification includes real pointer hover and GPU/RHI pixel checks for the exact swatch RGB and dark tooltip background in `test_shell_style.py`. Software-only Qt rendering cannot paint Quickshell clipping rectangles/shaders accurately, so pixel assertions run with `QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl` and graphics access.
