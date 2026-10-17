# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Fixa app icon: two orange-and-cream traffic cones standing on a wooden jetty (brygga) over archipelago blue.
Sticker style like the Fiskben family: flat fills, thick ink outline, one hard unblurred ink offset shadow,
cream highlights, a quiet sea gradient with two ripple rings. No text, nothing thin, so it reads at 60 px.
Writes the 1024 px universal AppIcon plus its dark and tinted appearances and Contents.json.

    uv run scripts/make-icon.py              # ship: AppIcon.png, AppIcon-Dark.png, AppIcon-Tinted.png
    uv run scripts/make-icon.py --alts /tmp/fx   # also render the boat and plaster alternatives for comparison
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersampling
W = SIZE * SS
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Fixa/Resources/Assets.xcassets/AppIcon.appiconset"

# The app's 2 pt outline scaled to the icon: thick enough to survive the 60 px downscale.
OUTLINE = 26
SHADOW = (24, 24)

LIGHT = {
    "sea_top": (0x2E, 0x72, 0xA8),
    "sea_bottom": (0x1F, 0x5A, 0x8A),
    "ripple": (0x4C, 0x8F, 0xC6),
    "ink": (0x1E, 0x21, 0x36),
    "cream": (0xFF, 0xF4, 0xDD),
    "cone": (0xFF, 0x6A, 0x2B),
    "hull": (0xA3, 0x30, 0x24),  # Falu red
    "wood": (0xC9, 0x8B, 0x52),
    "plaster": (0xF2, 0xD3, 0xA8),
}
DARK = {
    **LIGHT,
    "sea_top": (0x1E, 0x2B, 0x38),
    "sea_bottom": (0x15, 0x20, 0x2B),
    "ripple": (0x2F, 0x4A, 0x63),
    "ink": (0x0B, 0x0E, 0x16),
}
# Tinted: grayscale on black; the system recolours by luminance, so objects are light, outlines black.
TINTED = {
    "sea_top": (0x22, 0x22, 0x22),
    "sea_bottom": (0x00, 0x00, 0x00),
    "ripple": (0x3A, 0x3A, 0x3A),
    "ink": (0x00, 0x00, 0x00),
    "cream": (0xFF, 0xFF, 0xFF),
    "cone": (0xB4, 0xB4, 0xB4),
    "hull": (0x78, 0x78, 0x78),
    "wood": (0x8C, 0x8C, 0x8C),
    "plaster": (0xE6, 0xE6, 0xE6),
}

Point = tuple[float, float]


def s(v: float) -> int:
    return round(v * SS)


def sp(points: list[Point]) -> list[tuple[int, int]]:
    return [(s(x), s(y)) for x, y in points]


def rgba(c: tuple[int, int, int]) -> tuple[int, int, int, int]:
    return (*c, 255)


