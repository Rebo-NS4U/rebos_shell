"""Verify per-window dots and active workspace indications."""
from pathlib import Path
import tempfile, shutil, subprocess, os, unittest
src=Path(__file__).resolve().parents[2]
@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class TaskbarEntryTest(unittest.TestCase):
 def test_app_entry(self):
  with tempfile.TemporaryDirectory(prefix='taskbar-entry-') as d:
   p=Path(d)
   def write(name,s):
    f=p/name; f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s)
   for name in ['modules/bar/workspaces/RebosTaskbar.qml','modules/theme/Icons.qml']:
    f=p/name;f.parent.mkdir(parents=True,exist_ok=True);shutil.copy(src/name,f)
   write('config/Config.qml','pragma Singleton\nimport QtQuick\nQtObject { property int animDuration: 180 }')
   write('modules/theme/Styling.qml','pragma Singleton\nimport QtQuick\nQtObject {function fontSize(n){return 14;} function radius(n){return 10;}}')
   write('modules/theme/Colors.qml','pragma Singleton\nimport QtQuick\nQtObject {property color primary:"pink";property color red:"red";property color overSurfaceVariant:"gray";}')
   write('modules/bar/BarAppearance.qml','pragma Singleton\nimport QtQuick\nQtObject {property color foregroundColor:"white";}')
   write('modules/bar/BarSymbol.qml','import QtQuick\nItem {property string symbol;property real size;property color color;}')
   write('modules/components/StyledRect.qml','import QtQuick\nRectangle {property string variant;property bool animateRadius;property bool enableBorder;property bool enableShadow;}')
   write('modules/components/StyledToolTip.qml','import QtQuick\nItem {property bool show;property string tooltipText;property string description;}')
   write('modules/components/ScrollStepHandler.qml','import QtQuick\nItem {signal stepped(int steps);}')
   write('modules/services/NiriService.qml','''pragma Singleton
  import QtQuick
  QtObject {
   property var spaces: [{id:1,active:true,idx:1},{id:2,active:false,idx:2}]
   property var apps: [{id:1,appId:"kitty"}]
   property int selected: 0
   function workspacesForOutput(s){return spaces;}
   function windowsForWorkspace(id){return id===1 ? apps : [];}
   function focusWindow(id){} function focusWorkspace(id){selected=id;} function runNiriAction(args){}
  }''')
   write('shell.qml','''import QtQuick
  import QtQuick.Window
  import QtTest
  import Quickshell
  import qs.modules.bar.workspaces
  import qs.modules.services
  import qs.config
  ShellRoot {
   Window {id:win;visible:true;width:700;height:100
    Item {id:bar;property QtObject screen: QtObject {property string name:"test"}}
    RebosTaskbar {id:taskbar;bar:bar;showBackground:false}
    TestCase {id:t;name:"entry";when:windowShown
     function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const f=find(c,name);if(f)return f;}return null;}
     function check(value,message){if(!value){console.error("FAIL",message);Qt.exit(2);throw new Error(message);}}
     function equal(a,b){check(a===b,"expected "+a+" == "+b);}
     function test_entry(){
      wait(200);
      const original=find(taskbar,"workspace-1");check(original!==null);
      const before=taskbar.width;
      const first=find(taskbar,"window-dot-1");check(first!==null);
      const empty=find(taskbar,"workspace-dot-2");
      equal(empty.opacity,1);equal(empty.color.toString(),"#00000000");
      equal(empty.border.color.toString(),first.color.toString());
      check(empty.border.width>0,"empty workspace has a visible outline");
      equal(empty.mapToItem(taskbar,0,empty.height/2).y,first.mapToItem(taskbar,0,first.height/2).y);
      NiriService.spaces=[{id:1,active:false,idx:1},{id:2,active:true,idx:2}];wait(220);
      equal(first.opacity,1);
      NiriService.spaces=[{id:1,active:true,idx:1},{id:2,active:false,idx:2}];wait(220);
      NiriService.apps=[{id:1,appId:"kitty"},{id:2,appId:"firefox"},{id:3,appId:"mpv"}];
      wait(220);
      for(let id=1;id<=3;id++){
       const dot=find(taskbar,"window-dot-"+id);check(dot!==null,"one dot per window");
       equal(dot.width,first.width);equal(dot.opacity,1);
      }
      equal(find(taskbar,"window-dot-1"),first);
      const underline=find(taskbar,"workspace-underline-1");
      const dotLeft=first.mapToItem(original,0,0).x;
      const last=find(taskbar,"window-dot-3");
      const dotRight=last.mapToItem(original,last.width,0).x;
      check(Math.abs((dotLeft+dotRight)/2-(underline.x+underline.width/2))<0.01,"underline exactly centered beneath multiple dots");
      check(taskbar.width>before,"workspace fits multiple dots");
      check(!find(taskbar,"workspace-dot-1").visible,"empty marker hidden when occupied");
      NiriService.apps=[{id:3,appId:"mpv"},{id:1,appId:"kitty"}];wait(100);
      equal(find(taskbar,"window-dot-2"),null);equal(find(taskbar,"window-dot-1"),first);
      const left=find(taskbar,"window-dot-3"),right=find(taskbar,"window-dot-1");
      check(left.x<right.x,"dot order follows windows");
      NiriService.apps=[];wait(200);equal(taskbar.width,before);
      equal(find(taskbar,"window-dot-1"),null);
      check(find(taskbar,"workspace-dot-1").visible,"empty workspace marker restored");
      const marker=find(taskbar,"workspace-dot-1");
      equal(marker.x+marker.width/2,underline.x+underline.width/2);
      NiriService.spaces=[{id:1,active:false,idx:1},{id:2,active:true,idx:2}];
      wait(220);
      equal(find(taskbar,"workspace-underline-1").opacity,0);
      equal(find(taskbar,"workspace-underline-2").opacity,1);
      equal(taskbar.width,before);equal(find(taskbar,"workspace-1"),original);
      const target=find(taskbar,"workspace-2");mouseClick(target,target.width/2,target.height/2,Qt.LeftButton);
      equal(NiriService.selected,2);
      NiriService.spaces=[...NiriService.spaces,{id:3,active:false,idx:3}];wait(80);
      check(find(taskbar,"workspace-3")!==null,"new workspace appears");
      equal(find(taskbar,"workspace-1"),original);
      console.log("PASS per-window dot counts, add/remove/reorder, stable delegates, empty marker, active underline and workspace click");Qt.quit();
     }
    }
    Timer {interval:30;running:true;onTriggered:t.test_entry()}
   }
   Timer {interval:5000;running:true;onTriggered:Qt.exit(1)}
  }''')
   runtime=p/'runtime';runtime.mkdir(mode=0o700)
   r=subprocess.run(['qs','-p',str(p),'--no-color'],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='',XDG_RUNTIME_DIR=str(runtime)),capture_output=True,text=True,timeout=8)
   self.assertEqual(r.returncode, 0, r.stdout+r.stderr)

if __name__ == "__main__":
 unittest.main()
