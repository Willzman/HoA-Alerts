# Copyright (C) 2026 willzman
# SPDX-License-Identifier: GPL-3.0-only
"""Generate HoA Alerts' countdown numbers (1-10) as TGA textures.

Each numeral is drawn from an open-licensed font and given an original
treatment: a gold-to-orange gradient, fiery mottling, a bevel, a dark
outline and a soft drop shadow. Run from the repository root:

    python3 tools/make_numbers.py path/to/Font.ttf

Writes 256x256 32-bit RLE TGA files (the format the game client loads
for addon art) to HoAAlerts/Textures/Countdown/.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 256            # texture size (power of two)
SS = 4                # supersampling for smooth edges
OUT = os.path.join(os.path.dirname(__file__), "..", "HoAAlerts", "Textures", "Countdown")

TOP = np.array([255, 236, 140]) / 255      # pale gold
MID = np.array([247, 160, 38]) / 255       # orange gold
LOW = np.array([196, 70, 14]) / 255        # ember red
OUTLINE = np.array([38, 14, 4]) / 255      # dark brown


def glyph_mask(text, font_path):
    """The numeral as a 0..1 mask, centered and scaled to fill most of the texture."""
    big = SIZE * SS
    img = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(img)
    target = big * (0.70 if len(text) > 1 else 0.74)
    size = int(big * 0.8)
    font = ImageFont.truetype(font_path, size)
    box = draw.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    # fit by height like single digits; two digits may use most of the width
    scale = min(target / h, big * 0.94 / w) if len(text) > 1 else target / max(w, h)
    font = ImageFont.truetype(font_path, int(size * scale))
    box = draw.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text(((big - w) / 2 - box[0], (big - h) / 2 - box[1]), text, font=font, fill=255)
    return img


def noise(shape, seed, scales=(6, 14, 32)):
    """Smooth value noise in 0..1 (sum of upscaled random grids)."""
    rng = np.random.default_rng(seed)
    out = np.zeros(shape)
    for i, cells in enumerate(scales):
        grid = Image.fromarray((rng.random((cells, cells)) * 255).astype("uint8"))
        layer = np.asarray(grid.resize(shape[::-1], Image.BICUBIC), dtype=float) / 255
        out += layer / (i + 1)
    out -= out.min()
    return out / out.max()


def render(text, font_path, seed):
    big_mask = glyph_mask(text, font_path)
    mask = np.asarray(big_mask.resize((SIZE, SIZE), Image.LANCZOS), dtype=float) / 255

    # outline: the glyph grown by a few pixels
    grown = big_mask.filter(ImageFilter.MaxFilter(6 * SS + 1)).filter(ImageFilter.GaussianBlur(SS))
    outline = np.asarray(grown.resize((SIZE, SIZE), Image.LANCZOS), dtype=float) / 255

    # vertical gold -> orange -> ember gradient over the glyph's height
    ys = np.nonzero(mask.max(axis=1) > 0.5)[0]
    top, bottom = ys.min(), ys.max()
    t = np.clip((np.arange(SIZE) - top) / max(1, bottom - top), 0, 1)[:, None]
    upper = (t < 0.5)
    k = np.where(upper, t * 2, (t - 0.5) * 2)
    fill = np.where(upper[..., None],
                    TOP * (1 - k[..., None]) + MID * k[..., None],
                    MID * (1 - k[..., None]) + LOW * k[..., None])
    fill = np.broadcast_to(fill, (SIZE, SIZE, 3)).copy()

    # fiery mottling: darker, redder patches
    n = noise((SIZE, SIZE), seed)[..., None]
    fill = fill * (0.70 + 0.42 * n) + np.array([0.12, -0.06, -0.08]) * (1 - n) ** 2

    # bevel: light from the top-left on the glyph's edges
    soft = np.asarray(big_mask.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(3)),
                      dtype=float) / 255
    gy, gx = np.gradient(soft)
    light = -(gx + gy) * 6
    rim = np.clip(1 - np.abs(soft - 0.5) * 2, 0, 1) ** 0.5
    fill = fill + (light * rim)[..., None] * 0.55
    # inner edge darkening for depth
    fill = fill * (0.75 + 0.25 * np.clip(soft * 1.4, 0, 1))[..., None]
    fill = np.clip(fill, 0, 1)

    # compose: shadow, outline, fill
    shadow_img = Image.fromarray((outline * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(5))
    shadow = np.roll(np.asarray(shadow_img, dtype=float) / 255, (6, 4), axis=(0, 1)) * 0.65

    rgb = np.zeros((SIZE, SIZE, 3))
    alpha = shadow.copy()
    rgb = rgb * (1 - outline[..., None]) + OUTLINE * outline[..., None]
    alpha = alpha + outline * (1 - alpha)
    rgb = rgb * (1 - mask[..., None]) + fill * mask[..., None]
    alpha = alpha + mask * (1 - alpha)

    rgba = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    return Image.fromarray((rgba * 255 + 0.5).astype("uint8"), "RGBA")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python3 tools/make_numbers.py Font.ttf [out_dir]")
    font_path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else OUT
    os.makedirs(out, exist_ok=True)
    for n in range(1, 11):
        img = render(str(n), font_path, seed=n)
        path = os.path.join(out, f"{n}.tga")
        img.save(path, compression="tga_rle")
        print(path)


if __name__ == "__main__":
    main()
