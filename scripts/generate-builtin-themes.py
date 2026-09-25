#!/usr/bin/env python3
"""Regenerates the community and Omarchy built-in themes:
  Vibeshed/Modules/Theme/BuiltInThemes+CommunityDark.swift
  Vibeshed/Modules/Theme/BuiltInThemes+CommunityLight.swift
  Vibeshed/Modules/Theme/BuiltInThemes+Omarchy.swift

Sources:
  - mbadolato/iTerm2-Color-Schemes `ghostty/<name>` (terminal palettes)
  - basecamp/omarchy `themes/<name>/colors.toml` (Omarchy's semantic palettes)

Run from the repo root:  python3 scripts/generate-builtin-themes.py
"""

import os
import re
import urllib.parse
import urllib.request

OUT = "Vibeshed/Modules/Theme"
ITERM_URL = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/ghostty/{}"
OMARCHY_URL = "https://raw.githubusercontent.com/basecamp/omarchy/master/themes/{}/colors.toml"


def fetch(url):
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")

def hexrgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
def lum(h):
    def ch(c): return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    r,g,b = hexrgb(h); return 0.2126*ch(r)+0.7152*ch(g)+0.0722*ch(b)
def contrast(a,b):
    la,lb = lum(a),lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
def islight(h): r,g,b=hexrgb(h); return round(r*255)+round(g*255)+round(b*255) > 382
def mix(a,b,t):
    ra,rb=hexrgb(a),hexrgb(b); return '#%02x%02x%02x' % tuple(int((x+(y-x)*t)*255+0.5+1e-9) for x,y in zip(ra,rb))

HUES = ['red','green','yellow','blue','magenta','cyan']

# (file, display name, accent (hex or slot name), icon, keywords, semantic overrides)
COMMUNITY = [
 ("Catppuccin Frappe", "Catppuccin Frappé", "#ca9ee6", "cup.and.saucer", ["catppuccin","frappe","pastel"], {}),
 ("Catppuccin Macchiato", "Catppuccin Macchiato", "#c6a0f6", "cup.and.saucer.fill", ["catppuccin","pastel"], {}),
 ("TokyoNight Storm", "Tokyo Night Storm", "blue", "cloud.bolt", ["tokyonight","folke"], {}),
 ("TokyoNight Moon", "Tokyo Night Moon", "blue", "moon", ["tokyonight","folke"], {}),
 ("TokyoNight Day", "Tokyo Night Day", "blue", "sun.horizon", ["tokyonight","folke"], {}),
 ("Rose Pine Moon", "Rosé Pine Moon", "cyan", "moon.haze", ["rose","pine","rosepine"], {}),
 ("Rose Pine Dawn", "Rosé Pine Dawn", "cyan", "sunrise", ["rose","pine","rosepine"], {}),
 ("Kanagawa Dragon", "Kanagawa Dragon", "blue", "lizard", ["kanagawa","dragon"], {}),
 ("Kanagawa Lotus", "Kanagawa Lotus", "blue", "leaf", ["kanagawa","lotus"], {}),
 ("Gruvbox Material Dark", "Gruvbox Material", "#e78a4e", "flame.fill", ["gruvbox","material","retro"], {"orange": "#e78a4e"}),
 ("Gruvbox Light", "Gruvbox Light", "#af3a03", "sun.haze", ["gruvbox","retro"], {"orange": "#af3a03"}),
 ("iTerm2 Solarized Dark", "Solarized Dark", "blue", "moon.circle", ["solarized"],
    {"orange": "#cb4b16", "muted": "#586e75", "bright_red": "#dc322f", "bright_green": "#859900",
     "bright_yellow": "#b58900", "bright_blue": "#268bd2", "bright_magenta": "#d33682", "bright_cyan": "#2aa198",
     "bright_foreground": "#93a1a1"}),
 ("GitHub Dark Default", "GitHub Dark", "blue", "arrow.triangle.branch", ["github","primer"], {}),
 ("GitHub Dark Dimmed", "GitHub Dark Dimmed", "blue", "arrow.triangle.merge", ["github","primer","dimmed"], {}),
 ("GitHub Light Default", "GitHub Light", "blue", "arrow.triangle.pull", ["github","primer"], {}),
 ("Ayu", "Ayu Dark", "#e6b450", "moon.dust", ["ayu"], {}),
 ("Ayu Mirage", "Ayu Mirage", "#ffcc66", "cloud.moon", ["ayu","mirage"], {}),
 ("Ayu Light", "Ayu Light", "#ff9940", "sun.min", ["ayu"], {}),
 ("Nightfox", "Nightfox", "blue", "pawprint", ["nightfox","fox"], {}),
 ("Carbonfox", "Carbonfox", "blue", "pawprint.fill", ["nightfox","fox","carbon"], {}),
 ("Dawnfox", "Dawnfox", "blue", "pawprint.circle", ["nightfox","fox"], {}),
 ("Night Owl", "Night Owl", "blue", "bird", ["owl","sarah drasner"], {}),
 ("Monokai Pro", "Monokai Pro", "#ffd866", "square.stack.3d.up", ["monokai"],
    {"blue": "#78dce8", "cyan": "#78dce8", "orange": "#fc9867", "bright_blue": "#78dce8"}),
 ("Poimandres", "Poimandres", "#5de4c7", "sparkles", ["poimandres","mint"], {}),
 ("Vesper", "Vesper", "#ffc799", "star", ["vesper","minimal","orange"], {"cyan": "#99ffe4", "bright_cyan": "#99ffe4"}),
 ("Flexoki Dark", "Flexoki Dark", "blue", "book.closed", ["flexoki","paper"], {}),
 ("Moonfly", "Moonfly", "blue", "moonphase.waxing.crescent", ["moonfly","bluz71"], {}),
 ("Sonokai", "Sonokai", "#76cce0", "waveform", ["sonokai","monokai"],
    {"cyan": "#76cce0", "bright_cyan": "#76cce0", "orange": "#f39660"}),
 ("Iceberg Dark", "Iceberg", "blue", "snowflake.circle", ["iceberg","cool"], {}),
 ("Melange Dark", "Melange Dark", "#e49b5d", "mug.fill", ["melange","warm"], {"orange": "#e49b5d", "yellow": "#ebc06d"}),
 ("Melange Light", "Melange Light", "#bc5c00", "mug", ["melange","warm"], {"orange": "#bc5c00"}),
 ("Vague", "Vague", "blue", "cloud.fog", ["vague","muted"], {}),
 ("Everforest Light Med", "Everforest Light", "#8da101", "leaf.fill", ["everforest","forest","green"], {}),
 ("Atom One Light", "One Light", "blue", "atom", ["onelight","atom"], {}),
 ("Nord Light", "Nord Light", "#5e81ac", "snowflake", ["nord","arctic"], {}),
]

