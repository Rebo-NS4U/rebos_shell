"""Real QML checks for scratchpad persistence, popup loading and save failures."""
import os, pathlib, shutil, subprocess, tempfile, unittest
root = pathlib.Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class QuickNotesTest(unittest.TestCase):
    def test_persistence_and_popup(self):
        with tempfile.TemporaryDirectory(prefix='quick-notes-') as tmp:
            base=pathlib.Path(tmp); pkg=base/'package'; pkg.mkdir()
            for d in ['modules/services','modules/widgets/notes','modules/globals','modules/components','modules/theme','config']:
                (pkg/d).mkdir(parents=True,exist_ok=True)
            notes=base/'notes.md'
            source=(root/'modules/services/QuickNotes.qml').read_text().replace('Quickshell.env("HOME") + "/Documents/Quick Notes.md"', 'Quickshell.env("NOTES_TEST_FILE")')
            (pkg/'modules/services/QuickNotes.qml').write_text(source)
            for component in ('NotesPopup.qml', 'NotesAction.qml'):
                shutil.copy(root/'modules/widgets/notes'/component,pkg/'modules/widgets/notes')
            for component in ('StyledText.qml', 'StyledToolTip.qml', 'MotionReveal.qml'):
                shutil.copy(root/'modules/components'/component,pkg/'modules/components')
            shutil.copy(root/'modules/theme/Icons.qml',pkg/'modules/theme')
            shutil.copy(root/'modules/theme/Motion.qml',pkg/'modules/theme')
            stubs={
              'modules/services/NiriService.qml':'pragma Singleton\nimport Quickshell\nSingleton { property var focusedMonitor: ({name: Quickshell.screens[0].name}) }',
              'modules/globals/GlobalStates.qml':'pragma Singleton\nimport Quickshell\nSingleton { property bool lockscreenVisible: false }',
              'config/Config.qml':'pragma Singleton\nimport Quickshell\nSingleton { property int animDuration: 0; property var theme: ({font: "Sans", fontSize: 14}) }',
              'modules/theme/Colors.qml':'pragma Singleton\nimport Quickshell\nSingleton { property color overBackground: "#eeeeee"; property color primary: "#aaaaff"; property color overPrimary: "#111111"; property color overSurfaceVariant: "#cccccc"; property color tertiary: "#ffccaa"; property color error: "#ff8888" }',
              'modules/theme/Styling.qml':'pragma Singleton\nimport Quickshell\nSingleton { function fontSize(offset) { return 14 + offset; } function radius(offset) { return 16 + offset; } }',
              'modules/components/StyledRect.qml':'import QtQuick\nRectangle { required property string variant; color: "#222222" }',
            }
            for path,text in stubs.items(): (pkg/path).write_text("import QtQuick\n" + text) if not text.startswith("pragma") else (pkg/path).write_text(text.replace("import Quickshell", "import QtQuick\nimport Quickshell"))
            shell='''import QtQuick
        import QtQuick.Controls
        import Quickshell.Io
        import Quickshell
        import qs.modules.services
        import qs.modules.widgets.notes
        import qs.modules.theme
        ShellRoot {
            Process { id: failWrite; command: ["mkdir", Quickshell.env("NOTES_TEST_FILE")] }
            property int step: 0
            FloatingWindow {
                implicitWidth: 900; implicitHeight: 800; visible: true
                NotesPopup { id: popup; anchors.fill: parent; screen: Quickshell.screens[0] }
            }
            function check(ok, message) { if (!ok) { console.error("FAIL " + message); Qt.quit(); } }
            Timer { interval: 250; running: true; repeat: true
                onTriggered: {
                    step++;
                    if (step === 1) {
                        check(QuickNotes.ready, "ready");
                        if (Quickshell.env("NOTES_TEST_MODE") === "read") {
                            check(QuickNotes.text === "second line\\nUnicode: café 📝", "reload persisted text");
                            console.log("PASS read"); Qt.quit(); return;
                        }
                        QuickNotes.toggle();
                        check(QuickNotes.visible, "toggle opens");
                        QuickNotes.edit("first draft");
                    }
                    if (step === 2) { QuickNotes.edit("second line\\nUnicode: café 📝"); if (Quickshell.env("NOTES_TEST_MODE") === "fail") failWrite.running = true; }
                    if (step === 3) Colors.primary = "#80c0a0";
            if (step === 5) {
                        if (Quickshell.env("NOTES_TEST_MODE") === "fail") {
                            check(QuickNotes.error.length > 0 && QuickNotes.dirty && !QuickNotes.saving, "save error preserves draft");
                        } else {
                    check(!QuickNotes.dirty && !QuickNotes.saving && !QuickNotes.error, "autosave complete");
                    check(popup.statusColor.toString() === "#80c0a0", "live palette update");
                }
                        QuickNotes.close();
                        check(!QuickNotes.visible, "close");
                        QuickNotes.toggle();
                        check(QuickNotes.text === "second line\\nUnicode: café 📝", "reopen retains draft");
                        console.log("PASS " + Quickshell.env("NOTES_TEST_MODE")); Qt.quit();
                    }
                }
            }
        }'''
            (pkg/'shell.qml').write_text(shell)
            runtime=base/'runtime'; runtime.mkdir(mode=0o700)
            env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QPA_PLATFORMTHEME='',XDG_RUNTIME_DIR=str(runtime),XDG_CACHE_HOME=str(base/'cache'),NOTES_TEST_FILE=str(notes))
            for mode in ['write','read','fail']:
                env['NOTES_TEST_MODE']=mode
                if mode=='fail': env['NOTES_TEST_FILE']=str(base/'fail.md')
                proc=subprocess.run(['qs','-p',str(pkg),'--no-color'],env=env,capture_output=True,text=True,timeout=12)
                output=proc.stdout+proc.stderr
                assert proc.returncode==0 and 'PASS '+mode in output and 'FAIL' not in output and 'TypeError' not in output, output
            assert notes.read_text() == 'second line\nUnicode: café 📝'
            print('PASS disk contents, autosave, reload, close/reopen, failure handling and real NotesPopup load')


if __name__ == "__main__":
    unittest.main()
