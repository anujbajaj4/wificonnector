#!/usr/bin/env python3
"""Draws the WiFiConnector app icon and writes the AppIcon asset catalog.

Follows Apple's macOS icon grid: an 824-pixel rounded square centered on a
1024 canvas, with a soft shadow below it. Drawn at 2x and scaled down so the
edges stay smooth. The file names double as an .iconset, so app/build-app.sh
can turn them into an .icns with iconutil.

    python3 -m pip install pillow
    python3 app/tools/make_icon.py
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BLUE_TOP = (43, 140, 255)
BLUE_BOTTOM = (10, 108, 232)
WHITE = (255, 255, 255, 255)

OUT = Path(__file__).resolve().parent.parent / "WiFiConnector" / "Assets.xcassets"
SIZES = [16, 32, 128, 256, 512]


def draw_master(scale: int = 2) -> Image.Image:
    size = 1024 * scale
    s = lambda v: round(v * scale)  # noqa: E731
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # The tile: Apple's grid puts it at 100..924 with a ~185 corner radius.
    box = (s(100), s(100), s(924), s(924))
    radius = s(185)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)

    # Soft shadow under the tile.
    shadow = Image.new("RGBA", (size, size), (16, 24, 48, 0))
    shadow.putalpha(mask.point(lambda a: a * 0.35))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -s(12)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(18)))
    canvas.alpha_composite(shadow)

    # Vertical blue gradient, clipped to the tile.
    gradient = Image.new("RGBA", (size, size))
    gdraw = ImageDraw.Draw(gradient)
    top, bottom = box[1], box[3]
    for y in range(size):
        t = min(max((y - top) / (bottom - top), 0), 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(BLUE_TOP, BLUE_BOTTOM))
        gdraw.line([(0, y), (size, y)], fill=color + (255,))
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile.paste(gradient, (0, 0), mask)

    # A faint highlight along the top edge, as on Apple's own icons.
    highlight = Image.new("L", (size, size), 0)
    ImageDraw.Draw(highlight).rounded_rectangle(
        (box[0] + s(6), box[1] + s(6), box[2] - s(6), box[1] + s(330)), radius=radius - s(6), fill=36
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(s(40)))
    white_layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    white_layer.putalpha(Image.composite(highlight, Image.new("L", (size, size), 0), mask))
    tile.alpha_composite(white_layer)
    canvas.alpha_composite(tile)

    # The Wi-Fi mark: two arcs and a dot, with round ends.
    draw = ImageDraw.Draw(canvas)
    cx, cy = s(512), s(660)
    width = s(64)
    for r in (s(300), s(188)):
        bbox = (cx - r - width / 2, cy - r - width / 2, cx + r + width / 2, cy + r + width / 2)
        draw.arc(bbox, start=225, end=315, fill=WHITE, width=width)
        for angle in (225, 315):
            x = cx + r * math.cos(math.radians(angle))
            y = cy + r * math.sin(math.radians(angle))
            draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=WHITE)
    dot = s(50)
    draw.ellipse((cx - dot, cy - dot, cx + dot, cy + dot), fill=WHITE)
    return canvas


def main() -> None:
    master = draw_master()
    iconset = OUT / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    images = []
    for size in SIZES:
        for factor in (1, 2):
            name = f"icon_{size}x{size}{'@2x' if factor == 2 else ''}.png"
            master.resize((size * factor, size * factor), Image.LANCZOS).save(iconset / name)
            images.append({"idiom": "mac", "size": f"{size}x{size}", "scale": f"{factor}x", "filename": name})
    info = {"author": "xcode", "version": 1}
    (iconset / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
    (OUT / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    master.resize((1024, 1024), Image.LANCZOS).save(Path(__file__).resolve().parent / "icon-preview.png")
    print(f"Wrote {len(images)} images to {iconset}")


if __name__ == "__main__":
    main()
