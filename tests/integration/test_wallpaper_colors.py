"""Exercise actual color extraction, cache invalidation and unsupported files."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('wallpaper_colors', ROOT / 'scripts/wallpaper_color_index.py')
colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(colors)


class WallpaperColorsTest(unittest.TestCase):
    def test_color_families_and_neutrals(self):
        for name, rgb in {'red': '#e02020', 'orange': '#ee8811', 'yellow': '#dddd11',
                          'green': '#22bb44', 'cyan': '#22bbbb', 'blue': '#2244dd',
                          'purple': '#9922dd', 'pink': '#dd2288', 'white': '#eeeeee',
                          'gray': '#777777', 'black': '#111111'}.items():
            with self.subTest(name=name):
                self.assertEqual(colors.color_info(Image.new('RGB', (64, 64), rgb))['group'], name)

    def test_colorful_subject_on_dark_background(self):
        image = Image.new('RGB', (64, 64), 'black')
        image.paste('#2244dd', (0, 0, 32, 64))
        self.assertEqual(colors.color_info(image)['group'], 'blue')

    def test_index_cache_and_changed_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'walls'
            root.mkdir()
            cache = Path(directory) / 'cache'
            image = root / 'wall.png'
            Image.new('RGB', (64, 64), 'red').save(image)
            (root / 'broken.jpg').write_bytes(b'broken')
            (root / 'video.mp4').write_bytes(b'video')
            first = colors.build_index(root, cache)
            self.assertEqual(first[str(image)]['group'], 'red')
            self.assertEqual(first[str(root / 'broken.jpg')]['group'], 'unknown')
            self.assertEqual(first[str(root / 'video.mp4')]['group'], 'unknown')
            self.assertEqual(colors.build_index(root, cache), first)
            Image.new('RGB', (64, 64), 'blue').save(image)
            self.assertEqual(colors.build_index(root, cache)[str(image)]['group'], 'blue')
            self.assertEqual(json.loads((cache / 'wallpaper-color-index.json').read_text())['version'], 2)


if __name__ == '__main__':
    unittest.main()
