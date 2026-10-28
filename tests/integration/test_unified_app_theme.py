"""Verify exported styles reach installed-app files without changing user settings."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from apply_desktop_palette import apply
from apply_app_palette import read_jsonc


class UnifiedAppThemeTest(unittest.TestCase):
    def test_presets_export_and_preserve_user_settings(self):
        palette = json.loads((ROOT / 'assets/presets/rebos_shell Default/colors.json').read_text()) if (ROOT / 'assets/presets/rebos_shell Default/colors.json').exists() else None
        if palette is None:
            # Use the generator's complete built-in palette, independent of live files.
            import re
            text = (ROOT / 'modules/theme/Colors.qml').read_text().split('adapter: JsonAdapter {', 1)[1].split('\n    }', 1)[0]
            palette = dict(re.findall(r'property color (\w+): "(#[0-9a-fA-F]{6})"', text))
        source = (ROOT / 'modules/theme/ShellStyles.js').read_text().replace('.pragma library', '')
        script = source + '\nconst raw = ' + json.dumps(palette) + '; console.log(JSON.stringify(["glass","quiet","colorful","custom","dithered"].map(s => appPalette(s, raw, 0.7))));'
        presets = json.loads(subprocess.check_output(['node', '-e', script], text=True))
        self.assertEqual([p['opacity'] for p in presets], [0.86, 1, 0.82, 0.7, 1])
        self.assertEqual(len({p['background'] for p in presets}), 4)
        with tempfile.TemporaryDirectory(prefix='unified-theme-') as directory:
            home = Path(directory)
            profile = home / '.config/zen/default'
            profile.mkdir(parents=True)
            (profile.parent / 'profiles.ini').write_text('[Profile0]\nPath=default\nIsRelative=1\n')
            (profile / 'user.js').write_text('user_pref("example.keep", true);\n')
            (profile / 'chrome').mkdir()
            (profile / 'chrome/userChrome.css').write_text('/* Keep custom rules */\n')
            pdf = home / '.config/sioyek/prefs_user.config'
            pdf.parent.mkdir(parents=True)
            pdf.write_text('# user settings\ndefault_dark_mode 0\nbackground_color 0 0 0\n')
            settings = home / '.config/Code/User/settings.json'
            settings.parent.mkdir(parents=True)
            settings.write_text('// keep this comment\n{"editor.fontSize": 17, "workbench.colorCustomizations": {"editorRuler.foreground":"#123456"}}\n')
            for p in presets:
                with self.subTest(style=p['style']):
                    apply(p, home)
                    exported = json.loads((home / '.cache/rebos_shell/effective-palette.json').read_text())
                    self.assertEqual(exported, p)
                    self.assertIn('default_dark_mode 0', pdf.read_text())
                    self.assertIn('# user settings', pdf.read_text())
                    self.assertEqual(pdf.read_text().count('\nbackground_color '), 1)
                    css = (profile / 'chrome/rebos_shell.css').read_text()
                    self.assertIn('--zen-primary-color: ' + p['primary'], css)
                    self.assertIn('--panel-background-color: ' + p['surfaceContainerHigh'], css)
                    self.assertIn(f", {p['opacity']})", css)
                    prefs = (profile / 'user.js').read_text()
                    self.assertIn('user_pref("example.keep", true);', prefs)
                    self.assertIn('user_pref("zen.widget.linux.transparency", ' + ('false' if p['opacity']==1 else 'true') + ');', prefs)
                    self.assertEqual((profile / 'chrome/userChrome.css').read_text().count('@import'), 1)
                    code = read_jsonc(settings.read_text())
                    self.assertEqual(code['editor.fontSize'], 17)
                    self.assertEqual(code['workbench.colorCustomizations']['editorRuler.foreground'], '#123456')
                    self.assertEqual(code['workbench.colorCustomizations']['editor.background'], p['background'])
                    self.assertIn('// keep this comment', settings.read_text())
                    self.assertIn(f'opacity {p["opacity"]}', (home / '.cache/rebos_shell/niri-colors.kdl').read_text())
                    if shutil.which('niri'):
                        validation = subprocess.run(['niri', 'validate', '-c', str(home / '.cache/rebos_shell/niri-colors.kdl')], capture_output=True, text=True)
                        self.assertEqual(validation.returncode, 0, validation.stdout + validation.stderr)
                    self.assertIn('rgba(var(--spice-rgb-main), ' + str(p['opacity']) + ')', (home / '.config/spicetify/Themes/rebos_shell/user.css').read_text())
                    self.assertIn(p['background'][1:], (home / '.config/qt6ct/colors/rebos_shell.conf').read_text())
                    self.assertIn(p['primary'][1:], (home / '.cache/rebos_shell/fish.fish').read_text())


@unittest.skipUnless(shutil.which('qs'), 'Quickshell is required')
class ReactiveAppThemeTest(unittest.TestCase):
    def test_settings_change_reaches_app_files(self):
        # Run actual Config, Colors and exporters in a temporary home. Only
        # external reload commands are disabled; file generation remains real.
        with tempfile.TemporaryDirectory(prefix='theme-runtime-') as directory:
            root = Path(directory)
            shutil.copytree(ROOT / 'modules', root / 'modules')
            (root / 'modules/globals/GlobalStates.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject {property QtObject wallpaperManager: null}')
            for name in ['PywalGenerator', 'NvChadGenerator', 'DiscordGenerator']:
                (root / f'modules/theme/{name}.qml').write_text(
                    'import QtQuick\nQtObject { property ThemeWriter writerProcess: ThemeWriter {} ; function generate(palette: var): void {} }')
            kitty = root / 'modules/theme/KittyGenerator.qml'
            kitty.write_text(kitty.read_text().replace('pkill -SIGUSR1 -x kitty', 'true'))
            gtk = root / 'modules/theme/GtkGenerator.qml'
            gtk.write_text(gtk.read_text().replace('gsettings set', 'true'))
            shutil.copytree(ROOT / 'scripts', root / 'scripts')
            (root / 'scripts/reload_theme_apps.py').write_text('''from pathlib import Path
import json
home = Path.home()
cache = home / '.cache/rebos_shell'
palette = json.loads((cache / 'effective-palette.json').read_text())
assert 'background_opacity ' + str(palette['opacity']) in (cache / 'kitty.conf').read_text()
assert palette['primary'] in (home / '.config/gtk-3.0/colors.css').read_text()
(cache / 'refresh-observed.json').write_text(json.dumps(palette))
''')
            for name in ['config', 'assets', 'version']:
                (root / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
            (root / 'runtime').mkdir(mode=0o700)
            import re
            initial = dict(re.findall(r'property color (\w+): "(#[0-9a-fA-F]{6})"',
                                      (ROOT / 'modules/theme/Colors.qml').read_text()))
            (root / '.cache/rebos_shell').mkdir(parents=True)
            (root / '.cache/rebos_shell/colors.json').write_text(json.dumps(initial))
            (root / 'shell.qml').write_text("""import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme
