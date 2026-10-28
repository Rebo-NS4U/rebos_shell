#!/usr/bin/python3
"""Themed approval UI; password mode is only for sudo's private askpass pipe."""
import argparse
import json
import math
from pathlib import Path
import re
import sys

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk, Pango


def read_json(path):
    try:
        value = path.read_text()
        result = json.loads(value)
        return result if isinstance(result, dict) else {}
    except (OSError, ValueError):
        return {}


def mix(a, b, amount):
    return "#" + "".join(f"{round(int(a[i:i+2], 16) * (1-amount) + int(b[i:i+2], 16) * amount):02x}"
                          for i in (1, 3, 5))


def theme():
    home = Path.home()
    colors = read_json(home / ".cache/rebos_shell/colors.json")
    config = read_json(home / ".config/rebos_shell/config/theme.json")
    def color(key, fallback):
        value = colors.get(key, fallback)
        return value if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value) else fallback
    fg = color("overBackground", "#eeeeee")
    bg = "#000000" if config.get("oledMode") else color("background", "#181818")
    accent = color("primary", fg)
    style = config.get("shellStyle", "glass")
    quiet = style in ("quiet", "dithered")
    tint = .1 if style == "colorful" else (.015 if quiet else .035)
    base = mix(bg, fg, .035)
    fill = mix(base, accent, tint)
    strength = max(0, min(100, float(config.get("ditherStrength", 20))))
    return dict(fg=fg, bg=fill, accent=accent, on_accent=color("overPrimary", bg),
                inset=mix(bg, accent, tint * .6), border=mix(base, accent, .38 if style == "dithered" else .18),
                dot=mix(fill, fg, strength * .00175),
                cell=.75 + strength * .0375 if style == "dithered" and strength > 0 else 0,
                radius=max(0, float(config.get("roundness", 16))),
                font=str(config.get("font", "sans-serif")), size=max(10, int(config.get("fontSize", 14))))


class Prompt:
    def __init__(self, args):
        self.args = args
        self.result = 1
        self.app = Gtk.Application(application_id=None)
        self.app.connect("activate", self.activate)

    def finish(self, accepted):
        if accepted and self.args.mode == "password":
            # Only sudo reads this process's stdout. Never log or persist it.
            sys.stdout.write(self.entry.get_text() + "\n")
            sys.stdout.flush()
            self.entry.set_text("")
        self.result = 0 if accepted else 1
        self.app.quit()

    def activate(self, app):
        self.window = Gtk.ApplicationWindow(application=app)
        self.window.set_title("Administrator password" if self.args.mode == "password" else "Administrator approval")
        self.window.set_default_size(600 if self.args.mode == "approve" else 440, -1)
        self.window.set_resizable(False)
        self.window.set_decorated(False)
        self.window.add_css_class("sudo-prompt")
        self.window.connect("close-request", lambda *_: self.finish(False))
        keyboard = Gtk.EventControllerKey()
        keyboard.connect("key-pressed", self.key_pressed)
        self.window.add_controller(keyboard)
        overlay = Gtk.Overlay()
        overlay.add_css_class("panel")
        overlay.set_overflow(Gtk.Overflow.HIDDEN)
        self.window.set_child(overlay)
        self.canvas = Gtk.DrawingArea()
        self.canvas.set_draw_func(self.draw)
        overlay.set_child(self.canvas)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        for side in ("top", "bottom", "start", "end"):
            getattr(content, "set_margin_" + side)(24)
        overlay.add_overlay(content)
        overlay.set_measure_overlay(content, True)
        title = Gtk.Label(label=self.window.get_title(), xalign=0)
        title.add_css_class("heading")
        content.append(title)
        self.label(content, self.args.reason if self.args.mode == "approve"
                   else "Enter your password for the command you approved.")
        if self.args.mode == "approve":
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_propagate_natural_height(True)
            scroll.set_max_content_height(220)
            command_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.label(command_box, self.args.command, "command")
            scroll.set_child(command_box)
            content.append(scroll)
            self.label(content, "Working directory: " + self.args.directory)
        else:
            self.entry = Gtk.PasswordEntry()
            self.entry.set_show_peek_icon(False)
            self.entry.set_hexpand(True)
            self.entry.connect("activate", lambda *_: self.finish(True))
            content.append(self.entry)
        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.END)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.finish(False))
        buttons.append(cancel)
        allow = Gtk.Button(label="Authenticate" if self.args.mode == "password" else "Allow this command")
        allow.add_css_class("primary")
        allow.connect("clicked", lambda *_: self.finish(True))
        buttons.append(allow)
        content.append(buttons)
        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(self.window.get_display(), self.provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.current_theme = None
        self.refresh()
        GLib.timeout_add(500, self.refresh)
        self.window.present()
        # Approval deliberately defaults to Cancel; password Enter submits.
        (self.entry if self.args.mode == "password" else cancel).grab_focus()

    def key_pressed(self, controller, key, code, state):
        if key == Gdk.KEY_Escape:
            self.finish(False)
            return True
        return False

    def label(self, box, text, css_class=None):
        label = Gtk.Label(label=text, xalign=0, wrap=True, selectable=css_class == "command")
        label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        label.set_max_width_chars(62)
        if css_class:
            label.add_css_class(css_class)
        box.append(label)

    def refresh(self):
        t = theme()
        if t == self.current_theme:
            return True
        self.current_theme = t
        font = json.dumps(t['font'])
        css = f"""
        window.sudo-prompt {{ background: transparent; color: {t['fg']}; font-family: {font}; font-size: {t['size']}px; }}
        .sudo-prompt .panel {{ background: {t['bg']}; border: 1px solid {t['border']}; border-radius: {t['radius']}px; }}
        .sudo-prompt label {{ color: {t['fg']}; }}
        .sudo-prompt .heading {{ font-weight: bold; font-size: {t['size']+3}px; }}
        .sudo-prompt .command {{ background: {t['inset']}; border: 1px solid {t['border']}; border-radius: {t['radius']/2}px; padding: 12px; }}
        .sudo-prompt button, .sudo-prompt entry {{ background: {t['inset']}; color: {t['fg']}; border: 1px solid {t['border']}; border-radius: {t['radius']/2}px; padding: 10px 14px; box-shadow: none; }}
        .sudo-prompt button.primary {{ background: {t['accent']}; color: {t['on_accent']}; }}
        .sudo-prompt button.primary label {{ color: {t['on_accent']}; }}
        .sudo-prompt button:focus-visible, .sudo-prompt entry:focus-within {{ outline: 2px solid {t['accent']}; outline-offset: 2px; }}
        .sudo-prompt button:hover {{ border-color: {t['accent']}; }}
        """
        self.provider.load_from_data(css.encode())
        self.canvas.queue_draw()
        return True

    def draw(self, area, context, width, height):
        t = self.current_theme
        if not t or not t['cell']:
            return
        cell = t['cell']
        context.set_source_rgb(*(int(t['dot'][i:i+2], 16) / 255 for i in (1, 3, 5)))
        # Same logical-pixel checker grid as components/dither_pattern.glsl.
        for row in range(math.ceil(height / cell)):
            for col in range((row + 1) % 2, math.ceil(width / cell), 2):
                context.rectangle(col * cell, row * cell, cell, cell)
        context.fill()

    def run(self):
        self.app.run([])
        return self.result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("approve", "password"))
    parser.add_argument("--reason", default="")
    parser.add_argument("--command", default="")
    parser.add_argument("--directory", default="")
    sys.exit(Prompt(parser.parse_args()).run())
