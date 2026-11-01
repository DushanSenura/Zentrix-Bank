"""Turns the artwork in assets/icon/ into what the app and the platform launchers need.

    python tool/prepare_brand_assets.py
    dart run flutter_launcher_icons

Inputs (yours, left untouched):
    assets/icon/app icon.png    glass bank-and-card icon, rounded square on transparency
    assets/icon/bank logo.png   two-bar "Z" logo on transparency

Outputs in assets/brand/:
    app_icon.png              1024x1024, fully opaque and full-bleed. iOS rounds the corners itself and rejects
                              transparency, so the rounded artwork's corners are cropped away rather than left empty.
    app_icon_foreground.png   Android adaptive foreground: the same artwork centred and large enough to cover the
                              mask (72dp of the 108dp canvas), with the rest transparent.
    bank_logo.png             the logo with stray glow specks removed, trimmed, ready for in-app use.

Needs Pillow, numpy and scipy.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'assets', 'icon')
OUT = os.path.join(HERE, '..', 'assets', 'brand')
SIZE = 1024

# Alpha above this counts as "part of the artwork"; the glow around the edges is far fainter.
SOLID = 200


def alpha_bbox(im, threshold):
    return im.split()[3].point(lambda v: 255 if v > threshold else 0).getbbox()


def app_icon():
    art = Image.open(os.path.join(SRC, 'app icon.png')).convert('RGBA')
    left, top, right, bottom = alpha_bbox(art, SOLID)
    # The artwork is a rounded square. Cropping in by more than the corner needs leaves only artwork.
    side = min(right - left, bottom - top)
    inset = round(side * 0.085)
    crop = art.crop((left + inset, top + inset, right - inset, bottom - inset))
    a = np.array(crop)[:, :, 3]
    if a.min() < 250:
        raise SystemExit(f'cropped icon still has transparent pixels (min alpha {a.min()}); raise the inset')

    full = crop.convert('RGB').resize((SIZE, SIZE), Image.LANCZOS)
    full.save(os.path.join(OUT, 'app_icon.png'))

    # Adaptive foreground: artwork covers 74% of the canvas (mask is 66.7%, plus margin for the launcher's parallax).
    inner = round(SIZE * 0.74)
    fg = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    fg.paste(full.resize((inner, inner), Image.LANCZOS).convert('RGBA'), ((SIZE - inner) // 2, (SIZE - inner) // 2))
    fg.save(os.path.join(OUT, 'app_icon_foreground.png'))

    # Colour for the adaptive background layer, taken from the artwork's own deep blue.
    sample = np.array(full)[int(SIZE * 0.5):int(SIZE * 0.6), int(SIZE * 0.05):int(SIZE * 0.12)].reshape(-1, 3)
    r, g, b = (int(v) for v in np.median(sample, axis=0))
    print(f'adaptive background suggestion: #{r:02X}{g:02X}{b:02X}')


def logo():
    im = Image.open(os.path.join(SRC, 'bank logo.png')).convert('RGBA')
    arr = np.array(im)
    alpha = arr[:, :, 3]
    # Keep the two big shapes; drop the detached specks the glow left behind.
    labels, count = ndimage.label(alpha > 24)
    sizes = ndimage.sum(np.ones_like(alpha), labels, index=range(1, count + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s > 0.02 * sizes.max()]
    mask = np.isin(labels, keep)
    # Clear everything except the shapes and a thin band around them (their own anti-aliased edge).
    near = ndimage.binary_dilation(mask, iterations=6)
    arr[~near, 3] = 0
    cleaned = Image.fromarray(arr, 'RGBA')

    box = alpha_bbox(cleaned, 40)
    pad = round(max(box[2] - box[0], box[3] - box[1]) * 0.02)
    cleaned = cleaned.crop((max(box[0] - pad, 0), max(box[1] - pad, 0), box[2] + pad, box[3] + pad))
    cleaned.thumbnail((768, 768), Image.LANCZOS)
    cleaned.save(os.path.join(OUT, 'bank_logo.png'))
    print('logo', cleaned.size, f'({count} shapes found, {len(keep)} kept)')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    app_icon()
    logo()
    print('wrote', os.path.abspath(OUT))
