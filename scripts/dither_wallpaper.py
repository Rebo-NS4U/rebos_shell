#!/usr/bin/env python3
"""Create a cached, full-resolution dithered PNG without changing the source."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import tempfile

VERSION = 3
STRENGTHS = {'normal': (24, 1), 'strong': (6, 2), 'intense': (4, 3)}


def convert(source: Path, cache: Path, palette: str = 'original', strength: str = 'strong',
            tint: str = '#4c9cbd') -> Path:
    from PIL import Image, ImageOps

    if strength not in STRENGTHS:
        raise ValueError('Unknown strength: ' + strength)
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", tint):
        raise ValueError("Main color must be a six-digit hex color, such as #4c9cbd.")
    tint = tint.lower() if palette == "tint" else ""
    color_count, pixel_size = STRENGTHS[strength]
    source = source.expanduser().resolve(strict=True)
    info = source.stat()
    key = hashlib.sha256(json.dumps([str(source), info.st_size, info.st_mtime_ns,
                                    palette, strength, VERSION, tint]).encode()).hexdigest()
    cache = cache.expanduser().resolve()
    cache.mkdir(parents=True, exist_ok=True)
    output = cache / (key + '.png')
    if output.is_file():
        return output
    with Image.open(source) as raw:
        if getattr(raw, 'is_animated', False):
            raise ValueError('Choose a still image; animated wallpapers are kept unchanged.')
        image = ImageOps.exif_transpose(raw).convert('RGB')
    if palette == 'original':
        sample = image.copy()
        sample.thumbnail((512, 512))
        colors = sample.quantize(colors=color_count, method=Image.Quantize.MEDIANCUT)
        # An explicit palette enables error diffusion in the working image;
        # quantize(colors=N) alone does not produce this texture.
        entries = colors.getpalette()[:color_count * 3]
    elif palette == 'tint':
        main = tuple(bytes.fromhex(tint[1:]))
        dark = tuple(round(v * 0.06) for v in main)
        light = tuple(round(240 + v * 15 / 255) for v in main)
        # Map luminance through the chosen main color, preserving shading.
        image = ImageOps.colorize(ImageOps.grayscale(image), dark, light, mid=main)
        ramp = ImageOps.colorize(Image.linear_gradient('L'), dark, light, mid=main)
        entries = [v for i in range(color_count)
                   for v in ramp.getpixel((0, round(i * 255 / (color_count - 1))))]
    elif palette == 'teal-orange':
        palette_colors = ('0b191a', '10363d', '135260', '137788',
                                  '05a3b5', '30cccf', '793f32', 'b3694b',
                                  'e59a72', 'ffd2a5', 'fff0d5', 'd0e7df')
        indices = {'normal': range(12), 'strong': (0, 2, 4, 7, 9, 10),
                   'intense': (0, 3, 8, 10)}[strength]
        entries = [v for index in indices for v in bytes.fromhex(palette_colors[index])]
    else:
        raise ValueError('Unknown palette: ' + palette)
    swatch = Image.new('P', (1, 1))
    # Repeat real entries so unused palette slots cannot introduce black.
    swatch.putpalette((entries * (768 // len(entries) + 1))[:768])
    original_size = image.size
    if pixel_size > 1:
        image = image.resize((max(1, (image.width + pixel_size - 1) // pixel_size),
                              max(1, (image.height + pixel_size - 1) // pixel_size)),
                             Image.Resampling.LANCZOS)
    result = image.quantize(palette=swatch, dither=Image.Dither.FLOYDSTEINBERG)
    if result.size != original_size:
        result = result.resize(original_size, Image.Resampling.NEAREST)
    fd, temporary = tempfile.mkstemp(prefix='.dither-', suffix='.png', dir=cache)
    try:
        with os.fdopen(fd, 'wb') as stream:
            result.save(stream, format='PNG', optimize=True)
        os.replace(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return output


def original_swatches(source: Path) -> list[str]:
    """Sample frequent, distinct colors from the unmodified wallpaper."""
    from PIL import Image, ImageOps
    with Image.open(source.expanduser()) as raw:
        image = ImageOps.exif_transpose(raw).convert('RGB')
        image.thumbnail((192, 192))
    indexed = image.quantize(colors=12, method=Image.Quantize.MEDIANCUT)
    palette = indexed.getpalette()
    colors = []
    for _, index in sorted(indexed.getcolors(), reverse=True):
        rgb = tuple(palette[index * 3:index * 3 + 3])
        if all(sum((a-b)**2 for a,b in zip(rgb, old)) >= 32**2 for old in colors):
            colors.append(rgb)
        if len(colors) == 8:
            break
    return ['#%02x%02x%02x' % rgb for rgb in colors]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--palette', choices=['original', 'teal-orange', 'tint'], default='original')
    parser.add_argument('--swatches', action='store_true')
    parser.add_argument('--tint', default='#4c9cbd')
    parser.add_argument('--strength', choices=list(STRENGTHS), default='strong')
    parser.add_argument('--cache', type=Path, default=Path(os.environ.get(
        'XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'rebos_shell/dithered')
    args = parser.parse_args()
    try:
        if args.swatches:
            print(json.dumps({'colors': original_swatches(args.image)}))
        else:
            print(json.dumps({'path': str(convert(args.image, args.cache, args.palette, args.strength, args.tint))}))
        return 0
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