OMARCHY = [
 ("ethereal", "Ethereal", "sparkles"), ("hackerman", "Hackerman", "terminal"),
 ("last-horizon", "Last Horizon", "sunset"), ("lumon", "Lumon", "building.columns"),
 ("lupine", "Lupine", "drop.fill"), ("matte-black", "Matte Black", "circle.fill"),
 ("miasma", "Miasma", "smoke"), ("osaka-jade", "Osaka Jade", "diamond"),
 ("retro-82", "Retro 82", "tv"), ("ristretto", "Ristretto", "takeoutbag.and.cup.and.straw"),
 ("solitude", "Solitude", "moon.zzz"), ("vantablack", "Vantablack", "square.fill"), ("white", "White", "circle"),
]
OMARCHY_KEYS = ["accent","selection","muted","background","dark_background","darker_background","lighter_background",
                "foreground","dark_foreground","light_foreground","bright_foreground",
                "red","yellow","orange","green","cyan","blue","magenta","brown",
                "bright_red","bright_yellow","bright_green","bright_cyan","bright_blue","bright_magenta"]

def parse_ghostty(text):
    d={}
    for line in text.splitlines():
        m=re.match(r'\s*palette\s*=\s*(\d+)=(#[0-9a-fA-F]{6})',line)
        if m: d['color'+m.group(1)]=m.group(2).lower(); continue
        m=re.match(r'\s*([\w-]+)\s*=\s*(#[0-9a-fA-F]{6})',line)
        if m: d[m.group(1)]=m.group(2).lower()
    return d

