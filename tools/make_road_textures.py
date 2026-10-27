"""Generates the city street textures (all original, procedural): a 20 x 20 m street tile with
PBR maps, the intersection asphalt, the zebra stripe and a large-scale stain map that breaks the
tiling. Everything tiles along the street (noise is made in the frequency domain, features wrap).

Layout across the street (V, 0..200 units = 20 m), matching the game: gutter + parking strip
0-30, white edge line at 30, lanes, dashed yellow center line at 100, mirrored on the other side.

Writes (all RGB; gray textures crash SceneKit on the simulator and Macs):
  road_albedo.jpg 1024, road_normal.png 1024, road_rough.jpg 512
  junction_albedo.jpg 512, junction_normal.png 512, junction_rough.jpg 256
  zebra_albedo.jpg 128x512, street_stains.jpg 512

Usage: python3 make_road_textures.py <Hop/Textures>
"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(2026)


def fractal(n, m, beta=2.0, seed=0, low=1.0):
    """Periodic 1/f^beta noise, normalized to 0..1."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(m)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    amp = 1 / f ** (beta / 2)
    amp[f < low / max(n, m)] = 0
    phase = r.uniform(0, 2 * np.pi, (n, m))
    noise = np.real(np.fft.ifft2(amp * np.exp(1j * phase)))
    noise -= noise.min()
    return noise / noise.max()


def stones(n, m, count, rmin, rmax, seed):
    """Aggregate: random small rounded stones (wrapping), returns height 0..1 and tone."""
    r = np.random.default_rng(seed)
    height = np.zeros((n, m))
    tone = np.zeros((n, m))
    for _ in range(count):
        cy, cx = r.integers(0, n), r.integers(0, m)
        rad = r.uniform(rmin, rmax)
        ext = int(np.ceil(rad)) + 1
        ys = (np.arange(cy - ext, cy + ext + 1) % n)
        xs = (np.arange(cx - ext, cx + ext + 1) % m)
        dy = np.arange(-ext, ext + 1)[:, None]
        dx = np.arange(-ext, ext + 1)[None, :]
        d = np.sqrt(dx * dx + dy * dy) / rad
        bump = np.clip(1 - d * d, 0, 1)
        sub = np.ix_(ys, xs)
        height[sub] = np.maximum(height[sub], bump * r.uniform(0.5, 1))
        tone[sub] = np.where(bump > 0, r.uniform(-1, 1), tone[sub])
    return height, tone


def crack(mask, start, steps, seed, base_angle=None, depth=0):
    """A sealed crack: long, mostly straight with a gentle wander (longitudinal or transverse
    like real pavement), with a rare short branch."""
    r = np.random.default_rng(seed)
    n, m = mask.shape
    y, x = start
    heading = base_angle if base_angle is not None else r.choice([0, np.pi / 2]) + r.normal(0, 0.15)
    angle = heading
    for _ in range(steps):
        angle += r.normal(0, 0.09) + (heading - angle) * 0.04
        y += np.sin(angle) * 1.2
        x += np.cos(angle) * 1.2
        mask[int(y) % n, int(x) % m] = 1
        if depth < 1 and r.random() < 0.004:
            crack(mask, (y, x), steps // 5, int(r.integers(1e9)), angle + r.choice([-1, 1]) * r.uniform(0.5, 1.1), depth + 1)


def normal_map(height, strength):
    gx = ndimage.sobel(height, axis=1, mode='wrap')
    gy = ndimage.sobel(height, axis=0, mode='wrap')
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / length, ny / length, nz / length], -1) * 0.5 + 0.5
    return Image.fromarray((rgb * 255).astype(np.uint8))


def save_gray(values, path, size=None, quality=90):
    img = Image.fromarray((np.clip(values, 0, 1) * 255).astype(np.uint8)).convert('RGB')
    if size:
        img = img.resize(size, Image.LANCZOS)
    img.save(path, quality=quality)


