#!/usr/bin/env python3
"""Export the shell's effective palette without replacing unrelated app settings."""
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def write(path, content):
    # Resolve dotfile symlinks rather than replacing the links themselves.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == content:
        return False
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def update_ini(path, sections):
    """Patch owned keys, preserving comments, ordering and all other keys."""
    text = path.read_text() if path.exists() else ''
    for group, values in sections.items():
        header = '[' + group + ']'
        match = re.search(r'^' + re.escape(header) + r'\s*$', text, re.M)
        if match:
            start = match.end()
            next_group = re.search(r'^\[', text[start:], re.M)
            end = start + next_group.start() if next_group else len(text)
            body = text[start:end]
        else:
            text = text.rstrip() + '\n\n' + header + '\n'
            start = end = len(text)
            body = ''
        for key, value in values.items():
            pattern = r'^' + re.escape(key) + r'\s*=.*$'
            line = key + '=' + str(value)
            if re.search(pattern, body, re.M):
                body = re.sub(pattern, lambda _: line, body, flags=re.M)
            else:
                body = body.rstrip() + '\n' + line + '\n'
        text = text[:start] + body + text[end:]
    return write(path, text)


def apply_ladybird_palette(p, home):
    """Ladybird's own pages currently resolve CSS system colors to fixed defaults."""
    roles = {
        'page': 'background', 'text': 'overSurface', 'body': 'overSurface',
        'muted': 'outline', 'separator': 'outlineVariant',
        'separator-soft': 'surfaceContainerHigh', 'control': 'surfaceContainer',
        'control-hover': 'surfaceContainerHigh', 'control-pressed': 'surfaceBright',
        'segment': 'surface', 'surface': 'surface', 'edge': 'outlineVariant',
        'field-edge': 'outlineVariant', 'link': 'blue', 'checkbox-edge': 'outline',
        'accent': 'primary', 'focus-edge': 'primary', 'badge-background': 'surfaceContainer',
        'badge-text': 'primary', 'brand': 'primary', 'switch-off': 'outlineVariant',
        'preview-tab': 'surface', 'preview-tab-inactive': 'surfaceContainer',
        'preview-tab-current': 'surfaceContainerHigh', 'preview-field': 'surfaceContainerLowest',
        'choice': 'primary', 'error': 'red', 'success': 'green',
        'warning': 'yellow', 'warning-icon': 'yellow',
    }
    css = '/* Generated from the effective desktop palette. Reload open internal pages after changes. */\n:root:root {\n'
    css += ''.join(f'    --{name}: {p[role]};\n' for name, role in roles.items())
    # The built-in primary buttons have white labels in either appearance.
    css += ('    --primary: color-mix(in srgb, var(--accent) 45%, black);\n'
            '    --primary-hover: color-mix(in srgb, var(--accent) 40%, black);\n'
            '    --primary-pressed: color-mix(in srgb, var(--accent) 35%, black);\n'
            '    --focus-ring: color-mix(in srgb, var(--accent) 16%, transparent);\n'
            '    --choice-fill: color-mix(in srgb, var(--accent) 16%, transparent);\n}\n')
    for directory in (home / '.local/opt/ladybird/share/Lagom/ladybird',
                      home / 'ladybird/Base/res/ladybird'):
        if (directory / 'ladybird.css').is_file():
            write(directory / 'rebos-shell.css', css)


