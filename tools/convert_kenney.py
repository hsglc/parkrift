"""Converts vehicles from Kenney's "Car Kit" (CC0, www.kenney.nl) into USDZ for SceneKit and
writes Hop/KenneyCatalog.swift with their wheel positions and sizes.

The models are low-poly and share one palette texture (colormap.png). Game axes: +x forward,
+y up, z to the right; Kenney models face +z. They are stretched a little lengthwise (stylized
cars are short and tall) while the wheels keep a round profile.

Usage: python3 convert_kenney.py <car-kit folder> <Hop/Models> <Hop/KenneyCatalog.swift>
"""
import sys, os, shutil
import numpy as np
from convert_cars import load, collect, merge, write_usdz

SCALE = np.array([1.65, 1.3, 1.35])      # game x (length), y (height), z (width)
WHEEL_SCALE = np.array([1.3, 1.3, 1.35])  # round wheels

# Garage cars whose main body color can be repainted (others keep their livery)
TINTABLE = ['sedan-sports', 'hatchback-sports', 'suv-luxury']

VEHICLES = ['sedan', 'sedan-sports', 'hatchback-sports', 'suv', 'suv-luxury', 'taxi', 'police', 'van',
            'truck', 'delivery', 'ambulance', 'garbage-truck', 'firetruck']


def to_game(v, scale):
    # Kenney (x left, y up, z forward) -> game (x forward, y up, z right): a turn about y
    g = np.stack([v[:, 2], v[:, 1], -v[:, 0]], axis=1)
    return g * scale


def make_tint(colormap_path, v, f, uv, ident, out):
    """Finds the body's main paint color (the saturated palette color covering the most area) and
    writes a neutral-grey copy of the palette where that color was, plus a mask of those texels."""
    from PIL import Image
    img = np.asarray(Image.open(colormap_path).convert('RGB')).astype(np.float64) / 255
    h, w, _ = img.shape
    centers = uv[f].mean(axis=1)
    px = np.clip((centers[:, 0] * w).astype(int), 0, w - 1)
    py = np.clip(((1 - (1 - centers[:, 1])) * h).astype(int), 0, h - 1)   # glTF v: 0 = top row
    colors = img[py, px]
    area = np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1) / 2
    saturation = colors.max(1) - colors.min(1)
    keys = (colors * 255).round().astype(int)
    totals = {}
    for key, a, sat in zip(map(tuple, keys), area, saturation):
        if sat > 0.18:
            totals[key] = totals.get(key, 0) + a
    paint = np.array(max(totals, key=totals.get)) / 255
    mask = np.abs(img - paint).max(axis=2) < 0.06
    base = img.copy()
    lum = (img * [0.3, 0.59, 0.11]).sum(axis=2)
    shade = np.clip(lum / max(1e-3, (paint * [0.3, 0.59, 0.11]).sum()) * 0.92, 0, 1)
    base[mask] = shade[mask][:, None]
    Image.fromarray((base * 255).astype(np.uint8)).save(os.path.join(out, f'kenney_{ident}_base.png'))
    Image.fromarray((mask * 255).astype(np.uint8)).save(os.path.join(out, f'kenney_{ident}_mask.png'))
    print(f'  paint color {tuple((paint * 255).round().astype(int))}, {mask.mean() * 100:.1f}% of the palette')


def main(src, out_models, out_swift):
    shutil.copy(os.path.join(src, 'Textures', 'colormap.png'), os.path.join(out_models, 'kenney_colormap.png'))
    entries = []
    for name in VEHICLES:
        g, blob = load(os.path.join(src, name + '.glb'))
        parts = collect(g, blob, lambda node, ancestors, material: ('wheel' if node in ('wheel-front-left', 'wheel-front-right', 'wheel-back-left', 'wheel-back-right') else 'body', node))
        body_chunks = [c for chunks in parts['body'].values() for c in chunks]
        bv, bf, buv = merge(body_chunks)
        bv = to_game(bv, SCALE)
        wheels = {}
        for node, chunks in parts.get('wheel', {}).items():
            v, f, uv = merge(chunks)
            wheels[node] = (v, f, uv)
        # Wheel centers (Kenney space) -> game space with the body scale (positions follow the body)
        spots = []
        for node, (v, f, uv) in sorted(wheels.items()):
            center = (v.min(0) + v.max(0)) / 2
            c = to_game(center[None, :], SCALE)[0]
            spots.append((c, 'front' in node))
        ground = min(bv[:, 1].min(), min(c[1] for c, _ in spots) - 0.3 * WHEEL_SCALE[1])
        lift = -ground
        bv[:, 1] += lift
        ident = name.replace('-', '_')
        write_usdz({'kenney': (bv, bf, buv)}, os.path.join(out_models, f'kenney_{ident}_body.usdz'))
        # One wheel (front left), centered, with round scaling
        node = next(n for n in wheels if 'front-left' in n)
        v, f, uv = wheels[node]
        center = (v.min(0) + v.max(0)) / 2
        wv = to_game(v - center, WHEEL_SCALE)
        write_usdz({'kenney': (wv, f, uv)}, os.path.join(out_models, f'kenney_{ident}_wheel.usdz'))
        radius = float((wv[:, 1].max() - wv[:, 1].min()) / 2)
        side = -1 if to_game(center[None, :], SCALE)[0][2] < 0 else 1
        lo, hi = bv.min(0), bv.max(0)
        entries.append((ident, name, [(float(c[0]), float(c[1] + lift), float(c[2]), front) for c, front in spots],
                        radius, side, float(hi[0] - lo[0]), float(hi[2] - lo[2]), float(hi[1]), float(lo[0])))
        if name in TINTABLE:
            make_tint(os.path.join(src, 'Textures', 'colormap.png'), bv, bf, buv, ident, out_models)
        print(f'{name}: {len(bf)} body tris, length {hi[0]-lo[0]:.2f} m, height {hi[1]:.2f} m, wheel r {radius:.2f}')

    lines = ['// Generated by tools/convert_kenney.py from Kenney\'s Car Kit (CC0, www.kenney.nl). Do not edit.',
             'import SceneKit', '', '/// A Kenney vehicle: model files, wheel spots and size (meters, +x forward).',
             'struct KenneyVehicle {', '    let id: String', '    let wheels: [(Float, Float, Float, Bool)]',
             '    let wheelRadius: Float', '    let wheelModelSide: Float', '    let length: Float', '    let width: Float',
             '    let height: Float', '    /// Rear end (x) of the body.', '    let rear: Float', '}', '',
             'enum KenneyCatalog {', '    static let all: [String: KenneyVehicle] = [']
    for ident, name, spots, radius, side, length, width, height, rear in entries:
        wheel_text = ', '.join(f'({x:.3f}, {y:.3f}, {z:.3f}, {"true" if front else "false"})' for x, y, z, front in spots)
        lines.append(f'        "{ident}": KenneyVehicle(id: "{ident}", wheels: [{wheel_text}], wheelRadius: {radius:.3f}, '
                     f'wheelModelSide: {side}, length: {length:.3f}, width: {width:.3f}, height: {height:.3f}, rear: {rear:.3f}),')
    lines += ['    ]', '}', '']
    with open(out_swift, 'w') as fh:
        fh.write('\n'.join(lines))


if __name__ == '__main__':
    main(*sys.argv[1:4])
