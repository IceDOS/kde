#!/usr/bin/env python3
"""Inset an SVG icon's content by rewriting its viewBox.

Tela's symbolic tray icons are drawn edge-to-edge (no internal margin), so under
the Plasma system tray's scaleIconsToFit they render oversized next to padded
neighbours. Expanding the viewBox symmetrically maps a larger user-space region
into the same viewport, shrinking the content and adding a uniform margin —
without touching any paths, <defs>, currentColor, or an <?xml?> prolog.

Usage: pad-icon.py <scale> <src.svg> <dst.svg>
  scale 0.875 -> content occupies 87.5% of the viewport (~1px margin on a 16px canvas).
"""
import re
import sys

scale = float(sys.argv[1])
src, dst = sys.argv[2], sys.argv[3]

svg = open(src, encoding="utf-8").read()
m = re.search(r"<svg\b[^>]*>", svg)
if m is None:
    raise SystemExit(f"no <svg> tag in {src}")
tag = m.group(0)


def attr(name):
    a = re.search(r'\b' + name + r'="([^"]+)"', tag)
    return a.group(1) if a else None


width = float(attr("width") or 16)
height = float(attr("height") or 16)
viewbox = attr("viewBox")
if viewbox:
    vx, vy, vw, vh = (float(x) for x in re.split(r"[ ,]+", viewbox.strip()))
else:
    vx, vy, vw, vh = 0.0, 0.0, width, height

nvw, nvh = vw / scale, vh / scale
nvx, nvy = vx + vw / 2 - nvw / 2, vy + vh / 2 - nvh / 2
new_viewbox = f"{nvx:g} {nvy:g} {nvw:g} {nvh:g}"

if viewbox:
    new_tag = re.sub(r'\bviewBox="[^"]+"', f'viewBox="{new_viewbox}"', tag)
else:
    new_tag = tag[:-1].rstrip() + f' viewBox="{new_viewbox}">'

open(dst, "w", encoding="utf-8").write(svg.replace(tag, new_tag, 1))