def asphalt(n, m, seed):
    """Base asphalt: albedo (rgb), height and roughness."""
    macro = fractal(n, m, 2.2, seed)
    fine = fractal(n, m, 1.0, seed + 1)
    h_st, t_st = stones(n, m, int(n * m / 9), 0.6, 1.7, seed + 2)
    base = 0.19 + 0.05 * macro + 0.03 * (fine - 0.5)
    # Exposed aggregate: dense small stones, close in tone to the binder (a few lighter ones)
    stone_tone = base + 0.035 + 0.05 * t_st + 0.09 * (t_st > 0.85)
    albedo_l = np.where(h_st > 0.3, base * 0.35 + stone_tone * 0.65, base)
    albedo_l = ndimage.gaussian_filter(albedo_l, 0.45, mode='wrap')
    rgb = np.stack([albedo_l * 1.0, albedo_l * 1.01, albedo_l * 1.05], -1)
    height = 0.6 * h_st + 0.25 * fine + 0.15 * macro
    rough = 0.82 + 0.1 * fine - 0.12 * (h_st > 0.35)
    return rgb, height, rough


def wear(n, m, seed, scale=1.0):
    """Paint wear mask (1 = paint left)."""
    w = fractal(n, m, 1.4, seed)
    grit = np.random.default_rng(seed).random((n, m))
    return np.clip((w - 0.28 * scale) * 3, 0, 1) * (grit > 0.08 * scale)


# ---------------------------------------------------------------- street tile
N = 1024
k = N / 200          # pixels per world unit (10 cm)
rgb, height, rough = asphalt(N, N, 10)
v = np.arange(N)[:, None] / k  # across (units)
u = np.arange(N)[None, :] / k  # along

# Parking strips: newer, slightly different asphalt with a seam
strip = (v < 30) | (v > 170)
rgb = np.where(strip[..., None], rgb * np.array([1.08, 1.08, 1.07]), rgb)
seam = (np.abs(v - 30.8) < 0.25) | (np.abs(v - 169.2) < 0.25)
rgb = np.where(seam[..., None] & np.ones((1, N, 1), bool), rgb * 0.7, rgb)

# Tyre polish: two wheel paths per lane, darker and smoother, with streaks along the street
streak = fractal(N, N, 1.0, 21)
streak = ndimage.uniform_filter1d(streak, 60, axis=1, mode='wrap')
for lane in (65, 135):
    for off in (-9, 9):
        band = np.exp(-((v - (lane + off)) / 4.5) ** 2)
        polish = band * (0.6 + 0.4 * streak)
        rgb = rgb * (1 - 0.18 * polish[..., None])
        rough = rough - 0.22 * polish
    # Oil drips down the lane center
    drip = np.exp(-((v - lane) / 3.0) ** 2) * (fractal(N, N, 2.0, 30 + lane) > 0.55)
    drip = ndimage.gaussian_filter(drip.astype(float), 3, mode='wrap')
    rgb = rgb * (1 - 0.35 * drip[..., None])
    rough = rough - 0.3 * drip

# Sealed cracks (tar: dark, shiny, slightly raised) and a patch
cracks = np.zeros((N, N))
crack(cracks, (82 * k, 0), 900, 101, base_angle=0.0)          # longitudinal, along a lane joint
crack(cracks, (150 * k, 300), 500, 102, base_angle=0.05)
crack(cracks, (40 * k, 700), 260, 103, base_angle=np.pi / 2)  # transverse
crack(cracks, (120 * k, 120), 220, 104, base_angle=np.pi / 2 + 0.1)
seal = ndimage.gaussian_filter(cracks, 1.1, mode='wrap')
seal = np.clip(seal / seal.max() * 3, 0, 1)
rgb = rgb * (1 - 0.55 * seal[..., None])
rough = rough - 0.35 * seal
height = height + 0.4 * seal
# Irregular repair patch
blob = ndimage.gaussian_filter(np.random.default_rng(5).random((N, N)), 25, mode='wrap')
spot = np.exp(-(((u - 140) / 14) ** 2 + ((v - 125) / 8) ** 2))
patch = (spot * (0.7 + 3 * (blob - blob.mean()))) > 0.45
prgb, ph_, pr = asphalt(N, N, 77)
rgb = np.where(patch[..., None], prgb * 0.74, rgb)
rough = np.where(patch, pr + 0.04, rough)
height = np.where(patch, ph_ + 0.15, height)
edge = ndimage.gaussian_filter((patch ^ ndimage.binary_erosion(patch, iterations=2)).astype(float), 0.8)
rgb = rgb * (1 - 0.5 * np.clip(edge * 2, 0, 1)[..., None])

