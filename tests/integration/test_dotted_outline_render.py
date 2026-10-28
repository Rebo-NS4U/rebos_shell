"""Pixel-check the actual outline shader with an invisible OpenGL window.

Opt in with REBOS_GPU_RENDER_TEST=1 where a graphics context is accessible.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.environ.get('REBOS_GPU_RENDER_TEST') == '1' and shutil.which('qs'),
                     'Set REBOS_GPU_RENDER_TEST=1 with graphics access')
class DottedOutlineRenderTest(unittest.TestCase):
    def test_round_dots_gaps_corners_and_center(self):
        with tempfile.TemporaryDirectory(prefix='dotted-outline-render-') as directory:
            root = Path(directory)
            for suffix in ('vert.qsb', 'frag.qsb'):
                name = 'dotted_outline.' + suffix
                (root / name).symlink_to(ROOT / 'modules/components' / name)
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
ShellRoot {
 Window { id: win; visible: true; width: 384; height: 120; color: "black"
  component Outline: ShaderEffect {
   width:160; height:80
   property vector2d size: Qt.vector2d(width,height)
   property vector4d corners: Qt.vector4d(16,16,16,16)
   property real strokeWidth: 4
   property real cellSize: 4
   property color edgeColor: "white"
   property color baseColor: "black"
   vertexShader: "dotted_outline.vert.qsb"
   fragmentShader: "dotted_outline.frag.qsb"
  }
  Outline {x:16; y:16}
  Outline {x:208; y:16; corners:Qt.vector4d(0,0,0,0)}
  Timer {interval:500; running:true; onTriggered:win.contentItem.grabToImage(result=>{
   result.saveToFile("''' + str(root / 'render.png') + '''");
   console.log("DOTTED_OUTLINE_RENDER_PASS"); Qt.quit();
  })}
 }
 Timer {interval:5000; running:true; onTriggered:Qt.exit(1)}
}''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                       QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QSG_INFO='1',
                       XDG_RUNTIME_DIR=str(root / 'runtime'))
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DOTTED_OUTLINE_RENDER_PASS', output)
            self.assertNotIn('Loading backend software', output)
            self.assertNotIn('matching property', output)
            with Image.open(root / 'render.png') as raw:
                image = raw.convert('RGB')
                level = lambda x, y: max(image.getpixel((x, y)))
                self.assertGreater(level(32, 18), 200, 'First rounded-outline dot is visible')
                self.assertLess(level(36, 18), 20, 'True gap between neighboring dots')
                self.assertGreater(level(40, 18), 200, 'Next dot has the same size')
                self.assertLess(level(32, 21), 20, 'Circular dot does not become a square block')
                self.assertLess(level(80, 50), 20, 'Center remains transparent')
                self.assertLess(level(16, 16), 20, 'Rounded corner does not leak')
                self.assertGreater(max(level(x, y) for x in range(18, 31)
                                       for y in range(18, 31)), 100, 'Dots follow the corner arc')
                self.assertGreater(level(210, 18), 200, 'Square corner is also dotted')
                self.assertLess(level(214, 18), 20, 'Square edge has clean gaps')
            (root/'double_outline.frag.qsb').symlink_to(ROOT/'modules/components/double_outline.frag.qsb')
            scene=(root/'shell.qml').read_text().replace('property real strokeWidth: 4','property real strokeWidth: 1').replace('property real cellSize: 4','property real cellSize: 2').replace('fragmentShader: "dotted_outline.frag.qsb"','fragmentShader: "double_outline.frag.qsb"')
            (root/'shell.qml').write_text(scene)
            result=subprocess.run(['qs','-p',str(root),'--no-color'],env=env,capture_output=True,text=True,timeout=10)
            output=result.stdout+result.stderr
            self.assertEqual(result.returncode,0,output)
            self.assertIn('DOTTED_OUTLINE_RENDER_PASS',output)
            self.assertNotIn('matching property',output)
            with Image.open(root/'render.png') as raw:
                image=raw.convert('RGB')
                level=lambda x,y:max(image.getpixel((x,y)))
                self.assertGreater(level(32,16),200,'Outer fine line is visible')
                self.assertLess(level(32,17),20,'First gap pixel stays clear')
                self.assertLess(level(32,18),20,'Second gap pixel stays clear')
                self.assertGreater(level(32,19),100,'Inner fine line is visible')
                self.assertLess(level(32,20),20,'No extra inner band')
                self.assertLess(level(80,50),20,'Double outline leaves the center untouched')
            for name in ['dither_uniform_edge.vert.qsb','dither_uniform_edge.frag.qsb']:
                (root/name).symlink_to(ROOT/'modules/components'/name)
            scene=scene.replace('vertexShader: "dotted_outline.vert.qsb"','vertexShader: "dither_uniform_edge.vert.qsb"').replace('fragmentShader: "double_outline.frag.qsb"','fragmentShader: "dither_uniform_edge.frag.qsb"').replace('property color baseColor: "black"','property color baseColor: "black"\n   property color surfaceDotColor: "black"')
            scene=scene.replace('property real strokeWidth: 1','property real strokeWidth: 3').replace('property color surfaceDotColor: "black"','property color surfaceDotColor: "black"\n   property real nativeStrokeWidth: 5')
            (root/'shell.qml').write_text(scene)
            result=subprocess.run(['qs','-p',str(root),'--no-color'],env=env,capture_output=True,text=True,timeout=10)
            output=result.stdout+result.stderr
            self.assertEqual(result.returncode,0,output)
            self.assertIn('DOTTED_OUTLINE_RENDER_PASS',output)
            self.assertNotIn('matching property',output)
            with Image.open(root/'render.png') as raw:
                image=raw.convert('RGB')
                level=lambda x,y:max(image.getpixel((x,y)))
                widths=[sum(level(250,y)>20 for y in range(16,24)),
                        sum(level(250,y)>20 for y in range(88,96)),
                        sum(level(x,50)>20 for x in range(208,216)),
                        sum(level(x,50)>20 for x in range(360,368))]
                self.assertEqual(widths,[3,3,3,3],'All four sides have the same narrow width')
                tones={level(x,17) for x in range(40,146)}
                self.assertEqual(len(tones),2,'Texture has two regular tones, not scattered grain')
                self.assertGreater(min(tones),20,'A quiet base preserves uniform visible width')
                self.assertLess(max(tones),220,'The border retains restrained contrast')
                self.assertEqual(sum(level(x,20)>20 for x in range(40,146)),0,
                                 'No accent pixels extend past the uniform band')
                self.assertLess(level(80,50),20,'Dithered band leaves the center untouched')
                self.assertLess(level(16,16),20,'Rounded edge band does not leak')


if __name__ == '__main__':
    unittest.main()
