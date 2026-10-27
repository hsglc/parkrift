"""Converts the Ferrari 458 glTF (decoded, no Draco) into two light USDZ files for SceneKit:
car_body.usdz (exterior parts, one prim per material group) and car_wheel.usdz (one wheel,
centered on its axle). Interior parts are dropped and every part is decimated for phones.
The car faces +x, y is up, length is scaled to 4.4 m.

Model: "Ferrari 458 Italia" by vicent091036 (https://sketchfab.com/models/57bf6cc56931426e87494f554df1dab6),
CC BY 4.0, via the three.js examples.

Usage: python3 convert_car.py ferrari-plain.glb out_dir
"""
import sys, os, math
import numpy as np
import pygltflib
import fast_simplification
from pxr import Usd, UsdGeom, Vt, Gf, Sdf, UsdUtils

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
g = pygltflib.GLTF2().load(src)
blob = g.binary_blob()

def accessor(i):
    a = g.accessors[i]
    bv = g.bufferViews[a.bufferView]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a.componentType]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
    size = np.dtype(comp).itemsize
    stride = bv.byteStride or n * size
    start = (bv.byteOffset or 0) + (a.byteOffset or 0)
    rows = [np.frombuffer(blob, dtype=comp, count=n, offset=start + k * stride) for k in range(a.count)] if stride != n * size \
        else [np.frombuffer(blob, dtype=comp, count=a.count * n, offset=start).reshape(a.count, n)]
    return np.vstack(rows) if stride != n * size else rows[0].copy()

def local_matrix(node):
    if node.matrix:
        return np.array(node.matrix, dtype=np.float64).reshape(4, 4).T
    t = np.array(node.translation or [0, 0, 0], dtype=np.float64)
    q = node.rotation or [0, 0, 0, 1]
    s = np.array(node.scale or [1, 1, 1], dtype=np.float64)
    x, y, z, w = q
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m

world = {}
parent_name = {}
def walk(index, parent, top):
    node = g.nodes[index]
    world[index] = parent @ local_matrix(node)
    parent_name[index] = top
    for child in node.children or []:
        walk(child, world[index], top if top else None)
for root in g.scenes[0].nodes:
    walk(root, np.eye(4), None)
# Label each node with its top-level group (main / wheel_xx / steering)
group = {}
def label(index, current):
    name = g.nodes[index].name or ''
    if name.startswith('wheel_') or name == 'main' or name.startswith('steering'):
        current = name if current is None or current in ('RootNode',) else current
    group[index] = current
    for child in g.nodes[index].children or []:
        label(child, current)
for root in g.scenes[0].nodes:
    label(root, 'RootNode')

INTERIOR = {'trim', 'leather', 'interior_light', 'interior_dark', 'carpet'}
BODY_PARTS = {}   # material group -> (verts list, faces list)
OTHER_WHEELS = {}
WHEEL_PARTS = {}

# Exterior material groups the game recolors/re-materials by prim name
def material_group(node_name, material_name):
    if node_name == 'body':
        return 'paint'
    if node_name == 'glass':
        return 'glass'
    if node_name in ('lights_red', 'brakes'):
        return 'taillight'
    if node_name in ('lights', 'leds'):
        return 'headlight'
    if node_name == 'chrome':
        return 'chrome'
    if node_name in ('carbon_fibre_trim', 'carbon fibre'):
        return 'carbon'
    if node_name in ('grills', 'wipers', 'plastic_gray'):
        return 'darkplastic'
    if node_name in ('metal',):
        return 'metal'
    if node_name in ('yellow_trim', 'blue'):
        return 'badge'
    if node_name == 'tire':
        return 'tire'
    if node_name in ('wheel',) or node_name.startswith('rim_'):
        return 'rim'
    if node_name == 'brake':
        return 'caliper'
    if node_name in ('centre', 'nuts'):
        return 'hub'
    return 'darkplastic'

def add(target, key, verts, faces):
    vs, fs = target.setdefault(key, ([], []))
    offset = sum(len(v) for v in vs)
    vs.append(verts)
    fs.append(faces + offset)

