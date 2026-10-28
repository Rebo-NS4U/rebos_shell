#!/usr/bin/env python3
"""Cache dominant color metadata for wallpaper browsing; emit JSON only."""
import argparse
import colorsys
import json
import os
from pathlib import Path
import tempfile
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageOps

EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.tif', '.tiff', '.bmp', '.gif', '.mp4', '.webm', '.mov', '.avi', '.mkv'}
HUES = ('red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'pink')


def color_info(image):
    image.thumbnail((64, 64))
    pixels = list(image.convert('RGB').get_flattened_data()) if hasattr(image, 'get_flattened_data') else list(image.convert('RGB').getdata())
    buckets = {}
    for r, g, b in pixels:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        hue = h * 360
        if v < .16:
            group = 'black'
        elif s < .16:
            group = 'white' if v > .8 else 'gray'
        else:
            group = ('red' if hue < 15 or hue >= 345 else 'orange' if hue < 45
                     else 'yellow' if hue < 70 else 'green' if hue < 165
                     else 'cyan' if hue < 200 else 'blue' if hue < 260
                     else 'purple' if hue < 290 else 'pink')
        buckets.setdefault(group, []).append((r, g, b))
    chromatic = {k: v for k, v in buckets.items() if k in HUES}
    candidates = chromatic if sum(map(len, chromatic.values())) >= len(pixels) * .25 else buckets
    group = max(candidates, key=lambda k: len(candidates[k]))
    values = candidates[group]
    rgb = tuple(round(sum(p[i] for p in values) / len(values)) for i in range(3))
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    return {'group': group, 'hue': round(h * 360, 2), 'brightness': round(sum(.2126 * r + .7152 * g + .0722 * b for r, g, b in pixels) / (255 * len(pixels)), 4),
            'swatch': '#%02x%02x%02x' % rgb}


def build_index(root, cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / 'wallpaper-color-index.json'
    try:
        cached = json.loads(cache_file.read_text())
        old = cached.get('entries', {}) if cached.get('version') == 2 else {}
    except (OSError, ValueError):
        old = {}
    files = []
    for directory, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        files.extend(Path(directory) / n for n in sorted(names) if Path(n).suffix.lower() in EXTENSIONS)

    def analyze(path):
        key = str(path)
        try:
            stat = path.stat()
            thumb = cache_dir / 'thumbnails' / path.relative_to(root).parent / (path.name + '.jpg')
            source = thumb if thumb.exists() and thumb.stat().st_mtime_ns >= stat.st_mtime_ns else path
            stamp = [stat.st_mtime_ns, stat.st_size, str(source), source.stat().st_mtime_ns]
            if old.get(key, {}).get('stamp') == stamp:
                return key, old[key]
            with Image.open(source) as image:
                image.draft('RGB', (64, 64))
                # RGB conversion composites transparent images onto a dark desktop.
                image.thumbnail((64, 64))
                if 'A' in image.getbands():
                    bg = Image.new('RGB', image.size, '#202020')
                    bg.paste(image, mask=image.getchannel('A'))
                    image = bg
                info = color_info(ImageOps.exif_transpose(image).convert('RGB'))
            return key, dict(info, stamp=stamp)
        except (OSError, ValueError, Image.DecompressionBombError):
            return key, {'group': 'unknown', 'hue': 0, 'brightness': 0, 'swatch': '#808080'}

    with ThreadPoolExecutor(max_workers=2) as pool:
        entries = dict(pool.map(analyze, files))
    # Preserve cached entries belonging to other roots and allow concurrent readers.
    merged = dict(old, **entries)
    fd, name = tempfile.mkstemp(prefix='.wallpaper-colors-', dir=cache_dir)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump({'version': 2, 'entries': merged}, stream)
        os.replace(name, cache_file)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return {key: {k: v for k, v in entry.items() if k != 'stamp'} for key, entry in entries.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=lambda p: Path(p).expanduser().absolute())
    parser.add_argument('--cache-dir', type=Path, default=Path.home() / '.cache/rebos_shell')
    args = parser.parse_args()
    if not args.root.is_dir():
        raise ValueError('Wallpaper folder is unavailable')
    print(json.dumps({'colors': build_index(args.root, args.cache_dir)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        raise SystemExit(1)