# Concrete gutter along both curbs, with joints every 2 m
gutter = (v < 4) | (v > 196)
concrete = 0.55 + 0.06 * fractal(N, N, 1.6, 40)
rgb = np.where(gutter[..., None], np.stack([concrete, concrete * 0.99, concrete * 0.96], -1), rgb)
rough = np.where(gutter, 0.9, rough)
joint = gutter & ((u % 20) < 0.3)
rgb = np.where(joint[..., None], rgb * 0.55, rgb)
height = np.where(gutter, height * 0.3 - 0.3, height)

# Road paint, worn (more worn in the wheel paths), slightly raised and smoother
paint = np.zeros((N, N))
paint_color = np.zeros((N, N, 3))
white = np.array([0.88, 0.88, 0.86])
yellow = np.array([0.95, 0.74, 0.18])
edge_lines = (np.abs(v - 30) < 2) | (np.abs(v - 170) < 2)
ticks = ((u % 50) < 1.5) & ((v < 29) & (v > 4) | (v > 171) & (v < 196))
center = (np.abs(v - 100) < 3) & ((u % 100) > 12) & ((u % 100) < 88)
paint_w = (edge_lines | ticks).astype(float)
paint_y = center.astype(float)
w_mask = wear(N, N, 50)
paint_w *= w_mask
paint_y *= wear(N, N, 51, 0.8)
paint = np.clip(paint_w + paint_y, 0, 1)
paint = ndimage.gaussian_filter(paint, 0.6, mode='wrap')
pc = np.where(paint_y[..., None] > 0, yellow, white)
rgb = rgb * (1 - paint[..., None]) + pc * paint[..., None] * (0.9 + 0.1 * fractal(N, N, 1, 52)[..., None])
rough = rough * (1 - paint) + 0.55 * paint
height = height + 0.35 * paint

Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'road_albedo.jpg'), quality=88)
normal_map(ndimage.gaussian_filter(height, 0.7, mode='wrap'), 2.2).save(os.path.join(OUT, 'road_normal.png'))
save_gray(rough, os.path.join(OUT, 'road_rough.jpg'), (512, 512))

# ---------------------------------------------------------------- intersection
J = 512
jrgb, jh, jr = asphalt(J, J, 60)
jpol = fractal(J, J, 2.4, 61)
jrgb = jrgb * (1 - 0.12 * (jpol > 0.6)[..., None])
jr = jr - 0.15 * (jpol > 0.6)
jc = np.zeros((J, J))
crack(jc, (J * 0.3, 0), 420, 201, base_angle=0.02)
crack(jc, (0, J * 0.7), 420, 202, base_angle=np.pi / 2)
jseal = ndimage.gaussian_filter(jc, 1.0, mode='wrap')
jseal = np.clip(jseal / jseal.max() * 3, 0, 1)
jrgb = jrgb * (1 - 0.55 * jseal[..., None])
jr = jr - 0.35 * jseal
Image.fromarray((np.clip(jrgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'junction_albedo.jpg'), quality=88)
normal_map(ndimage.gaussian_filter(jh, 0.7, mode='wrap'), 2.2).save(os.path.join(OUT, 'junction_normal.png'))
save_gray(jr, os.path.join(OUT, 'junction_rough.jpg'), (256, 256))

# ---------------------------------------------------------------- zebra stripe (worn white paint on asphalt)
zr, _, _ = asphalt(512, 128, 70)
zw = wear(512, 128, 71, 1.1)
zpaint = ndimage.gaussian_filter(zw, 0.6)
z = zr * (1 - zpaint[..., None]) + np.array([0.9, 0.9, 0.88]) * zpaint[..., None]
Image.fromarray((np.clip(z, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'zebra_albedo.jpg'), quality=88)

# ---------------------------------------------------------------- large-scale stains (multiply, breaks tiling)
s = fractal(512, 512, 2.6, 80)
s2 = fractal(512, 512, 1.6, 81)
stains = 1 - 0.16 * np.clip((s - 0.45) * 2.5, 0, 1) - 0.06 * s2
save_gray(np.clip(stains, 0.7, 1), os.path.join(OUT, 'street_stains.jpg'))
print('done')
