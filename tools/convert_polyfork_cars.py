"""Converts Polyfork's free low poly cars (commercial use, no attribution; see README) into the
game's garage cars.

Polyfork cars are flat-shaded vertex-coloured meshes with named wheel groups (wheel-fl, ...),
built at real size facing +Z. Each car becomes:
  <id>_body.usdz     meshes "textured" (every face, coloured through a palette texture),
                     "headlight" and "taillight" (lit by the game), facing +X, centred, on y = 0
  <id>_wheel.usdz    the front-left wheel centred on its axle, meshes "tire" and "rim"
  <id>_palette.png   the palette: one 16 px cell per colour; the paint colours are grey here
  <id>_mask.png      white where the game tints with the chosen paint
and prints the Swift spec numbers (wheel spots, radius, rear, height).

The car's own colour knobs (from its params.json) say which colours are the bodywork: those are
painted (the upper tone fully, a lower tone as a darker shade of the paint).

Usage: python3 convert_polyfork_cars.py <folder with <asset>.glb and <asset>-params.json> <Hop/Models> [<refined GLB folder>]
"""
import sys, os, json
import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_polyfork_people import Character
from polyfork_car_classes import classify, snap

CELL = 16
COLUMNS = 16

CARS = [
    # game id, Polyfork asset, paint knobs -> grey level, knobs recoloured, length (m)
    dict(id='italia', asset='wedge-coupe-80s-9f8b5e', paint={'upper': 0.92}, recolor={}, length=4.45),
    dict(id='concept', asset='muscle-car-60s-524d46', paint={'upper': 0.92, 'lower': 0.5}, recolor={'roof': '#1a1f27'}, length=4.6),
    dict(id='retro', asset='convertible-60s-b76f89', paint={'body': 0.92}, recolor={}, length=4.6),
    dict(id='strada', asset='hatchback-80s-e95554', paint={'upper': 0.92, 'lower': 0.5}, recolor={}, length=4.2),
    dict(id='toro', asset='boxy-sedan-70s-7d55f7', paint={'upper': 0.92, 'lower': 0.5}, recolor={}, length=4.6),
    dict(id='arrow', asset='station-wagon-70s-11d67b', paint={'body': 0.92}, recolor={}, length=4.6),
    dict(id='bison', asset='pickup-truck-70s-8c0080', paint={'primary': 0.92, 'secondary': 0.5}, recolor={'roof': '#1a1f27'}, length=4.6),
    dict(id='classico', asset='family-crossover-suv-42027f', paint={'body': 0.92}, recolor={}, length=4.45),
]

HEADLIGHT = ['#ecf1cb', '#e7eaea', '#cfd6d6']
TAILLIGHT = ['#d13d34', '#b9553f']


def srgb255(linear):
    c = np.clip(linear, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255


def hex255(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def near(cols255, h, tol=4.5):
    return np.linalg.norm(cols255 - hex255(h), axis=1) < tol


def load_car(path):
    """Triangles and face colours of the body and of each wheel, in the asset's frame."""
    car = Character(path)
    world = car.world({})
    parts = {}
    for ni, node in enumerate(car.g.nodes):
        if node.mesh is None:
            continue
        # Name of the closest named ancestor (wheel-fl, ...) or the body
        name, i = 'body', ni
        while i in car.parent:
            i = car.parent[i]
            if car.g.nodes[i].name and car.g.nodes[i].name.startswith('wheel'):
                name = car.g.nodes[i].name
                break
        for prim in car.g.meshes[node.mesh].primitives:
            pos = car.acc(prim.attributes.POSITION)
            col = car.acc(prim.attributes.COLOR_0)[:, :3]
            nor = car.acc(prim.attributes.NORMAL) if prim.attributes.NORMAL is not None else None
            p4 = np.c_[pos, np.ones(len(pos))]
            m = world(ni)
            out = (m @ p4.T).T[:, :3]
            idx = car.acc(prim.indices).astype(int).reshape(-1) if prim.indices is not None else np.arange(len(pos))
            tris = out[idx].reshape(-1, 3, 3)
            if nor is not None:
                rot = np.linalg.inv(m[:3, :3]).T
                nw = (rot @ nor.T).T
                nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-12)
                norms = nw[idx].reshape(-1, 3, 3)
            else:
                f = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
                f /= np.maximum(np.linalg.norm(f, axis=1, keepdims=True), 1e-12)
                norms = np.repeat(f[:, None, :], 3, axis=1)
            cols = col[idx].reshape(-1, 3, 3).mean(axis=1)
            t0, n0, c0 = parts.get(name, (np.zeros((0, 3, 3)), np.zeros((0, 3, 3)), np.zeros((0, 3))))
            parts[name] = (np.concatenate([t0, tris]), np.concatenate([n0, norms]), np.concatenate([c0, cols]))
    return parts


def stage_for(path, root_name):
    usdc = path[:-5] + '.usdc'
    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, '/' + root_name)
    stage.SetDefaultPrim(root.GetPrim())
    mat = UsdShade.Material.Define(stage, f'/{root_name}/mats/plain')
    shader = UsdShade.Shader.Define(stage, f'/{root_name}/mats/plain/surface')
    shader.CreateIdAttr('UsdPreviewSurface')
    shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.7, 0.7, 0.7))
    mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), 'surface')
    return stage, usdc, mat