ShellRoot {
 FileView {id: exported; path: Quickshell.env("HOME") + "/.cache/rebos_shell/effective-palette.json"}
 FileView {id: terminal; path: Quickshell.env("HOME") + "/.cache/rebos_shell/kitty.conf"}
 FileView {id: observed; path: Quickshell.env("HOME") + "/.cache/rebos_shell/refresh-observed.json"}
 FileView {id: gtk; path: Quickshell.env("HOME") + "/.config/gtk-3.0/colors.css"}
 TestCase {id: test; when: false
  function test_exports() {
   tryCompare(Config, "initialLoadComplete", true, 5000);
   verify(Colors.availableColorNames.length > 0);
   for (const style of ["quiet", "colorful", "glass", "dithered", "custom"]) {
    Config.theme.shellStyle = style;
    tryVerify(function() {
     exported.reload(); terminal.reload(); gtk.reload();
     try {return JSON.parse(exported.text()).style === style;} catch(e) {return false;}
    }, 5000, "Export must follow Settings style " + style);
    const palette = JSON.parse(exported.text());
    const opacity = style === "quiet" || style === "dithered" ? 1 : style === "colorful" ? 0.82 : style === "glass" ? 0.86 : Config.theme.srBg.opacity;
    compare(palette.opacity, opacity);
    tryVerify(function() {terminal.reload(); return terminal.text().includes("background_opacity " + opacity);}, 5000);
    tryVerify(function() {gtk.reload(); return gtk.text().includes(", " + opacity + ")");}, 5000);
   }
   refreshTest.running = true;
  }
 }
 Timer {
  id: refreshTest; interval: 100; repeat: true
  property int phase: 0
  onTriggered: {
   observed.reload();
   let palette;
   try {palette = JSON.parse(observed.text());} catch(e) {return;}
   if (phase === 0 && palette.style === "custom") {
    phase = 1;
    publisher.running = true;
   } else if (phase === 1 && palette.primary === "#123456") {
    phase = 2;
    Colors.refreshApps();
   } else if (phase === 2 && !Colors.forceExport && !Colors.writersBusy && !Colors.refreshPending) {
    console.log("REACTIVE_APP_THEME_PASS"); Qt.quit();
   }
  }
 }
 Process {id: publisher; command: ["python3", "-c", "import json,os; from pathlib import Path; p=Path.home()/'.cache/rebos_shell/colors.json'; d=json.loads((Path.home()/'.cache/rebos_shell/effective-palette.json').read_text()); d={k:v for k,v in d.items() if isinstance(v,str) and v.startswith('#')}; d['primary']='#123456'; t=p.with_suffix('.tmp'); t.write_text(json.dumps(d)); os.replace(t,p)"]}
 Timer {interval: 500; running: true; onTriggered: Qt.callLater(test.test_exports)}
 Timer {interval: 15000; running: true; onTriggered: Qt.exit(1)}
}""")
            env = {**os.environ, 'HOME': str(root), 'XDG_CONFIG_HOME': str(root / '.config'),
                   'XDG_CACHE_HOME': str(root / '.cache'), 'XDG_RUNTIME_DIR': str(root / 'runtime'),
                   'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': '',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/nonexistent'}
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('REACTIVE_APP_THEME_PASS', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
