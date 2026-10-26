#!/usr/bin/env python3
"""Render Fixa's app icon (1024x1024): a birch-white screwdriver on Falu red.

The screwdriver lies diagonally (handle bottom-left, flat-blade tip top-right):
a capsule handle with three cut-out grip flutes, a short ferrule, a slim shaft.
Writes light, dark and tinted appearances into
Fixa/Resources/Assets.xcassets/AppIcon.appiconset/. Requires Pillow.
Usage: python3 scripts/make-icon.py
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling factor
W = SIZE * SS
OUT = Path(__file__).resolve().parent.parent / "Fixa/Resources/Assets.xcassets/AppIcon.appiconset"

FALU_LIGHT = (184, 64, 56)
FALU_DEEP = (142, 39, 35)
BIRCH = (246, 242, 234)
BIRCH_SOFT = (236, 232, 225)
FALU_NIGHT = (224, 103, 95)
NIGHT = (22, 25, 28)
NIGHT_TOP = (40, 46, 52)


def s(v: float) -> int:
    """Design units (on a 1024 grid) to supersampled pixels."""
    return int(round(v * SS))


def vertical_gradient(top, bottom):
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((W, W), Image.BICUBIC)


def soft_highlight(color, strength):
    """The one highlight: a soft light from the top of the tile."""
    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((s(512 - 560), s(120 - 560), s(512 + 560), s(120 + 560)), fill=int(255 * strength))
    mask = mask.filter(ImageFilter.GaussianBlur(s(250)))
    layer = Image.new("RGBA", (W, W), color + (0,))
    layer.putalpha(mask)
    return layer


def screwdriver_masks():
    """Upright screwdriver (tip up) on the 1024 grid → (body, ferrule) masks, rotated 45° and centred."""
    body = Image.new("L", (W, W), 0)
    ferrule = Image.new("L", (W, W), 0)
    b = ImageDraw.Draw(body)
    f = ImageDraw.Draw(ferrule)
    cx = 512
    top, bottom = 118, 900           # 782 units long → ~19–21% margins after rotation
    shaft_half = 23
    # Flat-blade tip: a short squared spade, tapering symmetrically into the shaft.
    blade_half = 31
    b.rounded_rectangle((s(cx - blade_half), s(top), s(cx + blade_half), s(top + 56)), radius=s(5), fill=255)
    b.polygon([(s(cx - blade_half), s(top + 50)), (s(cx + blade_half), s(top + 50)),
               (s(cx + shaft_half), s(top + 100)), (s(cx - shaft_half), s(top + 100))], fill=255)
    # Shaft, running into the handle so the silhouette stays one piece.
    b.rectangle((s(cx - shaft_half), s(top + 96), s(cx + shaft_half), s(620)), fill=255)
    # Ferrule / collar.
    f.rounded_rectangle((s(cx - 46), s(494), s(cx + 46), s(546)), radius=s(14), fill=255)
    # Handle: capsule, separated from the ferrule by a thin gap.
    hw = 100
    b.rounded_rectangle((s(cx - hw), s(560), s(cx + hw), s(bottom)), radius=s(hw), fill=255)
    # Three grip flutes cut out along the handle.
    for dx in (-46, 0, 46):
        b.rounded_rectangle((s(cx + dx - 12), s(640), s(cx + dx + 12), s(790)), radius=s(12), fill=0)

    # Rotate so the tip points top-right (PIL rotates counter-clockwise → negative angle).
    body = body.rotate(-45, resample=Image.BICUBIC, center=(W / 2, W / 2))
    ferrule = ferrule.rotate(-45, resample=Image.BICUBIC, center=(W / 2, W / 2))

    # Centre by visual mass: mostly bounding-box centre, nudged 30% toward the area centroid.
    union = ImageChops.lighter(body, ferrule)
    x0, y0, x1, y1 = union.getbbox()
    small = union.resize((256, 256), Image.BOX)
    total = sx = sy = 0
    for i, v in enumerate(small.tobytes()):
        if v:
            total += v
            sx += (i % 256) * v
            sy += (i // 256) * v
    scale = W / 256
    mass = ((sx / total + 0.5) * scale, (sy / total + 0.5) * scale)
    box = ((x0 + x1) / 2, (y0 + y1) / 2)
    target = (box[0] * 0.7 + mass[0] * 0.3, box[1] * 0.7 + mass[1] * 0.3)
    dx, dy = int(round(W / 2 - target[0])), int(round(W / 2 - target[1]))
    body = ImageChops.offset(body, dx, dy)
    ferrule = ImageChops.offset(ferrule, dx, dy)
    return body, ferrule


def compose(bg_top, bg_bottom, glow_color, glow_strength, body_color, ferrule_color):
    img = vertical_gradient(bg_top, bg_bottom).convert("RGBA")
    img.alpha_composite(soft_highlight(glow_color, glow_strength))
    body, ferrule = screwdriver_masks()
    for mask, color in ((body, body_color), (ferrule, ferrule_color)):
        layer = Image.new("RGBA", (W, W), color + (255,))
        layer.putalpha(mask)
        img.alpha_composite(layer)
    return img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    light = compose(FALU_LIGHT, FALU_DEEP, (255, 214, 190), 0.22, BIRCH, BIRCH)
    light.save(OUT / "AppIcon.png", optimize=True)

    dark = compose(NIGHT_TOP, NIGHT, FALU_NIGHT, 0.16, BIRCH_SOFT, FALU_NIGHT)
    dark.save(OUT / "AppIcon-Dark.png", optimize=True)

    tinted = compose((24, 24, 24), (0, 0, 0), (255, 255, 255), 0.08, (255, 255, 255), (255, 255, 255))
    tinted.convert("L").save(OUT / "AppIcon-Tinted.png", optimize=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