def community_colors(d, accent, overrides):
    bg, fg = d['background'], d['foreground']
    dark = not islight(bg)
    c = {'background': bg, 'foreground': fg}
    for i in range(16): c['color%d'%i] = d['color%d'%i]
    for i,h in enumerate(HUES, start=1):
        normal, bright = d['color%d'%i], d['color%d'%(i+8)]
        # Semantic hue: the readable one of the pair on this background.
        if contrast(normal,bg) < 2.5 and contrast(bright,bg) > contrast(normal,bg): normal = bright
        c[h] = normal
        # Some ports put darker tones in the bright slots; brights must not be dimmer on dark themes.
        c['bright_'+h] = bright if not (dark and lum(bright) < lum(normal)) else normal
    c8 = d['color8']
    fgc = contrast(fg,bg)
    c['muted'] = c8 if 1.8 <= contrast(c8,bg) < fgc else mix(fg,bg,0.45)
    cur = d.get('cursor-color')
    if cur and contrast(cur,bg) >= 3: c['cursor'] = cur
    sel = d.get('selection-background')
    if sel and contrast(sel,fg) >= 2.5 and contrast(sel,bg) < fgc: c['selection_background'] = sel
    c['accent'] = accent if accent.startswith('#') else c[accent]
    c.update(overrides)
    return c, ('dark' if dark else 'light')

def swift_def(name, mode, colors, icon, keywords, ident):
    keys = sorted(colors, key=lambda k: (k.startswith('color'), int(k[5:]) if k.startswith('color') else 0, k))
    pairs = ['"%s": "%s"' % (k, colors[k]) for k in keys]
    lines, cur = [], ''
    for p in pairs:
        if len(cur) + len(p) + 2 > 104:
            lines.append(cur.rstrip()); cur = ''
        cur += p + ', '
    if cur: lines.append(cur.rstrip())
    body = '\n'.join('            ' + l for l in lines)
    kw = ', '.join('"%s"' % k for k in keywords)
    return f'''    static let {ident} = ThemeDefinition(
        name: "{name}",
        mode: .{mode},
        colors: [
{body}
        ],
        icon: "{icon}",
        keywords: [{kw}]
    )
'''

def ident(name):
    parts = re.sub(r'[^A-Za-z0-9 ]', ' ', name.replace('é','e')).split()
    s = parts[0].lower() + ''.join(p[:1].upper()+p[1:] for p in parts[1:])
    return s if not s[0].isdigit() else 'theme' + s

def swift_file(comment, ident_name, entries):
    names = [e[0] for e in entries]
    return ('import Foundation\n\n' + comment + 'extension BuiltInThemes {\n'
            + '    static let %s: [ThemeDefinition] = [\n' % ident_name
            + ''.join('        %s,\n' % n for n in names) + '    ]\n\n'
            + '\n'.join(e[1] for e in entries) + '}\n')

COMMUNITY_COMMENT = """// Palettes from popular editor/terminal themes, converted from the ghostty ports in
// mbadolato/iTerm2-Color-Schemes by scripts/generate-builtin-themes.py — edit the script,
// not this file. Terminal colors (`color0`…`color15`) are kept exactly; the semantic hues
// are the readable one of each normal/bright pair, with a few overrides where a port puts
// orange in the blue/cyan slot.
"""

dark, light = [], []
for f, name, accent, icon, kw, ov in COMMUNITY:
    d = parse_ghostty(fetch(ITERM_URL.format(urllib.parse.quote(f))))
    colors, mode = community_colors(d, accent, ov)
    i = ident(name)
    (dark if mode == 'dark' else light).append((i, swift_def(name, mode, colors, icon, kw, i)))
open(os.path.join(OUT, 'BuiltInThemes+CommunityDark.swift'), 'w').write(
    swift_file(COMMUNITY_COMMENT, 'communityDark', dark))
open(os.path.join(OUT, 'BuiltInThemes+CommunityLight.swift'), 'w').write(
    swift_file(COMMUNITY_COMMENT, 'communityLight', light))

omarchy = []
for slug, name, icon in OMARCHY:
    raw = {}
    for line in fetch(OMARCHY_URL.format(slug)).splitlines():
        m = re.match(r'\s*([\w-]+)\s*=\s*"([^"]*)"', line)
        if m: raw[m.group(1)] = m.group(2)
    mode = raw.get('mode', 'dark')
    colors = {k: raw[k].lower() for k in OMARCHY_KEYS if k in raw}
    if 'selection' in colors: colors['selection_background'] = colors.pop('selection')
    i = ident(name)
    omarchy.append((i, swift_def(name, mode, colors, icon, ['omarchy', slug.replace('-', '')], i)))
open(os.path.join(OUT, 'BuiltInThemes+Omarchy.swift'), 'w').write(swift_file(
    "// Omarchy's own themes (basecamp/omarchy `themes/*/colors.toml`), keys taken as-is.\n"
    "// Generated by scripts/generate-builtin-themes.py — edit the script, not this file.\n",
    'omarchy', omarchy))
print('dark', len(dark), 'light', len(light), 'omarchy', len(omarchy))