def apply(p, home):
    required = ['background', 'surface', 'surfaceBright', 'surfaceContainer',
                'surfaceContainerHigh', 'surfaceContainerLowest', 'overSurface',
                'overPrimary', 'outline', 'outlineVariant', 'primary', 'secondary',
                'tertiary', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan']
    for key in required:
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', p.get(key, '')):
            raise ValueError('Missing or invalid palette color: ' + key)
    cfg = home / '.config'
    bg, fg, surface = p['background'], p['overSurface'], p['surface']
    accent, selected = p['primary'], p['overPrimary']
    muted = p['outline']
    apply_ladybird_palette(p, home)
    # Fish reloads this small palette at each prompt; fzf reads its options
    # file on each search, so existing terminals pick up wallpaper changes.
    roles = {key: p.get(key, fg) for key in
             ('primary', 'secondary', 'tertiary', 'green', 'yellow', 'error',
              'overSurface', 'overSurfaceVariant', 'overPrimary', 'outline')}
    if not all(re.fullmatch(r'#[0-9a-fA-F]{6}', value) for value in roles.values()):
        raise ValueError('Invalid fish palette color')
    fish = ''.join(f'set -g __rebos_shell_{key} {value[1:]}\n'
                   for key, value in roles.items())
    fish_roles = {
        'normal': fg, 'command': accent, 'param': fg, 'quote': p['yellow'],
        'redirection': p['secondary'], 'end': p['tertiary'],
        'error': roles['error'], 'comment': muted, 'autosuggestion': muted,
        'operator': accent, 'escape': p['tertiary'],
        'cwd': accent, 'cwd_root': roles['error'],
        'pager_progress': accent, 'pager_prefix': accent,
        'pager_completion': fg, 'pager_description': roles['overSurfaceVariant'],
        'pager_selected_completion': selected, 'pager_selected_prefix': selected,
        'pager_selected_description': selected}
    for name, value in fish_roles.items():
        prefix = 'fish_pager_color_' if name.startswith('pager_') else 'fish_color_'
        suffix = name.removeprefix('pager_')
        fish += f'set -g {prefix}{suffix} {value[1:]}\n'
    fish += (f'set -g fish_color_selection {selected[1:]} --background={accent[1:]}\n'
             f'set -g fish_color_search_match {selected[1:]} --background={accent[1:]}\n'
             f'set -g fish_pager_color_background --background={surface[1:]}\n'
             f'set -g fish_pager_color_selected_background --background={accent[1:]}\n')
    write(home / '.cache/rebos_shell/fish.fish', fish)
    fzf_roles = {'bg': bg, 'fg': fg, 'bg+': accent, 'fg+': selected,
                 'hl': p['tertiary'], 'hl+': selected, 'info': muted,
                 'border': p['outlineVariant'], 'prompt': accent,
                 'pointer': selected, 'marker': p['tertiary'],
                 'header': p['secondary'], 'spinner': accent}
    write(home / '.cache/rebos_shell/fzf.conf',
          '--height=40%\n--layout=reverse\n--border=rounded\n--info=inline\n'
          '--color=' + ','.join(f'{key}:{value}' for key, value in fzf_roles.items()) + '\n')
    # Niri watches included files and applies color changes without a restart.
    write(home / '.cache/rebos_shell/niri-colors.kdl',
          '// Generated from the effective QuickShell palette.\n'
          'layout {\n'
          '    border {\n'
          f'        active-color "{accent}"\n'
          f'        inactive-color "{p["outlineVariant"]}"\n'
          '    }\n'
          '    focus-ring {\n'
          f'        active-color "{accent}"\n'
          f'        inactive-color "{p["outlineVariant"]}"\n'
          '    }\n'
          '}\n'
          'window-rule {\n'
          '    match app-id=r#"^(Spotify|spotify|com\\.spotify\\.Client|org\\.kde\\.dolphin|thunar)$"#\n'
          f'    opacity {float(max(0, min(1, float(p.get("opacity", 1)))))}\n'
          '}\n')
    alpha = max(0, min(1, float(p.get('opacity', 1))))
    argb = lambda c: '#ff' + c[1:]
    # QPalette::ColorRole order, including Qt 6 placeholder and accent roles.
    active = [fg, surface, p['surfaceBright'], p['surfaceContainerHigh'],
              p['outlineVariant'], p['surfaceContainerLowest'], fg, fg, fg, bg,
              bg, bg, accent, selected, p['blue'], p['magenta'],
              p['surfaceContainer'], surface, fg, fg, muted, accent]
    disabled = active.copy()
    for role in (0, 6, 7, 8, 13, 19, 20):
        disabled[role] = muted
    disabled[12] = p['surfaceContainerHigh']
    palette = '[ColorScheme]\n' + ''.join(
        name + '=' + ', '.join(map(argb, colors)) + '\n'
        for name, colors in [('active_colors', active), ('inactive_colors', active),
                             ('disabled_colors', disabled)])
    for version in (5, 6):
        directory = cfg / f'qt{version}ct'
        target = directory / 'colors/rebos_shell.conf'
        palette_changed = write(target, palette)
        settings_path = directory / f'qt{version}ct.conf'
        settings_changed = update_ini(settings_path, {'Appearance': {
            'color_scheme_path': target, 'custom_palette': 'true'}})
        # qtct watches its settings file; the palette path itself stays fixed.
        if palette_changed and not settings_changed:
            settings_path.touch()

    rgb = lambda c: ','.join(str(int(c[i:i+2], 16)) for i in (1, 3, 5))
    kde = {}
    for group in ('Window', 'View', 'Button', 'Tooltip', 'Complementary', 'Header'):
        kde['Colors:' + group] = {
            'BackgroundNormal': rgb(surface if group == 'Button' else bg),
            'BackgroundAlternate': rgb(p['surfaceContainer']),
            'ForegroundNormal': rgb(fg), 'ForegroundInactive': rgb(muted),
            'ForegroundActive': rgb(accent), 'ForegroundLink': rgb(p['blue']),
            'ForegroundVisited': rgb(p['magenta']), 'ForegroundNegative': rgb(p['red']),
            'ForegroundNeutral': rgb(p['yellow']), 'ForegroundPositive': rgb(p['green']),
            'DecorationFocus': rgb(accent), 'DecorationHover': rgb(p['secondary'])}
    kde['Colors:Selection'] = dict(kde['Colors:View'],
                                  BackgroundNormal=rgb(accent), ForegroundNormal=rgb(selected))
    kde['General'] = {'ColorScheme': 'rebos_shell', 'Name': 'rebos_shell'}
    scheme = home / '.local/share/color-schemes/rebos_shell.colors'
    update_ini(scheme, kde)
    update_ini(cfg / 'kdeglobals', kde)
    if (cfg / 'dolphinrc').exists():
        update_ini(cfg / 'dolphinrc', {'UiSettings': {
            'ColorScheme': 'rebos_shell', 'ColorSchemePath': 'rebos_shell.colors'}})

    fuzzel = {'background': bg[1:] + f'{round(alpha * 255):02x}',
              'text': fg[1:] + 'ff', 'prompt': accent[1:] + 'ff',
              'placeholder': muted[1:] + 'ff', 'input': fg[1:] + 'ff',
              'match': p['tertiary'][1:] + 'ff', 'selection': accent[1:] + 'ff',
              'selection-text': selected[1:] + 'ff',
              'selection-match': selected[1:] + 'ff', 'border': accent[1:] + 'ff'}
    update_ini(cfg / 'fuzzel/fuzzel_theme.ini', {'colors': fuzzel})
    css = {'bg_color': bg, 'fg_color': fg, 'tray_color': surface,
           'accent_color': p['secondary'], 'highlight_color': accent,
           'invert_color': selected, 'caution_color': p['yellow'], 'urgent_color': p['red'],
           'middle_color': accent, 'first_right_color': p['green'],
           'middle_right_color': p['red'], 'last_right_color': p['tertiary'],
           'funny_pastel_color': p['cyan']}
    write(cfg / 'themes/global-colors.css', ''.join(
        f'@define-color {key} {value};\n' for key, value in css.items()))

    btop = {'main_bg': bg, 'main_fg': fg, 'title': fg, 'hi_fg': accent,
            'selected_bg': accent, 'selected_fg': selected, 'inactive_fg': muted,
            'graph_text': fg, 'meter_bg': p['outlineVariant'], 'proc_misc': p['cyan'],
            'cpu_box': accent, 'mem_box': p['green'], 'net_box': p['cyan'],
            'proc_box': p['tertiary'], 'div_line': p['outlineVariant']}
    for meter in ('temp', 'cpu', 'free', 'cached', 'available', 'used', 'download', 'upload'):
        for suffix, role in [('start', 'green'), ('mid', 'primary'), ('end', 'red')]:
            btop[meter + '_' + suffix] = p[role]
    write(cfg / 'btop/themes/rebos_shell.theme', ''.join(
        f'theme[{key}]="{value}"\n' for key, value in btop.items()))
    btop_config = cfg / 'btop/btop.conf'
    text = btop_config.read_text() if btop_config.exists() else ''
    line = 'color_theme = "rebos_shell"'
    if re.search(r'^color_theme\s*=', text, re.M):
        text = re.sub(r'^color_theme\s*=.*$', line, text, flags=re.M)
    else:
        text = text.rstrip() + '\n' + line + '\n'
    write(btop_config, text)

    sioyek = cfg / 'sioyek/prefs_user.config'
    if sioyek.exists():
        text = sioyek.read_text()
        pdf_roles = {'background_color': 'background', 'dark_mode_background_color': 'background',
                     'custom_background_color': 'background', 'custom_text_color': 'overSurface',
                     'page_separator_color': 'background', 'text_highlight_color': 'primary',
                     'search_highlight_color': 'tertiary', 'link_highlight_color': 'primary',
                     'synctex_highlight_color': 'secondary'}
        for key, role in pdf_roles.items():
            value = ' '.join(f'{int(p[role][i:i+2], 16) / 255:.3f}' for i in (1, 3, 5))
            pattern = r'^' + re.escape(key) + r'\s+[^\n]*$'
            if re.search(pattern, text, re.M):
                text = re.sub(pattern, lambda _, k=key, v=value: k + ' ' + v, text, flags=re.M)
            else:
                text = text.rstrip() + '\n' + key + ' ' + value + '\n'
        write(sioyek, text)

    from apply_app_palette import apply as apply_apps
    apply_apps(p, home)


if __name__ == '__main__':
    try:
        apply(json.loads(sys.argv[1]), Path.home())
    except (ValueError, OSError, IndexError) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        sys.exit(1)
