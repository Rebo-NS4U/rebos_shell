"""Exercise real monitor components with offscreen pointer events and changing samples."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('qs'), 'Quickshell is required')
class MonitorDetailsTest(unittest.TestCase):
    def test_stats_grouping_scrolling_and_window_details(self):
        with tempfile.TemporaryDirectory(prefix='monitor-details-') as temp:
            p = Path(temp)
            def write(name, text):
                path = p / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            files = list((SRC / 'modules/widgets/dashboard/metrics').glob('*.qml'))
            files += [SRC / 'modules/bar/island/IslandStatsPanel.qml']
            for f in files:
                write(str(f.relative_to(SRC)), f.read_text())
            write('modules/components/StyledRect.qml', 'import QtQuick\nRectangle {property string variant; property bool enableShadow:false}')
            write('modules/components/StyledText.qml', 'import QtQuick\nText {color:"white";font.pixelSize:14}')
            write('modules/components/Separator.qml', 'import QtQuick\nItem {}')
            icons = sorted(set(re.findall(r'Icons\.(\w+)', '\n'.join(f.read_text() for f in files))))
            write('modules/theme/Icons.qml', 'pragma Singleton\nimport QtQuick\nQtObject {' + ''.join(f'property string {k}: "x";' for k in icons) + '}')
            write('modules/theme/Colors.qml', 'pragma Singleton\nimport QtQuick\nQtObject {' + ''.join('property color '+x+': "white";' for x in ['primary','secondary','overBackground','overSurfaceVariant','overPrimary','outlineVariant']) + '}')
            write('modules/theme/Styling.qml', 'pragma Singleton\nimport QtQuick\nQtObject {function radius(n){return 8;} function fontSize(n){return 14+n;} function srItem(n){return "white";}}')
            write('modules/theme/Motion.qml','pragma Singleton\nimport QtQuick\nQtObject {property int press:0;property int feedback:0;property int feedbackCurve:0}')
            write('config/Config.qml', 'pragma Singleton\nimport QtQuick\nQtObject {property QtObject theme: QtObject {property string font:"Sans";property string monoFont:"Monospace";}}')
            write('modules/globals/GlobalStates.qml', 'pragma Singleton\nimport QtQuick\nQtObject {property bool islandStatsOpen:false}')
            write('modules/services/StateService.qml', 'pragma Singleton\nimport QtQuick\nQtObject {function get(k,v){return v;}}')
            write('modules/services/NetworkService.qml', 'pragma Singleton\nimport QtQuick\nQtObject {property var active:null;property string networkName:"Test network";property bool ethernet:true;property bool wifiEnabled:false;property real networkStrength:100;property bool vpnConnected:false;property string activeSsid:"";property string vpnName:"";function wifiIconForStrength(v){return "x";}}')
            write('modules/services/SystemResources.qml', '''pragma Singleton
import QtQuick
QtObject {
 property string detailMetric: ""
 property string detailTitle: ""
 property list<var> processes: []
 property var windowInfo: ({})
 property bool pickingWindow: false
 property int picks:0
 property bool windowActionBusy:false
 property bool windowKilled:false
 property string windowActionMessage:""
 property string lastAction:""
 function controlWindow(action){lastAction=action;}
 property real cpuUsage:12
 property string cpuModel:"Test CPU"
 property real cpuFrequency:2000
 property int cpuTemp:40
 property real ramUsed:1000000
 property real ramTotal:2000000
 property real ramUsage:50
 property bool gpuDetected:true
 property int gpuCount:1
 property var gpuPciIds:["0000:01:00.0"]
 property var gpuDrivers:["amdgpu"]
 property var gpuNames:["Test GPU"]
 property var gpuUsages:[10]
 property var gpuVramUsed:[1000]
 property var gpuVramTotal:[2000]
 property var gpuTemps:[30]
 property var gpuClockMhz:[1000]
 property var validDisks:["/"]
 property var diskUsage:({"/":20})
 property var diskUsed:({"/":2000})
 property var diskTotal:({"/":10000})
 property var diskTypes:({"/":"ssd"})
 property real networkDownloadSpeed:100
 property real networkUploadSpeed:100
 property int updateInterval:1000
 function showProcesses(m,t){detailTitle=t;detailMetric=m;}
 function pickWindow(){picks++;detailMetric="window";}
}''')
            write('shell.qml', '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.services
import qs.modules.widgets.dashboard.metrics
import qs.modules.bar.island
ShellRoot {
 Window {id:win;visible:true;width:450;height:850
  MetricsTab {id:classic;width:420;visible:!island.visible}
  IslandStatsPanel {id:island;width:420;visible:false}
  TestCase {id:test;name:"monitor";when:windowShown
   function check(ok,message){if(!ok){console.error("CHECK FAILED: "+message);throw new Error(message);}}
   function eq(a,b){check(a===b,"Expected "+b+", got "+a);}
   function find(item,predicate){if(predicate(item))return item;for(const c of item.children??[]){const r=find(c,predicate);if(r)return r;}return null;}
   function label(item,text){return find(item,c=>c.text===text);}
   function clickText(item,text){const l=label(item,text);check(l!==null,"Missing label: "+text);mouseClick(l,l.width/2,l.height/2,Qt.LeftButton);wait(30);}
   function test_flows(){
    let rows=[];
    for(let i=0;i<70;i++) rows.push({pid:1000+i,ppid:100+i,name:"worker"+i,cpu:70-i,ram:1000+i,disk:i,sockets:1,gpu:{"0000:01:00.0":i}});
    rows.push({pid:2000,ppid:100,name:"second child",cpu:1,ram:2000,disk:1,sockets:1,gpu:{}});
    SystemResources.processes=rows;
    for(const view of [classic,island]){
     island.visible=view===island;
     SystemResources.detailMetric="";wait(40);
     const overviewHeight=view.implicitHeight;
     const overviewCpuY=label(view,"Test CPU").mapToItem(view,0,0).y;
     function checkOverview(){
      wait(40);
      check(Math.abs(view.implicitHeight-overviewHeight)<1,"Returning to overview must restore compact height: expected "+overviewHeight+", got "+view.implicitHeight);
      check(Math.abs(label(view,"Test CPU").mapToItem(view,0,0).y-overviewCpuY)<1,"Returning to overview must restore CPU row position");
     }
     clickText(view,"Test CPU");eq(SystemResources.detailMetric,"cpu");
     const details=find(view,c=>c.objectName==="monitor-process-details");check(details!==null);
     eq(details.groups[0].ppid,100);eq(details.groups[0].children.length,2);
     const list=find(view,c=>c.objectName==="monitor-process-list");check(list!==null);check(list.contentHeight>list.height);
     mouseClick(list,30,15,Qt.LeftButton);wait(20);eq(details.expandedPpid,100);
     mouseWheel(list,100,100,0,-480);wait(40);check(list.contentY>0,"Wheel must scroll process list");
     const previousY=list.contentY;
     SystemResources.processes=rows.map(r=>Object.assign({},r,{cpu:r.cpu+0.1}));wait(40);
     check(Math.abs(list.contentY-previousY)<2,"Refresh must preserve scroll position");
     clickText(view,"← All stats");checkOverview();
     clickText(view,view===classic?"RAM":"Memory (RAM)");eq(SystemResources.detailMetric,"ram");clickText(view,"← All stats");checkOverview();
     clickText(view,"Test GPU");eq(SystemResources.detailMetric,"gpu:0000:01:00.0");clickText(view,"← All stats");checkOverview();
     // Storage title in the island includes its mount point too.
     const disk=find(view,c=>typeof c.text==="string" && (c.text==="/" || c.text==="Disk (/)" || c.text.startsWith("Storage ·")));
     check(disk!==null,"Storage target");mouseClick(disk,disk.width/2,disk.height/2,Qt.LeftButton);wait(30);eq(SystemResources.detailMetric,"disk");clickText(view,"← All stats");checkOverview();
     const net=find(view,c=>c.text==="Test network" || c.text==="Ethernet / Local");check(net!==null);mouseClick(net,net.width/2,net.height/2,Qt.LeftButton);wait(30);eq(SystemResources.detailMetric,"network");clickText(view,"← All stats");checkOverview();
     clickText(view,"Pick window on screen");eq(SystemResources.detailMetric,"window");
     SystemResources.windowInfo={window:{id:10,title:"A window",pid:55,app_id:"kitty",layout:{window_size:[800,600]}},process:{pid:55,ppid:1,start:100,name:"kitty",ram:1048576,exe:"/usr/bin/kitty"}};wait(40);
     check(find(view,c=>typeof c.text==="string" && c.text.includes("PPID: 1") && c.text.includes("800 × 600"))!==null,"Window info must render");
     clickText(view,"Close window");eq(SystemResources.lastAction,"close");
     clickText(view,"Terminate");eq(SystemResources.lastAction,"terminate");
     clickText(view,"Force kill");eq(SystemResources.lastAction,"kill");
     clickText(view,"Pick another window");clickText(view,"← All stats");checkOverview();
    }
    eq(SystemResources.picks,4);
    console.log("PASS monitor metric clicks, PPID groups, expansion, scrolling, refresh stability and window details in both layouts");Qt.quit();
   }
  }
  Timer {interval:200;running:true;onTriggered:test.test_flows()}
  Timer {interval:8000;running:true;onTriggered:Qt.exit(1)}
 }
}''')
            runtime=p/'runtime';runtime.mkdir(mode=0o700)
            result=subprocess.run(['qs','-p',str(p),'--no-color'],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QPA_PLATFORMTHEME='',XDG_RUNTIME_DIR=str(runtime)),capture_output=True,text=True,timeout=12)
            output=result.stdout+result.stderr
            self.assertIn('PASS monitor metric clicks',output,output)
            self.assertEqual(result.returncode,0,output)
            self.assertNotIn('TypeError',output,output)

    def test_picker_service_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='monitor-picker-') as temp:
            p = Path(temp)
            def write(name, text):
                path=p/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
            for name in ['modules/services/SystemResources.qml','scripts/process_monitor.py']:
                write(name,(SRC/name).read_text())
            write('scripts/system_monitor.py','import json,time\nprint(json.dumps({"static":{"gpu_pci_ids":["0000:01:00.0"]}}),flush=True)\ntime.sleep(20)')
            write('config/Config.qml','''pragma Singleton
import QtQuick
QtObject {property bool initialLoadComplete:true;property QtObject system:QtObject {property var disks:["/"];}}
''')
            write('modules/globals/GlobalStates.qml','''pragma Singleton
import QtQuick
QtObject {property bool systemMonitorOpen:true;property bool islandStatsOpen:false;}
''')
            write('modules/services/Visibilities.qml','''pragma Singleton
import QtQuick
import qs.modules.globals
QtObject {property int toggles:0;function toggleSystemMonitorForActive(){toggles++;GlobalStates.systemMonitorOpen=!GlobalStates.systemMonitorOpen;}}
''')
            write('bin/niri','''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
state=Path(os.environ['MONITOR_CANCEL_FILE']+'.window')
if 'windows' in sys.argv: print(json.dumps([json.loads(state.read_text())]))
elif 'close-window' in sys.argv: print('{}')
elif Path(os.environ['MONITOR_CANCEL_FILE']).exists(): print('null')
else:
 window={'id':77,'pid':os.getppid(),'title':'Selected window','app_id':'test','workspace_id':4}
 state.write_text(json.dumps(window))
 print(json.dumps(window))
''')
            (p/'bin/niri').chmod(0o755)
            write('shell.qml','''import QtQuick
import QtTest
import Quickshell
import qs.modules.services
import qs.modules.globals
import Quickshell.Io
ShellRoot {
 TestCase {id:test;name:"picker";when:false
  function check(value,msg){if(!value){console.error("CHECK FAILED "+msg);throw new Error(msg);}}
  function settle(){let n=0;while(SystemResources.pickingWindow && n++<100) wait(30);wait(30);check(!SystemResources.pickingWindow,"picker did not finish");}
  function exercise(){
   let attempts=0;while(!SystemResources.gpuPciIds.length && attempts++<30) wait(30);
   check(SystemResources.gpuPciIds[0]==="0000:01:00.0","GPU PCI mapping");
   SystemResources.pickWindow();SystemResources.pickWindow();
   check(SystemResources.pickingWindow,"busy state");check(GlobalStates.systemMonitorOpen,"menu stays open during selection");check(SystemResources.keepMonitorOpen,"selection protects monitor");
   check(Visibilities.toggles===0,"picker must not toggle the monitor");
   settle();
   check(SystemResources.windowInfo.window.id===77,"selected window result");
   check(SystemResources.windowInfo.process.ppid>0,"process parent metadata");
   check(GlobalStates.systemMonitorOpen && Visibilities.toggles===0 && SystemResources.keepMonitorOpen,"menu stays open with result");
   SystemResources.controlWindow("close");SystemResources.controlWindow("close");
   check(SystemResources.windowActionBusy,"action busy state");
   let actionAttempts=0;while(SystemResources.windowActionBusy && actionAttempts++<100) wait(30);
   check(!SystemResources.windowActionBusy && SystemResources.windowActionMessage==="Close requested.","close action result");
   SystemResources.controlWindow("kill");actionAttempts=0;
   while(SystemResources.windowActionBusy && actionAttempts++<100) wait(30);
   check(!SystemResources.windowActionBusy && SystemResources.windowActionMessage!=="Force kill sent.","exited-process error releases busy state");
   check(GlobalStates.systemMonitorOpen,"window actions keep monitor open");
   marker.running=true;
  }
  function cancel(){
   SystemResources.pickWindow();settle();
   check(!!SystemResources.windowInfo.error,"cancellation feedback");
   check(GlobalStates.systemMonitorOpen && Visibilities.toggles===0,"menu stays open on cancel");
   console.log("PASS picker service keeps menu open, returns process information, handles cancellation and prevents duplicate picks");Qt.quit();
  }
 }
 Process {id:marker;command:["touch",Quickshell.shellDir+"/cancel"];onExited:test.cancel()}
 Timer {interval:200;running:true;onTriggered:test.exercise()}
 Timer {interval:8000;running:true;onTriggered:Qt.exit(1)}
}
''')
            runtime=p/'runtime';runtime.mkdir(mode=0o700)
            env=dict(os.environ,PATH=str(p/'bin')+os.pathsep+os.environ['PATH'],MONITOR_CANCEL_FILE=str(p/'cancel'),QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QPA_PLATFORMTHEME='',XDG_RUNTIME_DIR=str(runtime))
            result=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=12)
            output=result.stdout+result.stderr
            self.assertIn('PASS picker service keeps',output,output)
            self.assertEqual(result.returncode,0,output)
            self.assertNotIn('TypeError',output,output)

if __name__=='__main__':
    unittest.main()