def bezier(p0: Point, c: Point, p1: Point, n: int = 48) -> list[Point]:
    """Quadratic Bezier as a polyline, endpoints included."""
    return [
        ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
         (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
        for t in (i / n for i in range(n + 1))
    ]


def rotate(points: list[Point], origin: Point, degrees: float) -> list[Point]:
    a = math.radians(degrees)
    ox, oy = origin
    return [(ox + (x - ox) * math.cos(a) - (y - oy) * math.sin(a),
             oy + (x - ox) * math.sin(a) + (y - oy) * math.cos(a)) for x, y in points]


def stroke(d: ImageDraw.ImageDraw, points: list[Point], color, width: float = OUTLINE, closed: bool = True) -> None:
    """Ink line with round joints and caps."""
    pts = points + points[:1] if closed else points
    d.line(sp(pts), fill=color, width=s(width), joint="curve")
    r = width / 2
    for x, y in (pts if not closed else points):
        d.ellipse([s(x - r), s(y - r), s(x + r), s(y + r)], fill=color)


def sticker(d: ImageDraw.ImageDraw, points: list[Point], fill, ink) -> None:
    d.polygon(sp(points), fill=fill)
    stroke(d, points, ink)


def background(p: dict) -> Image.Image:
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel((0, y), tuple(round(p["sea_top"][i] * (1 - t) + p["sea_bottom"][i] * t) for i in range(3)))
    return grad.resize((W, W), Image.BICUBIC).convert("RGBA")


def ripples(img: Image.Image, p: dict, cx: float, cy: float, sizes: list[tuple[float, float]]) -> None:
    d = ImageDraw.Draw(img)
    for w, h in sizes:
        d.ellipse([s(cx - w / 2), s(cy - h / 2), s(cx + w / 2), s(cy + h / 2)], outline=rgba(p["ripple"]), width=s(14))


def cone(layer: Image.Image, p: dict, base: Point, height: float, base_w: float, tilt: float,
         stripes=((0.30, 0.46), (0.60, 0.74)), tip_w: float = 64) -> list[Point]:
    """Traffic cone body (no foot) with cream stripes; returns its outline polygon."""
    bx, by = base

    def edge(t: float) -> tuple[Point, Point]:
        w = base_w + (tip_w - base_w) * t
        y = by - height * t
        return (bx - w / 2, y), (bx + w / 2, y)

    tip_l, _ = edge(1)
    cap = [(bx + tip_w / 2 * math.cos(a), tip_l[1] - tip_w / 2 * 0.8 * math.sin(a))
           for a in (math.pi * i / 16 for i in range(17))]
    body = rotate([edge(0)[0], *cap[::-1], edge(0)[1]], base, tilt)

    d = ImageDraw.Draw(layer)
    d.polygon(sp(body), fill=rgba(p["cone"]))
    for t0, t1 in stripes:
        (l0, r0), (l1, r1) = edge(t0), edge(t1)
        d.polygon(sp(rotate([l0, r0, r1, l1], base, tilt)), fill=rgba(p["cream"]))
    stroke(d, body, rgba(p["ink"]))
    return body


def scene_boat(p: dict) -> Image.Image:
    """Alternative: two cones riding in an eka."""
    img = background(p)
    ripples(img, p, 520, 800, [(700, 120), (900, 176)])
    group = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    cone(group, p, base=(374, 660), height=490, base_w=290, tilt=1)
    cone(group, p, base=(666, 652), height=420, base_w=270, tilt=-3)

    d = ImageDraw.Draw(group)
    stern_top, stern_bottom = (176, 588), (244, 770)
    bow_bottom, bow_top = (790, 712), (862, 552)
    keel = bezier(stern_bottom, (520, 860), bow_bottom)
    stem = bezier(bow_bottom, (842, 650), bow_top, 12)
    sheer = bezier(bow_top, (520, 622), stern_top)
    hull = [stern_top, *keel, *stem[1:], *sheer[1:-1]]
    d.polygon(sp(hull), fill=rgba(p["hull"]))
    # One strake line and the cream gunwale rim, both kept inside the hull outline.
    strake = bezier((214, 690), (530, 772), (830, 640), 32)
    d.line(sp(strake), fill=rgba(p["ink"]), width=s(OUTLINE * 0.8), joint="curve")
    rim = bezier((bow_top[0] - 26, bow_top[1] + 22), (520, 652), (stern_top[0] + 14, stern_top[1] + 34), 32)
    d.line(sp(rim), fill=rgba(p["cream"]), width=s(34), joint="curve")
    stroke(d, hull, rgba(p["ink"]))
    # Cream gloss on the stern quarter, between rim and strake.
    d.ellipse([s(246), s(664), s(336), s(692)], fill=rgba(p["cream"]))

    return finish(img, group, p)


def scene_plaster(p: dict) -> Image.Image:
    """Alternative: one big cone with a plaster across it, standing in the water."""
    img = background(p)
    ripples(img, p, 512, 820, [(640, 120), (860, 170)])
    group = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(group)
    # Foot slab.
    sticker(d, [(262, 800), (762, 800), (762, 860), (262, 860)], rgba(p["cone"]), rgba(p["ink"]))
    cone(group, p, base=(512, 806), height=620, base_w=380, tilt=0, stripes=((0.26, 0.40), (0.56, 0.68)), tip_w=90)
    # Plaster: a cream strip with ink dots, laid diagonally across the upper orange band.
    strip = rotate([(352, 520), (672, 520), (672, 600), (352, 600)], (512, 560), -28)
    d.polygon(sp(strip), fill=rgba(p["plaster"]))
    stroke(d, strip, rgba(p["ink"]), OUTLINE * 0.8)
    pad = rotate([(470, 530), (554, 530), (554, 590), (470, 590)], (512, 560), -28)
    d.polygon(sp(pad), fill=rgba(p["cream"]))
    return finish(img, group, p)


def scene_jetty(p: dict) -> Image.Image:
    """Shipped: two cones standing on a wooden jetty over the water."""
    img = background(p)
    ripples(img, p, 512, 852, [(700, 110), (900, 160)])
    group = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(group)
    for x in (250, 512, 774):
        sticker(d, [(x - 34, 690), (x + 34, 690), (x + 34, 850), (x - 34, 850)], rgba(p["wood"]), rgba(p["ink"]))
    cone(group, p, base=(380, 650), height=440, base_w=260, tilt=-4)
    cone(group, p, base=(650, 650), height=440, base_w=260, tilt=5)
    sticker(d, [(150, 632), (874, 632), (874, 712), (150, 712)], rgba(p["wood"]), rgba(p["ink"]))
    for x in (330, 512, 694):
        d.line([(s(x), s(646)), (s(x), s(698))], fill=rgba(p["ink"]), width=s(OUTLINE * 0.7))
    d.rounded_rectangle([s(176), s(648), s(286), s(668)], radius=s(10), fill=rgba(p["cream"]))
    return finish(img, group, p)


def finish(img: Image.Image, group: Image.Image, p: dict) -> Image.Image:
    """Hard, unblurred ink shadow of the whole sticker group, then the group, then downsample."""
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (W, W), rgba(p["ink"])), (s(SHADOW[0]), s(SHADOW[1])), group.getchannel("A"))
    img.alpha_composite(shadow)
    img.alpha_composite(group)
    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alts", type=Path, help="also write icon-alt-*.png comparison renders here")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    scene_jetty(LIGHT).save(OUT / "AppIcon.png", optimize=True)
    scene_jetty(DARK).save(OUT / "AppIcon-Dark.png", optimize=True)
    scene_jetty(TINTED).convert("L").save(OUT / "AppIcon-Tinted.png", optimize=True)

    def image(filename: str, appearance: str | None = None) -> dict:
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        return entry

    contents = {
        "images": [image("AppIcon.png"), image("AppIcon-Dark.png", "dark"), image("AppIcon-Tinted.png", "tinted")],
        "info": {"author": "xcode", "version": 1},
    }
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"wrote {OUT}")

    if args.alts:
        args.alts.mkdir(parents=True, exist_ok=True)
        for name, scene in (("boat", scene_boat), ("plaster", scene_plaster)):
            path = args.alts / f"icon-alt-{name}.png"
            scene(LIGHT).save(path)
            print(f"wrote {path}")


if __name__ == "__main__":
    main()
