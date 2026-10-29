"""Bakes the photo-scanned asphalt of Poly Haven's asphalt_floor (CC0, files named asphalt_02_* here) into the city street textures
made by tools/make_road_textures.py: the street tile (20 x 20 m) and the junction go from 1024 /
512 px to 2048 / 1024 px, with the real asphalt's grain in the colour, its fine relief blended
into the normal map, and its roughness mixed in. The grain repeats every 5 m (four times across
a tile) so the tiles still wrap without a seam.

Usage: python3 add_asphalt_grain.py <Hop/Textures> <folder with asphalt_02_{diff,nor,rough}.jpg>
"""
import sys, os
import numpy as np
from PIL import Image

T, SRC = sys.argv[1], sys.argv[2]


def load(path, size, mode='RGB'):
    return np.asarray(Image.open(path).convert(mode).resize(size, Image.LANCZOS)).astype(np.float64) / 255


def tiled(path, size, tiles, mode='RGB'):
    cell = (size[0] // tiles, size[1] // tiles)
    return np.tile(load(path, cell, mode), (tiles, tiles, 1) if mode == 'RGB' else (tiles, tiles))


def bake(name, normal_name, rough_name, size, tiles, out_normal):
    base = load(os.path.join(T, name), size)
    grain = tiled(os.path.join(SRC, 'asphalt_02_diff.jpg'), size, tiles)
    lum = grain.mean(axis=2, keepdims=True)
    # Grain as a ratio round 1 (colour of the street kept, the stones and pores of the photo
    # added); painted lines and kerbs get only a trace of it
    ratio = np.clip(lum / lum.mean(), 0.6, 1.4)
    paint = np.clip((base.mean(axis=2, keepdims=True) - 0.35) / 0.2, 0, 1)
    strength = 0.55 * (1 - paint) + 0.15 * paint
    colour = np.clip(base * (1 - strength + strength * ratio), 0, 1)
    Image.fromarray((colour * 255).astype(np.uint8)).save(os.path.join(T, name), quality=90)

    n1 = load(os.path.join(T, normal_name), size) * 2 - 1
    n2 = tiled(os.path.join(SRC, 'asphalt_02_nor.jpg'), size, tiles) * 2 - 1
    # Whiteout blend of the two tangent-space normals
    n = np.dstack([n1[..., 0] + n2[..., 0] * 0.8, n1[..., 1] + n2[..., 1] * 0.8, n1[..., 2] * n2[..., 2]])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(T, out_normal), quality=92)

    r1 = load(os.path.join(T, rough_name), (size[0] // 2, size[1] // 2))
    r2 = tiled(os.path.join(SRC, 'asphalt_02_rough.jpg'), (size[0] // 2, size[1] // 2), tiles)
    r = np.clip(r1 * 0.6 + r2 * 0.4, 0, 1)
    Image.fromarray((r * 255).astype(np.uint8)).save(os.path.join(T, rough_name), quality=90)


bake('road_albedo.jpg', 'road_normal.png', 'road_rough.jpg', (2048, 2048), 4, 'road_normal.jpg')
bake('junction_albedo.jpg', 'junction_normal.png', 'junction_rough.jpg', (1024, 1024), 4, 'junction_normal.jpg')
