"""Paints a tileable foliage texture for the street trees' crowns (all original, procedural):
thousands of small leaves in layers (darker inside, lighter and warmer on top), each with a
soft shading across its blade and a midrib, plus the height map they make, turned into a
normal map. Everything wraps, so the crown can repeat it without seams.

Writes (RGB): ph_leaves_diff.jpg 1024, ph_leaves_nor.jpg 1024, ph_leaves_rough.jpg 512
Usage: python3 make_foliage_texture.py <Hop/Textures>
"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
N = 1024
rng = np.random.default_rng(7)

colour = np.zeros((N, N, 3), np.float32)
height = np.zeros((N, N), np.float32)
# Deep shade first: the gaps between leaves read as the dark inside of the crown
colour[:] = (0.05, 0.10, 0.04)


def leaf_stamp(length, width, angle):
    """A leaf as an alpha mask and its shading (0 at the edges, 1 along the midrib)."""
    size = int(length * 2.2) + 4
    img = Image.new('L', (size * 4, size * 4), 0)
    d = ImageDraw.Draw(img)
    c = size * 2
    # Pointed ellipse: two arcs approximated by a polygon
    pts = []
    for t in np.linspace(0, math.pi, 24):
        x = -length * 2 + 4 * length * t / math.pi
        y = math.sin(t) ** 0.8 * width * 2
        pts.append((x, y))
    pts += [(x, -y) for x, y in reversed(pts)]
    a = math.radians(angle)
    rot = [(c + x * math.cos(a) - y * math.sin(a), c + x * math.sin(a) + y * math.cos(a)) for x, y in pts]
    d.polygon(rot, fill=255)
    img = img.resize((size, size), Image.LANCZOS)
    mask = np.asarray(img).astype(np.float32) / 255
    blur = np.asarray(img.filter(ImageFilter.GaussianBlur(width * 0.35))).astype(np.float32) / 255
    return mask, blur


def stamp(cx, cy, mask, shade, rgb, lift):
    h, w = mask.shape
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            x0, y0 = int(cx - w / 2) + ox, int(cy - h / 2) + oy
            x1, y1 = x0 + w, y0 + h
            if x1 <= 0 or y1 <= 0 or x0 >= N or y0 >= N:
                continue
            sx0, sy0 = max(0, -x0), max(0, -y0)
            sx1, sy1 = w - max(0, x1 - N), h - max(0, y1 - N)
            m = mask[sy0:sy1, sx0:sx1]
            s = shade[sy0:sy1, sx0:sx1]
            region = (slice(max(0, y0), min(N, y1)), slice(max(0, x0), min(N, x1)))
            c = np.array(rgb, np.float32) * (0.62 + 0.38 * s)[..., None]
            colour[region] = colour[region] * (1 - m[..., None]) + c * m[..., None]
            height[region] = np.maximum(height[region], (lift + 0.25 * s) * m)


# Three layers, deepest first: each layer lighter and higher
layers = [(3800, (0.09, 0.20, 0.06), 0.2), (3200, (0.16, 0.31, 0.09), 0.5), (2200, (0.26, 0.43, 0.13), 0.8)]
for count, base, lift in layers:
    for _ in range(count):
        length = rng.uniform(20, 34)
        width = length * rng.uniform(0.38, 0.5)
        mask, shade = leaf_stamp(length, width, rng.uniform(0, 360))
        tint = np.array(base) * rng.uniform(0.85, 1.15) + np.array([rng.uniform(-0.02, 0.04), rng.uniform(-0.03, 0.03), 0])
        stamp(rng.uniform(0, N), rng.uniform(0, N), mask, shade, np.clip(tint, 0, 1), lift + rng.uniform(-0.08, 0.08))

Image.fromarray((np.clip(colour, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'ph_leaves_diff.jpg'), quality=90)
# Normal map from the height (wrapping gradients)
hb = np.asarray(Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
gx = (np.roll(hb, -1, 1) - np.roll(hb, 1, 1)) * 3.0
gy = (np.roll(hb, -1, 0) - np.roll(hb, 1, 0)) * 3.0
n = np.dstack([-gx, gy, np.ones_like(gx)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, 'ph_leaves_nor.jpg'), quality=90)
rough = np.clip(0.75 - 0.25 * hb, 0, 1)
Image.fromarray((rough * 255).astype(np.uint8)).convert('RGB').resize((512, 512)).save(os.path.join(OUT, 'ph_leaves_rough.jpg'), quality=88)
print('done')

# ------------------------------------------------------------------ leaf cluster card (RGBA)
# A spray of leaves on a transparent background, for the cards that make up a tree's crown:
# thin twigs from the bottom centre, leaves along them, lit from above (lighter at the top).
C = 512
card = np.zeros((C, C, 4), np.float32)
card_h = np.zeros((C, C), np.float32)
crng = np.random.default_rng(11)


def card_leaf(cx, cy, length, width, angle, rgb, lift):
    mask, shade = leaf_stamp(length, width, angle)
    h, w = mask.shape
    x0, y0 = int(cx - w / 2), int(cy - h / 2)
    x1, y1 = x0 + w, y0 + h
    if x0 < 0 or y0 < 0 or x1 > C or y1 > C:
        return
    region = (slice(y0, y1), slice(x0, x1))
    c = np.array(rgb, np.float32) * (0.6 + 0.4 * shade)[..., None]
    card[region][..., :3] = card[region][..., :3] * (1 - mask[..., None]) + c * mask[..., None]
    card[region][..., 3] = np.maximum(card[region][..., 3], mask)
    card_h[region] = np.maximum(card_h[region], (lift + 0.3 * shade) * mask)


twig = Image.new('L', (C, C), 0)
td = ImageDraw.Draw(twig)
tips = []
for k in range(9):
    a = math.radians(-90 + (k - 4) * 17 + crng.uniform(-6, 6))
    length = crng.uniform(280, 400)
    x, y = C / 2 + crng.uniform(-20, 20), C - 10
    pts = [(x, y)]
    for s in range(6):
        a += crng.uniform(-0.15, 0.15)
        x += math.cos(a) * length / 6
        y += math.sin(a) * length / 6
        pts.append((x, y))
        tips.append((x, y, a))
    td.line(pts, fill=255, width=3)
tw = np.asarray(twig).astype(np.float32) / 255
card[..., :3] = card[..., :3] * (1 - tw[..., None]) + np.array([0.22, 0.16, 0.1]) * tw[..., None]
card[..., 3] = np.maximum(card[..., 3], tw)
for x, y, a in tips:
    for _ in range(6):
        side = crng.choice([-1, 1])
        ang = math.degrees(a) + side * crng.uniform(25, 70)
        length = crng.uniform(34, 54)
        off = length * 0.9
        lx = x + math.cos(math.radians(ang)) * off * 0.6
        ly = y + math.sin(math.radians(ang)) * off * 0.6
        top = 1 - ly / C          # higher on the card: more light
        rgb = np.array([0.16 + 0.14 * top, 0.32 + 0.2 * top, 0.09 + 0.06 * top]) * crng.uniform(0.85, 1.15)
        card_leaf(lx, ly, length, length * crng.uniform(0.38, 0.48), ang, np.clip(rgb, 0, 1), 0.5 + 0.3 * top)
# Colour bleeds past the alpha edge so mipmaps do not darken the leaf borders
rgb8 = (np.clip(card[..., :3], 0, 1) * 255).astype(np.uint8)
alpha8 = (np.clip(card[..., 3], 0, 1) * 255).astype(np.uint8)
filled = Image.fromarray(rgb8)
for _ in range(6):
    filled = Image.composite(Image.fromarray(rgb8), filled.filter(ImageFilter.MaxFilter(5)), Image.fromarray(alpha8))
out = np.dstack([np.asarray(filled), alpha8])
Image.fromarray(out, 'RGBA').save(os.path.join(OUT, 'leafcard.png'))
hb = np.asarray(Image.fromarray((card_h * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
gx = (np.roll(hb, -1, 1) - np.roll(hb, 1, 1)) * 4.0
gy = (np.roll(hb, -1, 0) - np.roll(hb, 1, 0)) * 4.0
n = np.dstack([-gx, gy, np.ones_like(gx)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, 'leafcard_nor.jpg'), quality=90)
print('card done')
