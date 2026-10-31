"""Exercise shared tooltip rendering and real hover events without changing the desktop."""
from pathlib import Path
import tempfile, shutil, os, subprocess, re, json, unittest
src=Path(__file__).resolve().parents[2]
class HoverHintsTest(unittest.TestCase):
 def test_empty_hints_and_hover_lifecycle(self):
  with tempfile.TemporaryDirectory(prefix='hover-hints-check-') as d:
   p=Path(d)
   shutil.copytree(src/'modules',p/'modules')
   colors=(src/'modules/theme/Colors.qml').read_text()
   names=re.search(r'availableColorNames: (\[.*?\])',colors).group(1)
   (p/'modules/theme/Colors.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: '+names+';'+''.join('property color '+n+': "'+('white' if n.startswith('over') else '#ac8866' if n.startswith('primary') else '#181818')+'";' for n in json.loads(names))+'}')
   for name in ['config','assets','version','scripts']:
    (p/name).symlink_to(src/name,target_is_directory=(src/name).is_dir())
   conf=p/'xdg/rebos_shell/config';conf.mkdir(parents=True)
   for f in (src/'assets/presets/rebos_shell Default').glob('*.json'):shutil.copy(f,conf/f.name)
   (p/'shell.qml').write_text('''import QtQuick
  import QtQuick.Window
  import QtQuick.Controls
  import QtTest
  import Quickshell
  import qs.config
  import qs.modules.components
  import qs.modules.widgets.dashboard.widgets
  ShellRoot {
   Window {id: window; visible: true; width: 600; height: 400
    ControlButton {id: button; x: 100; y: 150; width: 80; height: 50; isActive: false; iconName: ""; tooltipText: ""}
    Button {id: descriptionButton; x: 300; y: 150; text: "Shelf"; hoverEnabled: true
     StyledToolTip {id: descriptionHint; show: descriptionButton.hovered; description: "File shelf"}
    }
    TestCase {id: test; when: false
     property bool captured: false
     function check() {
      tryCompare(Config,"initialLoadComplete",true,5000);
      const hint=findChild(button,"styled-tooltip"); verify(hint !== null);
      compare(hint.popupType,Popup.Item);
      mouseMove(button,40,25); tryCompare(button,"isHovered",true);
      wait(1200); compare(hint.visible,false);
      button.tooltipText=" \\n "; wait(1200); compare(hint.visible,false);
      button.tooltipText="Volume 50%"; tryCompare(hint,"visible",true,2000);
      verify(hint.width>20); verify(hint.height>10);
      compare(hint.text,"Volume 50%");
      const bg=findChild(hint,"styled-tooltip-background"); verify(bg !== null);
      bg.grabToImage(result => {result.saveToFile(Qt.resolvedUrl("tooltip.png").toString().replace("file://", ""));test.captured=true;});
      tryCompare(test,"captured",true,2000);
      button.tooltipText=""; tryCompare(hint,"visible",false);
      mouseMove(descriptionButton,30,15); tryCompare(descriptionHint,"visible",true,2000);
      descriptionHint.description=" "; tryCompare(descriptionHint,"visible",false);
      descriptionHint.description="File shelf"; tryCompare(descriptionHint,"visible",true,2000);
      mouseMove(window,550,350); tryCompare(descriptionHint,"visible",false);
      console.log("HOVER_HINTS_PASS"); Qt.quit();
     }
    }
    Timer {interval: 800; running: true; onTriggered: test.check()}
    Timer {interval: 12000; running: true; onTriggered: Qt.exit(1)}
   }
  }''')
   runtime=p/'runtime'; runtime.mkdir(mode=0o700)
   env={**os.environ,'XDG_RUNTIME_DIR':str(runtime),'QT_QPA_PLATFORMTHEME':'','QT_QPA_PLATFORM':'offscreen','XDG_CONFIG_HOME':str(p/'xdg'),'XDG_CACHE_HOME':str(p/'cache')}

   try:
    r=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=20)
   except subprocess.TimeoutExpired as e:
    print(e.stdout,e.stderr); raise
   print(r.stdout+r.stderr)
   assert r.returncode==0 and 'HOVER_HINTS_PASS' in r.stdout+r.stderr
   from PIL import Image
   with Image.open(p/'tooltip.png') as im:
    rgb=im.convert('RGB'); px=rgb.getpixel((im.width//2,im.height//2))
    if os.environ.get('QT_QUICK_BACKEND') == 'rhi': assert max(px)<120,px
   print('Tooltip render sample:',px)

if __name__ == "__main__":
 unittest.main()