for index, node in enumerate(g.nodes):
    if node.mesh is None:
        continue
    top = group.get(index)
    name = node.name or ''
    if top is None or top.startswith('steering') or name in INTERIOR:
        continue
    if top.startswith('wheel_') and top != 'wheel_fl':
        # Only remember where the other wheels are
        m = world[index]
        pos = accessor(g.meshes[node.mesh].primitives[0].attributes.POSITION).astype(np.float64)
        p4 = np.hstack([pos, np.ones((len(pos), 1))]) @ m.T
        OTHER_WHEELS.setdefault(top, []).append(p4[:, :3])
        continue
    m = world[index]
    for prim in g.meshes[node.mesh].primitives:
        pos = accessor(prim.attributes.POSITION).astype(np.float64)
        idx = accessor(prim.indices).reshape(-1, 3).astype(np.int64) if prim.indices is not None \
            else np.arange(len(pos)).reshape(-1, 3)
        p4 = np.hstack([pos, np.ones((len(pos), 1))]) @ m.T
        key = material_group(name, g.materials[prim.material].name if prim.material is not None else '')
        if key == 'badge':
            continue  # leave out the maker's badges
        add(WHEEL_PARTS if top == 'wheel_fl' else BODY_PARTS, key, p4[:, :3], idx)

def merge(parts):
    return {k: (np.vstack(v), np.vstack(f)) for k, (v, f) in parts.items()}
body = merge(BODY_PARTS)
wheel = merge(WHEEL_PARTS)

# Orientation: longest horizontal extent is the length; headlights mark the front
allv = np.vstack([v for v, _ in body.values()])
lo, hi = allv.min(0), allv.max(0)
ext = hi - lo
print('extent (gltf)', ext)
length_axis = 0 if ext[0] > ext[2] else 2
front = body['headlight'][0][:, length_axis].mean() > (lo[length_axis] + hi[length_axis]) / 2
sign = 1 if front else -1
scale = 4.4 / ext[length_axis]
center = (lo + hi) / 2
ground = lo[1]

def to_game(v):
    c = v - np.array([center[0], ground, center[2]])
    forward = c[:, length_axis] * sign
    other = 2 if length_axis == 0 else 0
    side = c[:, other]
    # Right-handed: if forward = +gltf x, game z = gltf z; if forward = +gltf z, game z = -gltf x
    if length_axis == 0:
        z = side * sign
    else:
        z = -side * sign
    return np.stack([forward, c[:, 1], z], axis=1) * scale

def decimate(v, f, target):
    if len(f) <= target:
        return v, f
    ratio = 1 - target / len(f)
    vv, ff = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=ratio)
    return vv.astype(np.float64), ff.astype(np.int64)

def normals(v, f):
    n = np.zeros_like(v)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    length = np.linalg.norm(n, axis=1, keepdims=True)
    length[length == 0] = 1
    return n / length

BUDGET = {'paint': 30000, 'glass': 7000, 'chrome': 4000, 'taillight': 3000, 'headlight': 1200, 'carbon': 3000,
          'darkplastic': 6000, 'metal': 1500, 'badge': 300, 'tire': 900, 'rim': 2600, 'caliper': 500, 'hub': 300}

def write(parts, path, wheel_mode=False):
    stage = Usd.Stage.CreateNew(path.replace('.usdz', '.usdc'))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, '/car')
    stage.SetDefaultPrim(root.GetPrim())
    total = 0
    for key, (v, f) in sorted(parts.items()):
        v, f = decimate(v, f, BUDGET.get(key, 2000))
        n = normals(v, f)
        mesh = UsdGeom.Mesh.Define(stage, f'/car/{key}')
        mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in v]))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(f)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([int(i) for i in f.reshape(-1)]))
        mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in n]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        total += len(f)
        print(f'  {key}: {len(f)} triangles')
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(path.replace('.usdz', '.usdc')), path)
    os.remove(path.replace('.usdz', '.usdc'))
    print(path, 'triangles', total)

body_game = {k: (to_game(v), f) for k, (v, f) in body.items()}
wheel_game = {k: (to_game(v), f) for k, (v, f) in wheel.items()}
# Wheel: center on its axle; lift the car so the tyres touch y = 0
wv = np.vstack([v for v, _ in wheel_game.values()])
wc = (wv.min(0) + wv.max(0)) / 2
radius = (wv.max(0) - wv.min(0))[1] / 2
lift = radius - wc[1]
centers = {'wheel_fl': wc}
for name, parts in OTHER_WHEELS.items():
    allp = to_game(np.vstack(parts))
    centers[name] = (allp.min(0) + allp.max(0)) / 2
for name in sorted(centers):
    c = centers[name]
    print(f'{name}: x={c[0]:.3f} y={c[1] + lift:.3f} z={c[2]:.3f}')
print('wheel radius', radius, 'lift', lift)
wheel_game = {k: (v - wc, f) for k, (v, f) in wheel_game.items()}
body_game = {k: (v + np.array([0, lift, 0]), f) for k, (v, f) in body_game.items()}
bv = np.vstack([v for v, _ in body_game.values()])
print('body extent (game)', bv.min(0), bv.max(0))
write(body_game, os.path.join(out, 'car_body.usdz'))
write(wheel_game, os.path.join(out, 'car_wheel.usdz'), wheel_mode=True)
