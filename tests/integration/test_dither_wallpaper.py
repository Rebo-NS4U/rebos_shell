"""Real image conversion and asynchronous QML service boundaries."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dither', ROOT / 'scripts/dither_wallpaper.py')
dither = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dither)


class ConversionTest(unittest.TestCase):
    def test_strength_controls_colors_grain_and_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'gradient.png'
            image = Image.new('RGB', (240, 120))
            image.putdata([(x, y*2, (x+y)%256) for y in range(120) for x in range(240)])
            image.save(source)
            before = source.read_bytes()
            outputs = []
            for strength, count in [('normal',24), ('strong',6), ('intense',4)]:
                output = dither.convert(source, root/'cache', strength=strength)
                outputs.append(output)
                with Image.open(output) as result:
                    self.assertEqual(result.size,image.size)
                    self.assertLessEqual(len(result.convert('RGB').getcolors()),count)
                    if strength == 'strong':
                        for x in range(0,240,2):
                            for y in range(0,120,2):
                                self.assertEqual(result.getpixel((x,y)),result.getpixel((x+1,y)))
                                self.assertEqual(result.getpixel((x,y)),result.getpixel((x,y+1)))
            self.assertEqual(len(set(outputs)),3)
            self.assertEqual(source.read_bytes(),before)

    def test_size_palette_texture_cache_and_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'photo with spaces.png'
            image = Image.new('RGB', (256, 96))
            image.putdata([(x, (x + y) % 256, y * 2) for y in range(96) for x in range(256)])
            image.save(source)
            before = hashlib.sha256(source.read_bytes()).digest()
            output = dither.convert(source, root / 'cache')
            timestamp = output.stat().st_mtime_ns
            with Image.open(output) as result:
                self.assertEqual(result.size, image.size)
                self.assertLessEqual(len(result.convert('RGB').getcolors()), 12)
                # Compare against nearest-color mapping with the exact palette:
                # the result must actually diffuse error, not just posterize.
                plain = image.quantize(palette=result, dither=Image.Dither.NONE)
                self.assertNotEqual(plain.tobytes(), result.tobytes())
            self.assertEqual(dither.convert(source, root / 'cache'), output)
            self.assertEqual(output.stat().st_mtime_ns, timestamp)
            self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), before)
            self.assertNotEqual(dither.convert(source, root / 'cache', 'teal-orange'), output)
            Image.new('RGB', (100, 70), 'red').save(source)
            self.assertNotEqual(dither.convert(source, root / 'cache'), output)

    @unittest.skipUnless(shutil.which('node'), 'Node is required')
    def test_theme_waits_for_current_tint_and_restores_original(self):
        import re
        source=(ROOT/'modules/widgets/dashboard/wallpapers/Wallpaper.qml').read_text()
        functions=''
        for name, args in [('getColorSource','filePath'),('runMatugenForCurrentWallpaper','')]:
            body=re.search(r'    function '+name+r'\('+args+r'\) \{(.*?)\n    \}',source,re.S).group(1)
            functions+='function '+name+'('+args+') {'+body+'}\n'
        script="""const assert=require('assert');
