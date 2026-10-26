#!/usr/bin/env python3
"""Draws the website's images from the app icon: the favicons and the
1200x630 preview image that WhatsApp, Instagram and search results show when
someone shares the link.

    python3 -m pip install pillow
    python3 app/tools/make_site_images.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from make_icon import draw_master

SITE = Path(__file__).resolve().parents[2] / "site"

PAPER = (244, 245, 247)
INK = (22, 24, 29)
INK_2 = (85, 91, 103)
BLUE = (10, 122, 255)

BOLD_FONTS = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
REGULAR_FONTS = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def font(candidates, size, bold=False):
    for path in candidates:
        if Path(path).exists():
            # Helvetica.ttc holds several faces; index 1 is Bold.
            index = 1 if bold and path.endswith(".ttc") else 0
            return ImageFont.truetype(path, size, index=index)
    raise SystemExit("No usable font found; add one to the lists above.")


def preview_image(icon: Image.Image) -> Image.Image:
    image = Image.new("RGB", (1200, 630), PAPER)
    draw = ImageDraw.Draw(image)
    tile = icon.resize((340, 340), Image.LANCZOS)
    image.paste(tile, (70, 145), tile)

    title = font(BOLD_FONTS, 74, bold=True)
    body = font(REGULAR_FONTS, 34)
    small = font(BOLD_FONTS, 28, bold=True)
    x = 450
    draw.text((x, 150), "Never log in to", font=title, fill=INK)
    draw.text((x, 236), "VIT Wi-Fi again.", font=title, fill=INK)
    draw.text((x, 352), "Automatic hostel Wi-Fi login for Mac.", font=body, fill=INK_2)
    draw.text((x, 398), "Free and open source.", font=body, fill=INK_2)
    draw.text((x, 470), "anujbajaj4.github.io/wificonnector", font=small, fill=BLUE)
    return image


def main() -> None:
    icon = draw_master().resize((1024, 1024), Image.LANCZOS)
    SITE.mkdir(exist_ok=True)
    icon.resize((32, 32), Image.LANCZOS).save(SITE / "favicon.png")
    # iOS and macOS use this for home-screen and pinned-tab icons; it has no
    # transparency, so the icon sits on the page's paper colour.
    touch = Image.new("RGB", (180, 180), PAPER)
    small_icon = icon.resize((180, 180), Image.LANCZOS)
    touch.paste(small_icon, (0, 0), small_icon)
    touch.save(SITE / "apple-touch-icon.png")
    preview_image(icon).save(SITE / "og-image.png", optimize=True)
    print(f"Wrote favicon.png, apple-touch-icon.png and og-image.png to {SITE}")


if __name__ == "__main__":
    main()
