#!/usr/bin/env python3
"""Generates the website's data from the source, so the page never drifts from the app:
  docs/themes.json   every built-in palette (for the theme chips and press-T), plus counts
  docs/index.html    the numbers in elements marked data-stat="modules|themes|wallpapers|fonts"

Counts come from:
  themes      Vibeshed/Modules/Theme/BuiltInThemes*.swift (one ThemeDefinition each)
  wallpapers  the cases of WallpaperStyle
  fonts       FontCatalog.curated
  modules     the Modules table in README.md

Run from the repo root:  python3 scripts/generate-site-data.py
"""

import glob
import json
import re

THEME_DIR = "Vibeshed/Modules/Theme"
INDEX = "docs/index.html"
OUT = "docs/themes.json"

# The six hues the page draws swatches from, in terminal order.
HUES = ["red", "yellow", "green", "blue", "magenta", "cyan"]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def pairs(text):
    return dict(re.findall(r'"(\w+)":\s*"(#[0-9a-fA-F]{6})"', text))


def block_at(text, start):
    """The text from `start` to its matching closing bracket (start is at an opening one)."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] in "([":
            depth += 1
        elif text[i] in ")]":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise ValueError("unbalanced brackets")


def themes():
    found = []
    for path in sorted(glob.glob(f"{THEME_DIR}/BuiltInThemes*.swift")):
        text = read(path)
        # Shared color dictionaries, e.g. `private static let macHues: [String: String] = [ … ]`.
        shared = {}
        for m in re.finditer(r"static let (\w+): \[String: String\] = ", text):
            shared[m.group(1)] = pairs(block_at(text, m.end()))
        for m in re.finditer(r"static let \w+ = ThemeDefinition\(", text):
            body = block_at(text, m.end() - 1)
            name = re.search(r'name:\s*"([^"]+)"', body).group(1)
            mode = re.search(r"mode:\s*\.(\w+)", body).group(1)
            colors_at = body.index("colors:")
            base = re.match(r"colors:\s*(\w+)\.merging", body[colors_at:])
            colors = dict(shared[base.group(1)]) if base else {}
            colors.update(pairs(body[colors_at:]))
            found.append((name, mode, colors))
    return found


def theme_entry(name, mode, c):
    entry = {
        "name": name,
        "mode": mode,
        "bg": c["background"],
        "fg": c["foreground"],
        "accent": c["accent"],
        "muted": c.get("muted", c.get("color8", c["foreground"])),
        "hues": [c[h] for h in HUES],
    }
    if "selection_background" in c:
        entry["sel"] = c["selection_background"]
    return entry


def count_wallpapers():
    text = read(f"{THEME_DIR}/Wallpaper/WallpaperStyle.swift")
    enum = text[text.index("enum WallpaperStyle") : text.index("static let automatic")]
    return sum(len(line.split("case", 1)[1].split(",")) for line in enum.splitlines() if line.strip().startswith("case "))


def count_fonts():
    text = read(f"{THEME_DIR}/Font/FontCatalog.swift")
    start = text.index("static let curated")
    curated = block_at(text, text.index("[", text.index("=", start)))
    return len(re.findall(r"^\s+(?:FontDefinition\(|monaspace\()", curated, re.M))


def count_modules():
    readme = read("README.md")
    table = readme.split("\n## Modules\n", 1)[1].split("\n## ", 1)[0]
    return len(re.findall(r"^\| \*\*", table, re.M))


def main():
    found = themes()
    # Alphabetical, like BuiltInThemes.all (localizedStandardCompare is close enough to casefold here).
    found.sort(key=lambda t: t[0].casefold())
    stats = {
        "modules": count_modules(),
        "themes": len(found),
        "wallpapers": count_wallpapers(),
        "fonts": count_fonts(),
    }
    data = {"stats": stats, "themes": [theme_entry(*t) for t in found]}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")

    html = read(INDEX)
    for key, value in stats.items():
        html = re.sub(rf'(data-stat="{key}"[^>]*>)[^<]*(<)', rf"\g<1>{value}\g<2>", html)
    with open(INDEX, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"{OUT}: {len(found)} themes; stats {stats}")


if __name__ == "__main__":
    main()
