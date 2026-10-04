#!/usr/bin/env python3
"""Draws Vibeshed's icon and wallpapers from one vector source, then renders them.

    scripts/generate-brand-assets.py                 # Resources/AppIcon.{svg,png,icns}, docs/icon.png
    scripts/generate-brand-assets.py --wallpapers    # ...and docs/wallpapers/*.jpg
    scripts/generate-brand-assets.py --palette ink   # another palette (see PALETTES)
    scripts/generate-brand-assets.py --layers DIR    # unmasked layers for building a Liquid Glass
                                                     # icon in Icon Composer

Rendering needs rsvg-convert (`brew install librsvg`). JPEG wallpapers also need ImageMagick
(preferred, for smaller files) or sips (built into macOS); without either they're written as PNG.
The .icns is assembled here, so iconutil isn't needed.

The icon follows Apple's macOS grid: an 824px continuous-corner tile centered on a 1024px canvas
with transparent margins. That's the shape macOS 26+ expects of an .icns; anything that spills
outside it gets shrunk onto a gray tile.
"""

import argparse
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# MARK: - Palettes

PALETTES = {
    # Tangerine to raspberry with a cream wand: warm and loud, and unlike the blues and
    # purples that fill most Docks. The corner under the wand's head is the deepest, so the
    # head keeps its contrast (4.6:1) at 16px.
    "sunset": {
        "tile": [(0, "#FFB54D"), (0.5, "#FF6F61"), (1, "#D81E5B")],
        "ripple": ("#FFFFFF", 0.075),
        "wand": [(0, "#FFFFFF"), (0.5, "#FFF6F0"), (1, "#FFD9CB")],
        "neck": [(0, "#F9C7B6"), (1, "#E6958C")],
        "ridge": [(0, "#FFFFFF"), (1, "#FFD2C2")],
        "button": "#FF4F7B",
        "waves": "#FFFFFF",
        "shadow": ("#8A0A3A", 0.32),
        "shine": 0,
    },
    # Aubergine with a peach wand: the old icon's night-time mood, without the neon.
    "plum": {
        "tile": [(0, "#5A2366"), (0.6, "#33123F"), (1, "#1A0A26")],
        "ripple": ("#FFB49A", 0.055),
        "wand": [(0, "#FFE3D4"), (0.5, "#FFB79E"), (1, "#EE7C73")],
        "neck": [(0, "#C9606A"), (1, "#8E3557")],
        "ridge": [(0, "#FFD0BE"), (1, "#E58A80")],
        "button": "#6E2963",
        "waves": "#FFA690",
        "shadow": ("#000000", 0.35),
        "shine": 0.35,
    },
    # Cream with a coral wand: light and friendly.
    "cream": {
        "tile": [(0, "#FFFAF3"), (1, "#FFE2CF")],
        "ripple": ("#FF5F5D", 0.06),
        "wand": [(0, "#FF907F"), (0.5, "#FF605D"), (1, "#DD3B53")],
        "neck": [(0, "#C9384F"), (1, "#9E2440")],
        "ridge": [(0, "#FF8C7C"), (1, "#E2475A")],
        "button": "#FFF1E6",
        "waves": "#FF605D",
        "shadow": ("#C2404F", 0.22),
        "shine": 0.35,
    },
    # Near-black with a sunset-gradient wand: the dark-mode, developer-tool take.
    "ink": {
        "tile": [(0, "#2C2D44"), (1, "#0D0E18")],
        "ripple": ("#FF7C6A", 0.05),
        "wand": [(0, "#FFCB8F"), (0.5, "#FF7D6B"), (1, "#E5417D")],
        "neck": [(0, "#B8406D"), (1, "#7D2856")],
        "ridge": [(0, "#FFB58A"), (1, "#E2587A")],
        "button": "#2A2B40",
        "waves": "#FF8A6E",
        "shadow": ("#000000", 0.45),
        "shine": 0.35,
    },
}

# MARK: - Geometry

CANVAS = 1024
TILE = 824  # Apple's macOS icon grid: the tile, centered, leaves a 100px margin
TILE_RADIUS = 185.4

# The wand in its own frame: axis along y, head up (negative y), in canvas pixels.
HEAD_R = 150
HEAD_TOP = -380
HEAD_BASE = -112
HEAD_CY = HEAD_TOP + HEAD_R  # center of the dome
NECK_TOP, NECK_BOTTOM = HEAD_BASE - 6, -34
HANDLE_TOP = -44
HANDLE_W_TOP, HANDLE_W_BOTTOM = 170, 150
HANDLE_END = 430
WAVE_CY = HEAD_CY + 22  # vibration arcs and ripples center here
# The wand's pose everywhere, clockwise from upright: head down-right, handle up-left. Head down
# keeps it from reading as a magnifier, whose lens is always on top.
WAND_ANGLE = 150
# Where the wand sits on the tile: local (0, -60) on (482, 550), which centers the wand and its
# arcs where the tile's optical center is.
WAND_PLACEMENT = {"scale": 0.8, "anchor": (482, 550), "pivot": -60}