def add_mesh(stage, root_name, name, tris, mat, uvs=None, normals=None):
    if normals is None:
        n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        normals = np.repeat(n[:, None, :], 3, axis=1)
    pts = tris.reshape(-1, 3)
    mesh = UsdGeom.Mesh.Define(stage, f'/{root_name}/{name}')
    mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in pts]))
    mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(tris)))
    mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(list(range(len(pts)))))
    mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in normals.reshape(-1, 3)]))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    if uvs is not None:
        st = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
        st.Set(Vt.Vec2fArray([Gf.Vec2f(float(a), float(b)) for a, b in uvs]))
    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(mat)


def finish(stage, usdc, path):
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), path)
    os.remove(usdc)


def convert(spec, src, out, refined=None):
    """`refined`: folder with the Blender-refined GLBs (bevelled, smooth normals); colours are
    snapped back to the original model's colours."""
    original = load_car(os.path.join(src, spec['asset'] + '.glb'))
    parts = load_car(os.path.join(refined or src, spec['asset'] + '.glb'))
    palette255 = np.unique(np.round(srgb255(np.concatenate([c for _, _, c in original.values()]))), axis=0)
    params = json.load(open(os.path.join(src, spec['asset'] + '-params.json')))['params']
    knobs = {k: v['default'] for k, v in params.items() if v['type'] == 'color'}

    # Asset frame (+Z forward) -> game frame (+X forward, Z to the right): x' = z, z' = -x
    def turn(t):
        return np.stack([t[..., 2], t[..., 1], -t[..., 0]], axis=-1)
    parts = {k: (turn(t), turn(n), c) for k, (t, n, c) in parts.items()}
    every = np.concatenate([t.reshape(-1, 3) for t, _, _ in parts.values()])
    lo, hi = every.min(axis=0), every.max(axis=0)
    scale = spec['length'] / (hi[0] - lo[0])
    shift = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    parts = {k: ((t - shift) * scale, n, c) for k, (t, n, c) in parts.items()}
    length = spec['length']

    # Body surfaces: paint (palette + mask), glass, chrome, dark trim, lamps, the rest (palette)
    tris, norms, cols = parts['body']
    c255 = snap(srgb255(cols), palette255)
    centre_x = tris.mean(axis=1)[:, 0]
    classes, base = classify(c255, centre_x, length, knobs, spec['paint'], spec['recolor'])
    painted = classes == 'paint'
    head = classes == 'headlight'
    tail = classes == 'taillight'
    if not refined:
        # The plain conversion: one palette mesh for everything but the lamps
        classes = np.where(np.isin(classes, ['headlight', 'taillight']), classes, 'other').astype(object)
        classes[painted] = 'paint'
    separate = np.isin(classes, ['glass', 'chrome', 'dark', 'headlight', 'taillight'])
    body = ~separate
    if os.environ.get('PREVIEW_DIR'):
        # Data for the before/after renders: triangles, normals, surface and colour (red paint)
        shown = base.copy()
        shown[painted] = base[painted] / 255 * np.array([209, 10, 15])
        wt = np.concatenate([parts[w][0] for w in ['wheel-fl', 'wheel-fr', 'wheel-rl', 'wheel-rr']])
        wn = np.concatenate([parts[w][1] for w in ['wheel-fl', 'wheel-fr', 'wheel-rl', 'wheel-rr']])
        wc = snap(srgb255(np.concatenate([parts[w][2] for w in ['wheel-fl', 'wheel-fr', 'wheel-rl', 'wheel-rr']])), palette255)
        wcls = np.where(wc.mean(axis=1) < 70, 'tire', 'rim')
        np.savez_compressed(os.path.join(os.environ['PREVIEW_DIR'], spec['id'] + ('_after' if refined else '_before')),
                            tris=np.concatenate([tris, wt]), normals=np.concatenate([norms, wn]),
                            classes=np.concatenate([classes.astype(str), wcls]),
                            colors=np.concatenate([shown, wc]) / 255)

    keys = sorted({(tuple(np.round(b).astype(int)), bool(p)) for b, p in zip(base[body], painted[body])})
    slot = {k: i for i, k in enumerate(keys)}
    rows = (len(keys) + COLUMNS - 1) // COLUMNS
    width, height = COLUMNS * CELL, max(1, rows) * CELL
    palette = np.zeros((height, width, 3), dtype=np.uint8)
    mask = np.zeros((height, width, 3), dtype=np.uint8)
    for (colour, paint), i in slot.items():
        r, c = divmod(i, COLUMNS)
        palette[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = colour
        mask[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = 255 if paint else 0
    Image.fromarray(palette).save(os.path.join(out, spec['id'] + '_palette.png'))
    Image.fromarray(mask).save(os.path.join(out, spec['id'] + '_mask.png'))
    uvs = []
    for b, p in zip(base[body], painted[body]):
        r, c = divmod(slot[(tuple(np.round(b).astype(int)), bool(p))], COLUMNS)
        uvs += [((c * CELL + CELL / 2) / width, 1 - (r * CELL + CELL / 2) / height)] * 3

    path = os.path.join(out, spec['id'] + '_body.usdz')
    stage, usdc, mat = stage_for(path, 'car')
    add_mesh(stage, 'car', 'textured', tris[body], mat, uvs, norms[body])
    for cls, mesh_name in [('glass', 'glass'), ('chrome', 'chrome'), ('dark', 'darkplastic'),
                           ('headlight', 'headlight'), ('taillight', 'taillight')]:
        pick = classes == cls
        if pick.any():
            add_mesh(stage, 'car', mesh_name, tris[pick], mat, None, norms[pick])
    finish(stage, usdc, path)

    # Wheels: centres and radius; the front-left one (z < 0) is the model
    spots = []
    names = ['wheel-fl', 'wheel-fr', 'wheel-rl', 'wheel-rr']
    for name in names:
        t, _, _ = parts[name]
        p = t.reshape(-1, 3)
        centre = (p.min(axis=0) + p.max(axis=0)) / 2
        radius = (p[:, 1].max() - p[:, 1].min()) / 2
        spots.append((centre, radius, centre[0] > 0))
    index = min((i for i, s in enumerate(spots) if s[2]), key=lambda i: spots[i][0][2])
    front_left = spots[index]
    name = names[index]
    t, wn, c = parts[name]
    t = t - front_left[0]
    lum = srgb255(c).mean(axis=1)
    dark = lum < 70
    path = os.path.join(out, spec['id'] + '_wheel.usdz')
    stage, usdc, mat = stage_for(path, 'wheel')
    add_mesh(stage, 'wheel', 'tire', t[dark], mat, None, wn[dark])
    if (~dark).any():
        add_mesh(stage, 'wheel', 'rim', t[~dark], mat, None, wn[~dark])
    finish(stage, usdc, path)

    radius = float(np.mean([s[1] for s in spots]))
    spots.sort(key=lambda s: (-s[0][0], s[0][2]))
    wheel_text = ', '.join(f'({s[0][0]:.3f}, {s[0][1]:.3f}, {s[0][2]:.3f}, {"true" if s[2] else "false"})' for s in spots)
    every = np.concatenate([t.reshape(-1, 3) for t, _, _ in parts.values()])
    counts = {k: int((classes == k).sum()) for k in ['paint', 'glass', 'chrome', 'dark', 'headlight', 'taillight', 'other']}
    print(f"{spec['id']}: tris {len(tris)} {counts} colours {len(keys)}")
    print(f"    wheels: [{wheel_text}],")
    print(f"    radius: {radius:.3f}, rear: {every[:, 0].min():.3f}, height: {every[:, 1].max():.3f}")


if __name__ == '__main__':
    for spec in CARS:
        convert(spec, sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
