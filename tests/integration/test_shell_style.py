"""Exercise shell style presets with real QML, pointer events and file persistence.

Palette/compositor backends are stubbed so this never changes the live desktop.
"""
import unittest
from pathlib import Path
import tempfile, os, shutil, subprocess
src=Path(__file__).resolve().parents[2]

@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class ShellStyleSettingsTest(unittest.TestCase):
 def test_presets_and_persistence(self):
  with tempfile.TemporaryDirectory(prefix='bar-settings-check-') as d:
   p=Path(d)
   shutil.copytree(src/'modules',p/'modules')
   import re
   colors=(src/'modules/theme/Colors.qml').read_text()
   names=re.search(r'availableColorNames: (\[.*?\])',colors).group(1)
   import json
   (p/'modules/theme/Colors.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: '+names+';'+''.join('property color '+n+': "'+('white' if n.startswith('over') else '#ac8866' if n.startswith('primary') else '#181818')+'";' for n in json.loads(names))+'}')
   (p/'modules/services/NiriService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var focusedMonitor: null }')
   for name in ['config','assets','version','scripts']:
    (p/name).symlink_to(src/name,target_is_directory=(src/name).is_dir())
   from PIL import Image
   Image.new('RGB',(64,64),'#e35a92').save(p/'pink.png')
   Image.new('RGB',(64,64),'#2255bb').save(p/'blue.png')
   conf=p/'xdg/rebos_shell/config';conf.mkdir(parents=True)
   for f in (src/'assets/presets/rebos_shell Default').glob('*.json'):shutil.copy(f,conf/f.name)
   (conf/'bar.json').write_text(json.dumps({'position':'top','style':'island','pinned':True,'use12hFormat':True}))
   (p/'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.bar
import qs.modules.theme
import qs.modules.widgets.dashboard.controls
ShellRoot {
 Window {visible: true; width: 640; height: 2400
  ColumnLayout {
   anchors.fill: parent
   ShellStyleSettings {id: styles; Layout.fillWidth: true}
   StyledRect {id: settings; variant: "bg"; implicitWidth: 100; implicitHeight: 30}
   StyledRect {id: menu; variant: "popup"; implicitWidth: 100; implicitHeight: 30}
   StyledRect {id: pane; variant: "surface"; implicitWidth: 100; implicitHeight: 30}
   StyledRect {id: accent; variant: "primary"; implicitWidth: 100; implicitHeight: 30}
   StyledRect {id: bar; variant: "bar"; implicitWidth: 100; implicitHeight: 30}
   BarBg {id: normalBar; implicitWidth: 100; implicitHeight: 40}
   StyledSwitch {id: toggle; checked: true}
  }
  TestCase {id: test; when: false
   property bool swatchCaptured: false
   property bool hintCaptured: false
   function checkPatternSizes() {
    for (const surface of [settings,menu,pane,bar,accent]) {
     const fill=findChild(surface,"dithered-fill");
     const edge=findChild(surface,"dithered-outline");
     if (surface.gradientType === "halftone") verify(fill !== null);
     if (surface.ditheredOutline) verify(edge !== null);
     if (fill) compare(fill.cellSize,Styling.ditherCellSize);
     if (edge) compare(edge.cellSize,Styling.ditherCellSize);
     if (edge && Config.theme.ditherBorder === "band") compare(edge.strokeWidth,Styling.ditherEdgeWidth);
     if (fill && edge) compare(fill.cellSize,edge.cellSize);
    }
   }
   function test_styles() {
    tryCompare(Config,"initialLoadComplete",true,5000);
    const customBefore=JSON.stringify(Styling.customRectConfig("common"));
    for (const style of ["quiet","colorful","dithered","custom","glass"]) {
     const card=findChild(styles,"shell-style-"+style);
     verify(card !== null);
     mouseClick(card,card.width/2,card.height/2);
     tryCompare(Config.theme,"shellStyle",style);
     wait(150);
     compare(Styling.shellStyle,style);
     if (style === "quiet") {compare(settings.rectOpacity,1); compare(menu.rectOpacity,1);}
     if (style === "glass") {compare(settings.rectOpacity,0.86); compare(menu.rectOpacity,0.94);}
     if (style === "colorful") compare(settings.rectOpacity,0.82);
     if (style === "dithered") {
      compare(settings.gradientType,"halftone"); compare(settings.rectOpacity,1);
      compare(menu.gradientType,"halftone"); compare(pane.gradientType,"halftone");
      verify(findChild(styles,"dither-palette") !== null);
      const palette=findChild(styles,"dither-palette");
      palette.currentIndex=2; palette.activated(2);
      compare(Config.theme.ditherPalette,"tint");
      const swatches=findChild(styles,"wallpaper-tint-swatches");
      swatches.source=Qt.resolvedUrl("pink.png").toString().replace("file://", "");
      tryVerify(() => swatches.colors.length>0,3000);
      compare(swatches.colors[0],"#e35a92");
      const pink=findChild(swatches,"wallpaper-tint-#e35a92");
      verify(pink !== null); pink.clicked();
      const fill=findChild(pink,"swatch-fill");
      verify(fill.hasFillColor); compare(fill.color.toString(),"#e35a92");
      compare(findChild(fill,"dithered-fill"),null);
      wait(100);
      pink.grabToImage(result => {
       result.saveToFile(Qt.resolvedUrl("swatch.png").toString().replace("file://", ""));
       test.swatchCaptured=true;
      });
      tryCompare(test,"swatchCaptured",true,2000);
      mouseMove(pink,pink.width/2,pink.height/2);

      const hint=findChild(pink,"styled-tooltip");
      verify(hint !== null);
      tryCompare(hint,"visible",true,2500);
      const hintBackground=findChild(hint,"styled-tooltip-background");
      verify(hintBackground !== null);
      compare(hintBackground.variant,"popup");
      hintBackground.grabToImage(result => {
       result.saveToFile(Qt.resolvedUrl("tooltip.png").toString().replace("file://", ""));
       test.hintCaptured=true;
      });
      tryCompare(test,"hintCaptured",true,2000);
      compare(hint.tooltipText,"#e35a92");
      mouseMove(styles,0,0);
      compare(Config.theme.ditherTintColor,"#e35a92");
      swatches.source=Qt.resolvedUrl("blue.png").toString().replace("file://", "");
      tryVerify(() => swatches.colors[0]==="#2255bb",3000);
      swatches.source=Qt.resolvedUrl("missing.png").toString().replace("file://", "");
      tryVerify(() => swatches.error.length>0,3000);
      compare(swatches.colors.length,0);
      const hex=findChild(styles,"dither-tint-hex");
      verify(hex.visible);
      hex.text="#e35a92"; hex.editingFinished();
      compare(Config.theme.ditherTintColor,"#e35a92");
      Config.theme.ditherPalette="original";
      const slider=findChild(styles,"dither-strength");
      verify(slider !== null);
      compare(Config.theme.ditherStrength,20);
      compare(settings.halftoneDotMax,1.5);
      verify(settings.ditheredOutline);
      verify(pane.ditheredOutline);
      compare(bar.gradientType,"halftone");
      compare(bar.gradientAngle,0);
      verify(normalBar.backgroundVisible); compare(normalBar.bgOpacity,1);
      compare(bar.halftoneDotMin,pane.halftoneDotMin);
      checkPatternSizes();
      const gridFill=findChild(bar,"dithered-fill");
      verify(gridFill !== null);
      const cellBefore=gridFill.cellSize;
      bar.implicitWidth=340; bar.implicitHeight=50;
      wait(20);
      compare(gridFill.cellSize,cellBefore);
      checkPatternSizes();
      const outline=findChild(settings,"dithered-outline");
      verify(outline !== null);
      settings.topLeftRadius=3; settings.bottomRightRadius=10;
      compare(outline.corners.x,3); compare(outline.corners.w,10);
      compare(Config.theme.ditherBorder,"band");
      verify(outline.fragmentShader.toString().includes("dither_uniform_edge"));
      compare(outline.cellSize,Styling.ditherCellSize);
      const sharedWidth=outline.strokeWidth;
      settings.border.width=5;
      compare(outline.strokeWidth,sharedWidth);
      compare(outline.nativeStrokeWidth,5);
      settings.border.width=1;
      Config.theme.ditherBorder="double";
      verify(outline.fragmentShader.toString().includes("double_outline"));
      compare(outline.strokeWidth,settings.border.width);
      Config.theme.ditherBorder="dotted";
      verify(outline.fragmentShader.toString().includes("dotted_outline"));
      compare(outline.strokeWidth,Math.max(settings.border.width,Styling.ditherCellSize));
      Config.theme.ditherBorder="band";
      compare(Config.theme.wallpaperDitherStrength,"strong");
      verify(findChild(styles,"dither-border") !== null);
      verify(findChild(styles,"wallpaper-dither-strength") !== null);
      settings.border.color="#8fbbcc";
      compare(outline.edgeColor.toString(),"#8fbbcc");
      settings.enableBorder=false; verify(!settings.ditheredOutline);
      tryVerify(() => findChild(settings,"dithered-outline") === null);
      settings.enableBorder=true; verify(settings.ditheredOutline);
      compare(accent.gradientType,"linear");
      mouseClick(slider,slider.width*0.85,slider.height/2);
      verify(Config.theme.ditherStrength >= 80);
      verify(settings.halftoneDotMax > 3);
      compare(accent.gradientType,"halftone");
      checkPatternSizes();
      Config.theme.ditherStrength=0;
      compare(settings.gradientType,"linear"); compare(accent.gradientType,"linear");
      verify(!settings.ditheredOutline);
      verify(!normalBar.backgroundVisible);
      tryVerify(() => findChild(settings,"dithered-outline") === null);
      Config.theme.ditherStrength=75;
      compare(settings.gradientType,"halftone");
      checkPatternSizes();
     }
     if (style === "custom") compare(JSON.stringify(Styling.getStyledRectConfig("common")),customBefore);
     if (style !== "dithered") verify(!settings.ditheredOutline);
    }
    compare(JSON.stringify(Styling.customRectConfig("common")),customBefore);
    const oldColor=menu.color.toString();
    Colors.primary="#83b4e3";
    wait(50);
    verify(menu.color.toString() !== oldColor,"Surfaces must follow palette changes");
    Config.theme.roundness=0; compare(Styling.radius(16),0);
    Config.theme.roundness=16; verify(Styling.radius(16)<=22);
    toggle.forceActiveFocus(); keyClick(Qt.Key_Space); compare(toggle.checked,false);
    Config.theme.shellStyle="quiet";
    wait(250);
    console.log("SHELL_STYLE_PASS"); Qt.quit();
   }
  }
  Timer {interval: 800; running: true; onTriggered: test.test_styles()}
  Timer {interval: 10000; running: true; onTriggered: Qt.exit(1)}
 }
}''')
   runtime=p/'runtime'; runtime.mkdir(mode=0o700)
   env={**os.environ,'XDG_RUNTIME_DIR':str(runtime),'QT_QPA_PLATFORMTHEME':'','QT_QPA_PLATFORM':'offscreen','XDG_CONFIG_HOME':str(p/'xdg'),'XDG_CACHE_HOME':str(p/'cache')}
   r=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=15)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   self.assertIn('SHELL_STYLE_PASS',r.stdout+r.stderr)
   # ClippingRectangle/shaders require RHI; the software renderer paints them black.
   if os.environ.get('QT_QUICK_BACKEND') == 'rhi':
    with Image.open(p/'swatch.png') as rendered:
     self.assertEqual(rendered.convert('RGB').getpixel((rendered.width//2,rendered.height//2)),(227,90,146))
    with Image.open(p/'tooltip.png') as rendered:
     self.assertLess(max(rendered.convert('RGB').getpixel((rendered.width//2,rendered.height//2))),120)
   self.assertEqual(json.loads((conf/'theme.json').read_text())['shellStyle'],'quiet')
   self.assertEqual(json.loads((conf/'theme.json').read_text())['ditherStrength'],75)
   self.assertEqual(json.loads((conf/'theme.json').read_text())['ditherBorder'],'band')
   (p/'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import qs.config
import qs.modules.theme
ShellRoot {
 TestCase {id: test; when: false
  function checkReload() {
   tryCompare(Config,"initialLoadComplete",true,5000);
   compare(Config.theme.shellStyle,"quiet");
   compare(Config.theme.ditherTintColor,"#e35a92");
   compare(Config.theme.ditherStrength,75);
   compare(Config.theme.ditherBorder,"band");
   compare(Styling.getStyledRectConfig("bg").opacity,1);
   console.log("SHELL_STYLE_RELOAD_PASS"); Qt.quit();
  }
 }
 Timer {interval: 500; running: true; onTriggered: test.checkReload()}
 Timer {interval: 7000; running: true; onTriggered: Qt.exit(1)}
}''')
   r=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   self.assertIn('SHELL_STYLE_RELOAD_PASS',r.stdout+r.stderr)

if __name__ == "__main__":
 unittest.main()