let pending=true, enabled=true, failed=false, requests=0;
const DitheredWallpapers={waiting:()=>pending, request:()=>requests++,
source:path=>enabled && !failed ? '/adjusted.png' : path};
function getFileType(path) {return path.endsWith('.mp4') ? 'video' : 'image';}
function getThumbnailPath(path) {return path+'.jpg';}
const wallpaperConfig={adapter:{activeColorPreset:'',matugenScheme:'scheme-tonal-spot'}};
const matugenProcessWithConfig={running:false,command:[]};
const matugenProcessNormal={running:false};
const Config={theme:{lightMode:false}};
const Qt={resolvedUrl:path=>path};
const Quickshell={env:()=>'/test-home'};
let currentWallpaper='/original.png', initialLoadCompleted=true, paletteError='';
"""+functions+"""
runMatugenForCurrentWallpaper();
assert.equal(requests,1);
assert.deepEqual(matugenProcessWithConfig.command,[]);
pending=false;
runMatugenForCurrentWallpaper();
assert.equal(matugenProcessWithConfig.command[2],'/adjusted.png');
assert.equal(matugenProcessWithConfig.running,true);
enabled=false;
runMatugenForCurrentWallpaper();
assert.equal(matugenProcessWithConfig.command[2],'/original.png');
enabled=true; failed=true;
runMatugenForCurrentWallpaper();
assert.equal(matugenProcessWithConfig.command[2],'/original.png');
currentWallpaper='/movie.mp4';
runMatugenForCurrentWallpaper();
assert.equal(matugenProcessWithConfig.command[2],'/movie.mp4.jpg');
"""
        result=subprocess.run(['node','-e',script],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_swatches_sample_original_colors(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'original.png'
            image = Image.new('RGB',(100,100),'#e35a92')
            image.paste('#2255bb',(60,0,100,100))
            image.save(source)
            before=source.read_bytes()
            self.assertEqual(dither.original_swatches(source),['#e35a92','#2255bb'])
            result=subprocess.run(['python3',str(ROOT/'scripts/dither_wallpaper.py'),str(source),'--swatches'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(json.loads(result.stdout)['colors'],['#e35a92','#2255bb'])
            self.assertEqual(source.read_bytes(),before)

    def test_tint_shading_cache_and_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'gradient.png'
            Image.linear_gradient('L').convert('RGB').save(source)
            outputs = []
            for tint in ['#ff0000', '#00ff00', '#0000ff', '#000000', '#ffffff']:
                output = dither.convert(source, root/'cache', 'tint', 'strong', tint)
                outputs.append(output)
                with Image.open(output) as result:
                    rgb = result.convert('RGB')
                    self.assertEqual(rgb.size, (256, 256))
                    self.assertLessEqual(len(rgb.getcolors()), 6)
                    self.assertGreater(sum(rgb.getpixel((0,255))), sum(rgb.getpixel((0,0))))
                    if tint == '#ff0000':
                        r,g,b = rgb.getpixel((0,128))
                        self.assertGreater(r,g + 100)
                        self.assertEqual(g,b)
                self.assertEqual(output, dither.convert(source, root/'cache', 'tint', 'strong', tint.upper()))
            self.assertEqual(len(set(outputs)), 5)
            with self.assertRaises(ValueError):
                dither.convert(source, root/'cache', 'tint', tint='invalid')

    def test_invalid_and_animated_images_return_json_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bad = root / 'broken.png'
            bad.write_bytes(b'broken')
            gif = root / 'animated.webp'
            Image.new('RGB', (16, 16), 'red').save(gif, save_all=True,
                append_images=[Image.new('RGB', (16, 16), 'blue')], duration=100)
            for source in (bad, gif, root / 'missing.jpg'):
                result = subprocess.run(['python3', str(ROOT / 'scripts/dither_wallpaper.py'), str(source)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertIn('error', json.loads(result.stdout))


@unittest.skipUnless(shutil.which('qs'), 'Quickshell is required')
class DitherServiceTest(unittest.TestCase):
    def test_queue_palette_changes_failure_and_restoration(self):
        with tempfile.TemporaryDirectory(prefix='dither-runtime-') as directory:
            root = Path(directory)
            (root / 'modules/services').mkdir(parents=True)
            shutil.copy(ROOT / 'modules/services/DitheredWallpapers.qml', root / 'modules/services')
            (root / 'scripts').mkdir()
            shutil.copy(ROOT / 'scripts/dither_wallpaper.py', root / 'scripts')
            (root / 'config').mkdir()
            (root / 'config/Config.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton { property QtObject theme: QtObject {
 property string shellStyle: "glass"; property string ditherPalette: "original"
 property string wallpaperDitherStrength: "strong"
 property string ditherTintColor: "#4c9cbd"
} }
''')
            Image.linear_gradient('L').resize((256, 128)).convert('RGB').save(root / 'one.png')
            Image.new('RGB', (128, 128), 'cyan').save(root / 'two.png')
            (root / 'broken.png').write_bytes(b'bad')
            (root / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import qs.config
import qs.modules.services
ShellRoot {
 TestCase { id: test; when: false
  function check() {
   const a=Qt.resolvedUrl("one.png").toString().replace("file://", "");
   const b=Qt.resolvedUrl("two.png").toString().replace("file://", "");
   const bad=Qt.resolvedUrl("broken.png").toString().replace("file://", "");
   compare(DitheredWallpapers.source(a),a);
   Config.theme.shellStyle="dithered";
   verify(DitheredWallpapers.waiting(a));
   DitheredWallpapers.request(a); DitheredWallpapers.request(b);
   tryVerify(() => !DitheredWallpapers.busy && DitheredWallpapers.source(a)!==a,5000);
   verify(DitheredWallpapers.source(b)!==b);
   const original=DitheredWallpapers.source(a);
   Config.theme.ditherPalette="teal-orange";
   DitheredWallpapers.request(a);
   wait(1);
   Config.theme.ditherPalette="original";
   DitheredWallpapers.request(b);
   tryVerify(() => !DitheredWallpapers.busy,5000);
   compare(DitheredWallpapers.source(a),original);
   Config.theme.wallpaperDitherStrength="intense";
   DitheredWallpapers.request(a);
   tryVerify(() => !DitheredWallpapers.busy && !DitheredWallpapers.waiting(a),5000);
   verify(DitheredWallpapers.source(a)!==original);
   Config.theme.wallpaperDitherStrength="normal";
   DitheredWallpapers.request(a); wait(1);
   Config.theme.wallpaperDitherStrength="strong";
   DitheredWallpapers.request(b);
   tryVerify(() => !DitheredWallpapers.busy,5000);
   compare(DitheredWallpapers.source(a),original);
   Config.theme.ditherPalette="tint";
   DitheredWallpapers.request(a); wait(1);
   Config.theme.ditherTintColor="#ef573c";
   DitheredWallpapers.request(a);
   tryVerify(() => !DitheredWallpapers.busy && !DitheredWallpapers.waiting(a),5000);
   const red=DitheredWallpapers.source(a);
   Config.theme.ditherTintColor="#4c9cbd";
   DitheredWallpapers.request(a);
   tryVerify(() => !DitheredWallpapers.busy && !DitheredWallpapers.waiting(a),5000);
   verify(DitheredWallpapers.source(a)!==red);
   Config.theme.ditherTintColor="#ef573c";
   compare(DitheredWallpapers.source(a),red);
   Config.theme.ditherPalette="teal-orange";
   verify(DitheredWallpapers.source(a)!==original);
   Config.theme.shellStyle="quiet";
   compare(DitheredWallpapers.source(a),a);
   Config.theme.shellStyle="dithered";
   DitheredWallpapers.request(bad);
   tryVerify(() => !DitheredWallpapers.waiting(bad) && !DitheredWallpapers.busy,5000);
   verify(DitheredWallpapers.error.length>0);
   compare(DitheredWallpapers.source(bad),bad);
   verify(!DitheredWallpapers.supported("clip.mp4"));
   console.log("DITHER_SERVICE_PASS"); Qt.quit();
  }
 }
 Timer { interval: 50; running: true; onTriggered: test.check() }
 Timer { interval: 20000; running: true; onTriggered: Qt.exit(1) }
}
''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': '',
                   'XDG_RUNTIME_DIR': str(runtime), 'XDG_CACHE_HOME': str(root / 'cache')}
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=25)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('DITHER_SERVICE_PASS', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