# Corner of a continuous-curvature rounded rect, in units of the corner radius (the curve
# UIKit/AppKit use since iOS 7 and Big Sur), from the straight edge round to the next one.
_CORNER = [
    ((1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ((0.63149399, 0.07491100),),
    ((0.37282392, 0.16905899), (0.16905899, 0.37282392), (0.07491100, 0.63149399)),
    ((0.06549600, 0.66993427),),
    ((0.0, 0.86840689), (0.0, 1.08849323), (0.0, 1.52866471)),
]
_CORNER_EXTENT = 1.52866483


def squircle(x, y, size, radius):
    """SVG path for a continuous-corner rounded square."""
    radius = min(radius, size / 2 / _CORNER_EXTENT)
    corners = [  # map (along incoming edge, along outgoing edge) to canvas points, clockwise
        lambda a, b: (x + size - a * radius, y + b * radius),
        lambda a, b: (x + size - b * radius, y + size - a * radius),
        lambda a, b: (x + a * radius, y + size - b * radius),
        lambda a, b: (x + b * radius, y + a * radius),
    ]
    d = [f"M{x + _CORNER_EXTENT * radius:.2f},{y:.2f}"]
    for corner in corners:
        d.append("L%.2f,%.2f" % corner(_CORNER_EXTENT, 0))
        for segment in _CORNER:
            points = " ".join("%.2f,%.2f" % corner(*p) for p in segment)
            d.append(("C" if len(segment) == 3 else "L") + points)
    return " ".join(d) + "Z"


def arc(cx, cy, r, start, end):
    """SVG arc, clockwise on screen from `start` to `end` degrees."""
    x0, y0 = cx + r * math.cos(math.radians(start)), cy + r * math.sin(math.radians(start))
    x1, y1 = cx + r * math.cos(math.radians(end)), cy + r * math.sin(math.radians(end))
    large = 1 if (end - start) % 360 > 180 else 0
    return f"M{x0:.1f},{y0:.1f} A{r},{r} 0 {large} 1 {x1:.1f},{y1:.1f}"


def head_path():
    """A dome with straight sides and a flat, rounded-off base."""
    r, base = HEAD_R, HEAD_BASE
    return (f"M{-r},{HEAD_CY} A{r},{r} 0 0 1 {r},{HEAD_CY} "
            f"L{r},{base - 58} C{r},{base - 16} {r - 24},{base} {r - 64},{base} "
            f"L{-r + 64},{base} C{-r + 24},{base} {-r},{base - 16} {-r},{base - 58} Z")


def handle_path():
    """A long capsule, a little wider at the top, with softened shoulders."""
    top, bottom = HANDLE_W_TOP / 2, HANDLE_W_BOTTOM / 2
    cap = HANDLE_END - bottom
    y = HANDLE_TOP
    return (f"M{-top},{y + 24} C{-top},{y + 7} {-top + 15},{y} {-top + 36},{y} "
            f"L{top - 36},{y} C{top - 15},{y} {top},{y + 7} {top},{y + 24} "
            f"L{bottom},{cap} A{bottom},{bottom} 0 0 1 {-bottom},{cap} Z")


def neck_rect():
    return f'x="-62" y="{NECK_TOP}" width="124" height="{NECK_BOTTOM - NECK_TOP}"'


def placement(scale, anchor, pivot, angle=WAND_ANGLE):
    """Transform that rotates the wand frame by `angle` and puts local (0, pivot) on `anchor`."""
    dx = -pivot * math.sin(math.radians(angle)) * scale
    dy = pivot * math.cos(math.radians(angle)) * scale
    return f"translate({anchor[0] - dx:.2f} {anchor[1] - dy:.2f}) rotate({angle}) scale({scale})"


def stops(gradient):
    return "".join(f'<stop offset="{offset}" stop-color="{color}"/>' for offset, color in gradient)


def wand_defs(p, uid):
    return (f'<linearGradient id="{uid}-wand" x1="0" y1="0" x2="1" y2="0">{stops(p["wand"])}</linearGradient>'
            f'<linearGradient id="{uid}-neck" x1="0" y1="0" x2="1" y2="0">{stops(p["neck"])}</linearGradient>'
            f'<linearGradient id="{uid}-ridge" x1="0" y1="0" x2="1" y2="0">{stops(p["ridge"])}</linearGradient>')


def wand(p, uid, small=False):
    """The wand in its own frame, shaded across its width. `small` drops the fine detail."""
    parts = [f'<rect {neck_rect()} fill="url(#{uid}-neck)"/>']
    if not small:
        for y in (HEAD_BASE + 14, HEAD_BASE + 42):
            parts.append(f'<rect x="-70" y="{y}" width="140" height="18" rx="9" fill="url(#{uid}-ridge)"/>')
    parts.append(f'<path d="{handle_path()}" fill="url(#{uid}-wand)"/>')
    if not small and p["button"]:
        parts.append(f'<rect x="-15" y="74" width="30" height="62" rx="15" fill="{p["button"]}"/>')
    parts.append(f'<path d="{head_path()}" fill="url(#{uid}-wand)"/>')
    if not small and p["shine"]:
        parts.append(
            f'<path d="M{-HANDLE_W_TOP / 2 + 28},{HANDLE_TOP + 44} L{-HANDLE_W_BOTTOM / 2 + 26},{HANDLE_END - 120}" '
            f'stroke="#FFFFFF" stroke-opacity="{p["shine"]}" stroke-width="18" stroke-linecap="round"/>'
            f'<path d="{arc(0, HEAD_CY, HEAD_R - 36, 200, 252)}" fill="none" stroke="#FFFFFF" '
            f'stroke-opacity="{p["shine"]}" stroke-width="20" stroke-linecap="round"/>')
    return "".join(parts)


def wand_silhouette():
    return f'<rect {neck_rect()}/><path d="{handle_path()}"/><path d="{head_path()}"/>'


def waves(p, small=False):
    """Vibration arcs either side of the head, square to the wand's axis: it's shaking."""
    radii, opacities, width, sweep = ([205], [1.0], 40, 34) if small else ([200, 262], [0.95, 0.6], 30, 30)
    out = []
    for radius, opacity in zip(radii, opacities):
        for side in (180, 0):
            out.append(f'<path d="{arc(0, WAVE_CY, radius, side - sweep, side + sweep)}" fill="none" '
                       f'stroke="{p["waves"]}" stroke-opacity="{opacity}" stroke-width="{width}" '
                       f'stroke-linecap="round"/>')
    return "".join(out)


def ripples(color, opacity, count=9, first=240, step=92, width=24, fade=0.0):
    """Concentric rings around the head, fainter outward when `fade` > 0."""
    return "".join(
        f'<circle cx="0" cy="{WAVE_CY}" r="{first + k * step}" fill="none" stroke="{color}" '
        f'stroke-opacity="{opacity * (1 - fade * k / count):.4f}" stroke-width="{width}"/>'
        for k in range(1, count + 1))


# MARK: - Icon


def icon_svg(p, small=False, uid="icon"):
    """The app icon: the wand and its vibration on the tile, with transparent margins.

    `small` is the 16 and 32px drawing: no ripples, ridges or button, and one thicker arc a side.
    """
    tile = squircle((CANVAS - TILE) / 2, (CANVAS - TILE) / 2, TILE, TILE_RADIUS)
    place = placement(**WAND_PLACEMENT)
    shadow_color, shadow_opacity = p["shadow"]
    texture = "" if small else ripples(*p["ripple"])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" \
width="{CANVAS}" height="{CANVAS}">
  <defs>
    <linearGradient id="{uid}-tile" x1="0.18" y1="0" x2="0.82" y2="1">{stops(p["tile"])}</linearGradient>
    {wand_defs(p, uid)}
    <clipPath id="{uid}-clip"><path d="{tile}"/></clipPath>
    <filter id="{uid}-blur" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="{10 if small else 18}"/>
    </filter>
  </defs>
  <path d="{tile}" fill="url(#{uid}-tile)"/>
  <g clip-path="url(#{uid}-clip)">
    <g transform="{place}">{texture}{waves(p, small)}</g>
    <g transform="translate(0 {16 if small else 22})" opacity="{shadow_opacity}" filter="url(#{uid}-blur)">
      <g transform="{place}" fill="{shadow_color}">{wand_silhouette()}</g>
    </g>
    <g transform="{place}">{wand(p, uid, small)}</g>
  </g>
</svg>
'''


def icon_layers(p):
    """Full-bleed, unmasked layers for Icon Composer, which applies the shape and the glass."""
    grow = f"translate(512 512) scale({CANVAS / TILE:.5f}) translate(-512 -512) {placement(**WAND_PLACEMENT)}"

    def layer(body, defs=""):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
                f'width="{CANVAS}" height="{CANVAS}"><defs>{defs}</defs>{body}</svg>\n')

    background = layer(
        f'<rect width="{CANVAS}" height="{CANVAS}" fill="url(#bg)"/>'
        f'<g transform="{grow}">{ripples(*p["ripple"])}</g>',
        f'<linearGradient id="bg" x1="0.18" y1="0" x2="0.82" y2="1">{stops(p["tile"])}</linearGradient>')
    return {
        "1-background.svg": background,
        "2-waves.svg": layer(f'<g transform="{grow}">{waves(p)}</g>'),
        "3-wand.svg": layer(f'<g transform="{grow}">{wand(p, "layer")}</g>', wand_defs(p, "layer")),
    }


# MARK: - Wallpapers

# "vibeshed" set in Outfit SemiBold, and "space" in Outfit Medium (both SIL Open Font License,
# github.com/Outfitio/Outfit-Fonts), outlined at 100px with the baseline at y=0 so rendering
# needs no fonts. Widths are of the ink, not the advance.
WORDMARK_WIDTH, WORDMARK_X_HEIGHT = 397.7, 48.3
WORDMARK = (
    "M21.5 0 0.2-48.3H14.6L26.4-17.7L38.2-48.3H52.1L30.9 0ZM58.1 0V-48.3H71.3V0ZM64.7-56.1Q61.5-56.1 59.4-58.2"
    "Q57.3-60.4 57.3-63.6Q57.3-66.7 59.4-68.9Q61.5-71.1 64.7-71.1Q68-71.1 70.1-68.9Q72.1-66.7 72.1-63.6"
    "Q72.1-60.4 70.1-58.2Q68-56.1 64.7-56.1ZM109.7 1Q104.5 1 100.3-1.2Q97.8-2.5 95.9-4.4V0H82.9V-72.3H96V-44.1"
    "Q97.9-46 100.4-47.2Q104.6-49.3 109.7-49.3Q116.4-49.3 121.7-46Q127-42.7 130.1-37Q133.1-31.3 133.1-24.1"
    "Q133.1-17 130.1-11.3Q127-5.6 121.7-2.3Q116.4 1 109.7 1ZM107.5-11.1Q111.1-11.1 113.9-12.8"
    "Q116.6-14.4 118.2-17.4Q119.7-20.3 119.7-24.2Q119.7-28 118.2-30.9Q116.6-33.9 113.8-35.5Q111-37.2 107.4-37.2"
    "Q103.8-37.2 101.1-35.5Q98.3-33.9 96.8-30.9Q95.2-28 95.2-24.2Q95.2-20.3 96.8-17.4Q98.3-14.4 101.1-12.8"
    "Q103.9-11.1 107.5-11.1ZM164.8 1Q157.2 1 151.3-2.2Q145.4-5.5 141.9-11.2Q138.5-16.9 138.5-24.2"
    "Q138.5-31.4 141.9-37.1Q145.2-42.7 151-46.1Q156.8-49.4 163.9-49.4Q170.9-49.4 176.2-46.2Q181.6-43.1 184.7-37.7"
    "Q187.7-32.2 187.7-25.3Q187.7-24 187.6-22.6Q187.4-21.3 187-19.6L151.7-19.5Q152.1-18 152.8-16.8"
    "Q154.4-13.5 157.5-11.8Q160.6-10 164.7-10Q168.4-10 171.4-11.2Q174.4-12.5 176.6-15L184.3-7.3"
    "Q180.8-3.2 175.8-1.1Q170.7 1 164.8 1ZM151.7-29.3 175.1-29.4Q174.7-31.1 174.1-32.5Q172.7-35.4 170.2-37"
    "Q167.6-38.5 163.9-38.5Q160-38.5 157.1-36.8Q154.2-35 152.7-31.9Q152.1-30.7 151.7-29.3ZM212.4 1.1"
    "Q208.3 1.1 204.4 0Q200.4-1.1 197.1-3Q193.8-5 191.4-7.8L199.2-15.7Q201.7-12.9 205-11.5Q208.3-10.1 212.3-10.1"
    "Q215.5-10.1 217.2-11Q218.8-11.9 218.8-13.7Q218.8-15.7 217.1-16.8Q215.3-17.9 212.5-18.7Q209.7-19.4 206.6-20.4"
    "Q203.6-21.3 200.8-22.9Q198-24.4 196.2-27.2Q194.5-29.9 194.5-34.3Q194.5-38.9 196.8-42.3Q199-45.7 203.2-47.6"
    "Q207.4-49.5 213.1-49.5Q219.1-49.5 223.9-47.4Q228.8-45.3 232-41.1L224.1-33.2Q221.9-35.9 219.2-37.1"
    "Q216.4-38.3 213.2-38.3Q210.3-38.3 208.8-37.4Q207.2-36.5 207.2-34.9Q207.2-33.1 208.9-32.1"
    "Q210.7-31.1 213.5-30.4Q216.3-29.6 219.4-28.7Q222.4-27.7 225.2-26Q227.9-24.3 229.7-21.5Q231.4-18.7 231.4-14.3"
    "Q231.4-7.2 226.3-3Q221.2 1.1 212.4 1.1ZM272.7 0V-27.7Q272.7-32 270-34.7Q267.3-37.4 263-37.4"
    "Q260.2-37.4 258-36.2Q255.8-35 254.6-32.8Q253.3-30.6 253.3-27.7V0H240.2V-72.3H253.3V-43.9Q255-45.6 257.3-46.9"
    "Q261.5-49.3 267-49.3Q272.5-49.3 276.8-46.9Q281-44.5 283.4-40.3Q285.8-36.1 285.8-30.6V0ZM319.5 1"
    "Q311.9 1 306-2.2Q300.1-5.5 296.7-11.2Q293.2-16.9 293.2-24.2Q293.2-31.4 296.6-37.1Q299.9-42.7 305.7-46.1"
    "Q311.5-49.4 318.6-49.4Q325.6-49.4 331-46.2Q336.3-43.1 339.4-37.7Q342.4-32.2 342.4-25.3Q342.4-24 342.2-22.6"
    "Q342.1-21.3 341.7-19.6L306.4-19.5Q306.8-18 307.5-16.8Q309.1-13.5 312.2-11.8Q315.3-10 319.4-10"
    "Q323.1-10 326.1-11.2Q329.1-12.5 331.3-15L339-7.3Q335.5-3.2 330.5-1.1Q325.4 1 319.5 1ZM306.4-29.3 329.8-29.4"
    "Q329.4-31.1 328.8-32.5Q327.4-35.4 324.9-37Q322.3-38.5 318.6-38.5Q314.7-38.5 311.8-36.8Q308.9-35 307.4-31.9"
    "Q306.8-30.7 306.4-29.3ZM370.9 1Q364.2 1 358.9-2.3Q353.6-5.6 350.6-11.3Q347.5-17 347.5-24.1"
    "Q347.5-31.3 350.6-37Q353.6-42.7 358.9-46Q364.1-49.3 370.9-49.3Q376.1-49.3 380.3-47.2Q382.7-46 384.6-44.1"
    "V-72.3H397.7V0H384.7V-4.4Q382.8-2.5 380.3-1.2Q376.1 1 370.9 1ZM373.1-11.1Q376.8-11.1 379.6-12.8"
    "Q382.3-14.4 383.9-17.4Q385.4-20.3 385.4-24.2Q385.4-28 383.9-30.9Q382.3-33.9 379.6-35.5Q376.8-37.2 373.2-37.2"
    "Q369.5-37.2 366.8-35.5Q364-33.8 362.5-30.9Q360.9-28 360.9-24.2Q360.9-20.3 362.5-17.4Q364-14.4 366.8-12.8"
    "Q369.6-11.1 373.1-11.1Z"
)
SPACE_WIDTH, SPACE_X_HEIGHT = 257.4, 48.0
SPACE = (
    "M21.8 1Q17.8 1 14.1-0.1Q10.4-1.1 7.3-3Q4.2-5 1.9-7.8L8.9-14.8Q11.4-11.9 14.7-10.4Q17.9-9 22-9"
    "Q25.7-9 27.6-10.1Q29.5-11.2 29.5-13.3Q29.5-15.5 27.7-16.7Q25.9-17.9 23.1-18.8Q20.2-19.6 17.1-20.5"
    "Q13.9-21.4 11.1-23Q8.2-24.5 6.4-27.2Q4.6-29.9 4.6-34.2Q4.6-38.8 6.8-42.1Q8.9-45.4 12.9-47.2Q16.8-49 22.3-49"
    "Q28.1-49 32.5-47Q37-44.9 40-40.8L33-33.8Q30.9-36.4 28.2-37.7Q25.5-39 22-39Q18.7-39 16.9-38Q15.1-37 15.1-35.1"
    "Q15.1-33.1 16.9-32Q18.7-30.9 21.6-30.1Q24.4-29.3 27.6-28.4Q30.7-27.4 33.5-25.8Q36.4-24.1 38.2-21.4"
    "Q40-18.6 40-14.2Q40-7.2 35.1-3.1Q30.2 1 21.8 1ZM74.8 1Q69.3 1 65-1.4Q62.1-2.9 60.1-5.2V20H49.1V-48H60.1"
    "V-42.7Q62.2-45.1 65.1-46.7Q69.4-49 74.8-49Q81.3-49 86.6-45.7Q91.8-42.3 94.9-36.7Q97.9-31 97.9-23.9"
    "Q97.9-16.9 94.9-11.3Q91.8-5.6 86.6-2.3Q81.3 1 74.8 1ZM73-9.4Q77-9.4 80-11.2Q83.1-13.1 84.8-16.4"
    "Q86.6-19.7 86.6-24Q86.6-28.3 84.8-31.6Q83.1-34.9 80-36.8Q77-38.6 73-38.6Q69-38.6 65.9-36.8"
    "Q62.8-34.9 61.1-31.6Q59.4-28.3 59.4-24Q59.4-19.7 61.1-16.4Q62.8-13.1 65.9-11.2Q69-9.4 73-9.4ZM127.2 1"
    "Q120.7 1 115.5-2.3Q110.2-5.6 107.2-11.3Q104.1-16.9 104.1-23.9Q104.1-31 107.2-36.7Q110.2-42.3 115.5-45.7"
    "Q120.7-49 127.2-49Q132.7-49 137-46.7Q139.8-45.1 141.9-42.7V-48H152.9V0H141.9V-5.2Q139.9-2.9 137-1.4"
    "Q132.7 1 127.2 1ZM129-9.4Q135.1-9.4 138.8-13.5Q142.6-17.6 142.6-24Q142.6-28.3 140.9-31.6"
    "Q139.2-34.9 136.1-36.8Q133.1-38.6 129-38.6Q125-38.6 122-36.8Q118.9-34.9 117.2-31.6Q115.4-28.3 115.4-24"
    "Q115.4-19.7 117.2-16.4Q118.9-13.1 122-11.2Q125-9.4 129-9.4ZM187.2 1Q180.1 1 174.3-2.3Q168.6-5.6 165.3-11.3"
    "Q162-17 162-24Q162-31.1 165.3-36.8Q168.6-42.4 174.3-45.7Q180.1-49 187.2-49Q192.8-49 197.7-46.9"
    "Q202.5-44.7 205.9-40.7L198.7-33.4Q196.6-35.9 193.6-37.2Q190.7-38.4 187.2-38.4Q183.1-38.4 179.9-36.6"
    "Q176.8-34.7 175.1-31.5Q173.3-28.3 173.3-24Q173.3-19.8 175.1-16.6Q176.8-13.3 179.9-11.5Q183.1-9.6 187.2-9.6"
    "Q190.7-9.6 193.6-10.9Q196.6-12.1 198.7-14.6L205.9-7.3Q202.5-3.3 197.7-1.2Q192.8 1 187.2 1ZM235.1 1"
    "Q227.9 1 222.2-2.2Q216.4-5.5 213.1-11.2Q209.7-16.9 209.7-24Q209.7-31.1 213-36.8Q216.3-42.4 222-45.7"
    "Q227.6-49 234.5-49Q241.2-49 246.4-45.9Q251.5-42.8 254.5-37.4Q257.4-32 257.4-25.1Q257.4-23.9 257.2-22.7"
    "Q257.1-21.4 256.8-19.9H221Q221.4-18 222.3-16.4Q224.1-13 227.4-11.2Q230.7-9.3 235-9.3Q238.7-9.3 241.9-10.6"
    "Q245-11.9 247.2-14.4L254.2-7.3Q250.7-3.2 245.7-1.1Q240.7 1 235.1 1ZM221-28.9H246.6Q246.1-31 245.3-32.7"
    "Q243.8-35.7 241.1-37.3Q238.3-38.9 234.3-38.9Q230.1-38.9 227-37.1Q223.9-35.3 222.2-32.1Q221.4-30.6 221-28.9Z"
)

# Wallpaper sizes: Studio Display / iMac (16:9) and MacBook Pro (about 3:2 once the notch is in).
WALLPAPER_SIZES = {"5k": (5120, 2880), "macbook": (3456, 2234)}


def wordmark(x, baseline, x_height, color):
    """The wordmark at the given x-height, its left edge at x."""
    scale = x_height / WORDMARK_X_HEIGHT
    return f'<path transform="translate({x:.1f} {baseline:.1f}) scale({scale:.4f})" d="{WORDMARK}" fill="{color}"/>'


def option_key(x, y, size, color, width):
    """The ⌥ symbol, stroked, `size` wide."""
    return (f'<g transform="translate({x:.1f} {y:.1f})" fill="none" stroke="{color}" stroke-width="{width:.1f}" '
            f'stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="M0,0 H{size * 0.32:.1f} L{size * 0.72:.1f},{size * 0.78:.1f} H{size:.1f}"/>'
            f'<path d="M{size * 0.58:.1f},0 H{size:.1f}"/></g>')


def _hotkey_metrics(unit):
    """(padding, gap between keys, label x-height, ⌥ key width, space key width) for keys `unit` tall."""
    pad, gap, text_h = unit * 0.34, unit * 0.28, unit * 0.36
    return pad, gap, text_h, unit, SPACE_WIDTH * text_h / SPACE_X_HEIGHT + pad * 2


def hotkey_width(unit):
    _, gap, _, option_w, space_w = _hotkey_metrics(unit)
    return option_w + gap + space_w


def hotkey(x, y, unit, color, opacity):
    """Keycaps for the default picker shortcut, ⌥ space, `unit` tall, top-left at (x, y)."""
    pad, gap, text_h, option_w, space_w = _hotkey_metrics(unit)
    stroke = unit * 0.045
    keys = (
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{option_w:.1f}" height="{unit:.1f}" rx="{unit * 0.22:.1f}"/>'
        f'<rect x="{x + option_w + gap:.1f}" y="{y:.1f}" width="{space_w:.1f}" height="{unit:.1f}" '
        f'rx="{unit * 0.22:.1f}"/>')
    glyph = unit * 0.42
    return (f'<g opacity="{opacity}"><g fill="none" stroke="{color}" stroke-width="{stroke:.1f}">{keys}</g>'
            f'{option_key(x + (option_w - glyph) / 2, y + (unit - glyph * 0.78) / 2, glyph, color, stroke * 1.15)}'
            f'<path transform="translate({x + option_w + gap + pad - 1.9 * text_h / SPACE_X_HEIGHT:.1f} '
            f'{y + unit / 2 + text_h / 2:.1f}) '
            f'scale({text_h / SPACE_X_HEIGHT:.4f})" d="{SPACE}" fill="{color}"/></g>')


def dither(width, height, amount):
    """Zero-mean noise added to every pixel, so long, slow gradients don't band once they're 8-bit."""
    return (f'<filter id="dither" filterUnits="userSpaceOnUse" x="0" y="0" width="{width}" height="{height}">'
            f'<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="1" seed="7" result="noise"/>'
            f'<feColorMatrix in="noise" type="matrix" values="1 0 0 0 0  1 0 0 0 0  1 0 0 0 0  0 0 0 0 1" '
            f'result="gray"/>'
            f'<feComposite in="SourceGraphic" in2="gray" operator="arithmetic" k1="0" k2="1" k3="{amount}" '
            f'k4="{-amount / 2}"/></filter>')


def wallpaper_svg(p, style, width, height):
    """`sunset`: the wand, big, in its vibration; `midnight`: the icon on a dark stage; `pattern`: wands."""
    return {"sunset": _sunset, "midnight": _midnight, "pattern": _pattern}[style](p, width, height)


def _frame(width, height, defs, body, dither_amount=0.006):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" '
            f'height="{height}"><defs>{defs}{dither(width, height, dither_amount)}</defs>'
            f'<g filter="url(#dither)">{body}</g></svg>\n')


def _sunset(p, width, height):
    unit = height / 1000  # layout in thousandths of the height so every size matches
    scale = unit * 0.8
    head = (width - 470 * unit, 600 * unit)  # low enough that the raised handle clears the menu bar
    place = placement(scale, head, WAVE_CY)
    left = 150 * unit
    return _frame(
        width, height,
        f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">{stops(p["tile"])}</linearGradient>'
        f'<radialGradient id="sun" cx="{head[0]:.0f}" cy="{head[1]:.0f}" r="{700 * unit:.0f}" '
        f'gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFE3A3" stop-opacity="0.55"/>'
        f'<stop offset="1" stop-color="#FFE3A3" stop-opacity="0"/></radialGradient>'
        f'{wand_defs(p, "wp")}'
        f'<filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">'
        f'<feGaussianBlur stdDeviation="{24 * scale:.1f}"/></filter>',
        f'<rect width="{width}" height="{height}" fill="url(#bg)"/>'
        f'<rect width="{width}" height="{height}" fill="url(#sun)"/>'
        f'<g transform="{place}">{ripples("#FFFFFF", 0.09, count=26, first=320, step=150, width=26, fade=0.85)}'
        f'{waves(p)}</g>'
        f'<g transform="translate(0 {26 * scale:.1f})" opacity="0.32" filter="url(#shadow)">'
        f'<g transform="{place}" fill="#9E0F45">{wand_silhouette()}</g></g>'
        f'<g transform="{place}">{wand(p, "wp")}</g>'
        f'{wordmark(left, 600 * unit, 62 * unit, "#FFFFFF")}'
        f'{hotkey(left + 4 * unit, 660 * unit, 64 * unit, "#FFFFFF", 0.85)}',
    )


def _midnight(p, width, height):
    unit = height / 1000
    size = 300 * unit
    cx, cy = width / 2, 405 * unit
    icon_scale = size / TILE
    tx, ty = cx - CANVAS / 2 * icon_scale, cy - CANVAS / 2 * icon_scale
    icon = icon_svg(p, uid="wp")
    inner = icon[icon.index("<defs>"):icon.rindex("</svg>")]
    mark_h = 46 * unit
    mark_w = WORDMARK_WIDTH * mark_h / WORDMARK_X_HEIGHT
    key_unit = 52 * unit
    return _frame(
        width, height,
        f'<radialGradient id="stage" cx="{cx:.0f}" cy="{cy:.0f}" r="{width * 0.42:.0f}" '
        f'gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#4A1A5C"/>'
        f'<stop offset="0.5" stop-color="#21102E"/><stop offset="1" stop-color="#110A1C"/></radialGradient>'
        f'<radialGradient id="glow" cx="{cx:.0f}" cy="{cy + 40 * unit:.0f}" r="{330 * unit:.0f}" '
        f'gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FF4F7B" stop-opacity="0.5"/>'
        f'<stop offset="0.55" stop-color="#FF6F61" stop-opacity="0.16"/>'
        f'<stop offset="1" stop-color="#FF6F61" stop-opacity="0"/></radialGradient>',
        f'<rect width="{width}" height="{height}" fill="url(#stage)"/>'
        f'<g transform="translate({cx:.1f} {cy:.1f})">'
        + "".join(f'<circle r="{(200 + k * 95) * unit:.1f}" fill="none" stroke="#FF7C6A" '
                  f'stroke-opacity="{0.10 * (1 - k / 16):.3f}" stroke-width="{7 * unit:.1f}"/>'
                  for k in range(1, 16))
        + f'</g><rect width="{width}" height="{height}" fill="url(#glow)"/>'
        f'<g transform="translate({tx:.1f} {ty:.1f}) scale({icon_scale:.5f})">{inner}</g>'
        f'{wordmark(cx - mark_w / 2, 680 * unit, mark_h, "#FFF1E8")}'
        f'{hotkey(cx - hotkey_width(key_unit) / 2, 735 * unit, key_unit, "#FFB49A", 0.75)}',
        dither_amount=0.01,
    )


def _pattern(p, width, height):
    unit = height / 1000
    cell = 240 * unit
    scale = cell / 1250
    rows = int(height / (cell * 0.866)) + 3
    cols = int(width / cell) + 3
    accents = ["#FFB4A4", "#FFA3BC", "#FFCB94"]  # the tile's three colors, washed out
    tiles = []
    for row in range(rows):
        for col in range(cols):
            x = col * cell + (cell / 2 if row % 2 else 0) - cell / 2
            y = row * cell * 0.866 - cell / 2
            color = accents[(row + 2 * col) % len(accents)]
            body = (f'<g fill="{color}">{wand_silhouette()}</g>'
                    + waves({"waves": color}, small=True))
            tiles.append(f'<g transform="{placement(scale, (x, y), WAVE_CY + 120)}">{body}</g>')
    return _frame(
        width, height,
        '<linearGradient id="paper" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF7EF"/>'
        '<stop offset="1" stop-color="#FFE9DA"/></linearGradient>',
        f'<rect width="{width}" height="{height}" fill="url(#paper)"/>{"".join(tiles)}',
        dither_amount=0.004,
    )


# MARK: - Rendering


def render(svg, out, width, height=None):
    if not shutil.which("rsvg-convert"):
        sys.exit("rsvg-convert not found: brew install librsvg")
    subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(height or width), "-o", str(out)],
                   input=svg.encode(), check=True)


def to_jpeg(png, jpg, quality=90):
    """PNG to JPEG with ImageMagick or sips; returns the path written (the PNG if neither exists).

    ImageMagick comes first: at the same quality sips writes files about twice the size.
    """
    if shutil.which("magick") or shutil.which("convert"):
        cmd = [shutil.which("magick") or shutil.which("convert"), str(png), "-quality", str(quality), str(jpg)]
    elif shutil.which("sips"):
        cmd = ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(quality), str(png),
               "--out", str(jpg)]
    else:
        return png
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    png.unlink()
    return jpg


# MARK: - ICNS

# What iconutil writes for a full .iconset: (type, pixels, use the simplified drawing).
ICNS_ENTRIES = [
    ("ic04", 16, True),  # 16pt, ARGB
    ("ic05", 32, True),  # 32pt, ARGB
    ("ic11", 32, True),  # 16pt @2x
    ("ic12", 64, False),  # 32pt @2x
    ("ic07", 128, False),
    ("ic13", 256, False),  # 128pt @2x
    ("ic08", 256, False),
    ("ic14", 512, False),  # 256pt @2x
    ("ic09", 512, False),
    ("ic10", 1024, False),  # 512pt @2x
]


def read_png_rgba(data):
    """Pixels of an 8-bit, non-interlaced RGBA PNG (what rsvg-convert writes)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert (depth, color, interlace) == (8, 6, 0), "expected 8-bit RGBA"
        elif kind == b"IDAT":
            idat += chunk
        pos += length + 12
    raw, stride = zlib.decompress(idat), width * 4
    pixels, prev = bytearray(), bytearray(stride)
    for row in range(height):
        start = row * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up, up_left = prev[i], (prev[i - 4] if i >= 4 else 0)
            if kind == 1:
                line[i] = (line[i] + left) & 0xFF
            elif kind == 2:
                line[i] = (line[i] + up) & 0xFF
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif kind == 4:
                guess = left + up - up_left
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - up_left)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else up_left)) & 0xFF
        pixels += line
        prev = line
    return width, height, bytes(pixels)


def icns_rle(channel):
    """The .icns run-length coding: 0x00-0x7F copies n+1 bytes, 0x80-0xFF repeats one n-125 times."""
    out, literal, i = bytearray(), bytearray(), 0

    def flush():
        for at in range(0, len(literal), 128):
            out.append(len(literal[at:at + 128]) - 1)
            out.extend(literal[at:at + 128])
        literal.clear()

    while i < len(channel):
        run = 1
        while i + run < len(channel) and run < 130 and channel[i + run] == channel[i]:
            run += 1
        if run >= 3:
            flush()
            out.extend((0x80 + run - 3, channel[i]))
        else:
            literal.extend(channel[i:i + run])
        i += run
    flush()
    return bytes(out)


def argb_entry(png):
    """An ic04/ic05 payload: 'ARGB', then the A, R, G and B planes, each run-length coded."""
    _, _, rgba = read_png_rgba(png)
    return b"ARGB" + b"".join(icns_rle(rgba[offset::4]) for offset in (3, 0, 1, 2))


def write_icns(path, entries):
    body = b"".join(kind.encode() + struct.pack(">I", len(data) + 8) + data for kind, data in entries)
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


# MARK: - Main


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--palette", default="sunset", choices=sorted(PALETTES))
    parser.add_argument("--wallpapers", action="store_true", help="also render docs/wallpapers")
    parser.add_argument("--layers", metavar="DIR", type=Path, help="write Icon Composer layers to DIR")
    args = parser.parse_args()
    palette = PALETTES[args.palette]

    master = icon_svg(palette)
    (ROOT / "Resources/AppIcon.svg").write_text(master)
    render(master, ROOT / "Resources/AppIcon.png", 1024)
    render(master, ROOT / "docs/icon.png", 512)
    print("Wrote Resources/AppIcon.svg, Resources/AppIcon.png, docs/icon.png")

    small = icon_svg(palette, small=True)
    with tempfile.TemporaryDirectory() as tmp:
        entries = []
        for kind, pixels, simplified in ICNS_ENTRIES:
            png = Path(tmp) / f"{kind}.png"
            render(small if simplified else master, png, pixels)
            data = png.read_bytes()
            entries.append((kind, argb_entry(data) if kind in ("ic04", "ic05") else data))
        write_icns(ROOT / "Resources/AppIcon.icns", entries)
    print("Wrote Resources/AppIcon.icns")

    if args.layers:
        args.layers.mkdir(parents=True, exist_ok=True)
        for name, svg in icon_layers(palette).items():
            (args.layers / name).write_text(svg)
        print(f"Wrote Icon Composer layers to {args.layers}")

    if args.wallpapers:
        out_dir = ROOT / "docs/wallpapers"
        out_dir.mkdir(parents=True, exist_ok=True)
        for style in ("sunset", "midnight", "pattern"):
            for name, (width, height) in WALLPAPER_SIZES.items():
                png = out_dir / f"vibeshed-{style}-{name}.png"
                render(wallpaper_svg(palette, style, width, height), png, width, height)
                written = to_jpeg(png, png.with_suffix(".jpg"))
                print(f"Wrote {written.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
