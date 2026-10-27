"""Converts the two Khronos sample cars used in the garage into light USDZ files for SceneKit plus a
cars.json catalog (wheel positions, exhaust points, stats).

Sources (all free):
  * "Car Concept" — Khronos glTF Sample Assets, CC BY 4.0 (based on a CC0 model by Unity Fan);
    Khronos logos and the licence plate are removed
  * "Toy Car" — Khronos glTF Sample Assets, CC0

Each car: one prim per material group (paint, glass, chrome, ...), interiors dropped, meshes
decimated for phones. Game axes: +x forward, +y up, length 4.4 m, tyres on y = 0.

Usage: python3 convert_cars.py CarConcept.glb ToyCar.glb out_dir
(The other garage cars are original Meshy AI designs: tools/convert_meshy_cars.py.)
"""
import sys, os, json
import numpy as np
import pygltflib
import fast_simplification
from pxr import Usd, UsdGeom, Vt, Gf, Sdf, UsdUtils

LENGTH = 4.4


def load(path):
    g = pygltflib.GLTF2().load(path)
    return g, g.binary_blob()


def accessor(g, blob, i):
    a = g.accessors[i]
    bv = g.bufferViews[a.bufferView]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a.componentType]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
    size = np.dtype(comp).itemsize
    stride = bv.byteStride or n * size
    start = (bv.byteOffset or 0) + (a.byteOffset or 0)
    if stride == n * size:
        return np.frombuffer(blob, dtype=comp, count=a.count * n, offset=start).reshape(a.count, n).copy()
    raw = np.frombuffer(blob, dtype=np.uint8, count=stride * (a.count - 1) + n * size, offset=start)
    out = np.empty((a.count, n), dtype=comp)
    for k in range(a.count):
        out[k] = np.frombuffer(raw[k * stride:k * stride + n * size].tobytes(), dtype=comp)
    return out


def local_matrix(node):
    if node.matrix:
        return np.array(node.matrix, dtype=np.float64).reshape(4, 4).T
    t = np.array(node.translation or [0, 0, 0], dtype=np.float64)
    x, y, z, w = node.rotation or [0, 0, 0, 1]
    s = np.array(node.scale or [1, 1, 1], dtype=np.float64)
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def collect(g, blob, classify):
    """Walks the scene; classify(node_name, ancestor_names, material_name) -> (target, group) or None.
    target is 'body' or a wheel key. Returns {target: {group: [(verts, faces, uvs)]}}."""
    parts = {}

    def walk(index, parent, ancestors):
        node = g.nodes[index]
        world = parent @ local_matrix(node)
        name = node.name or ''
        if node.mesh is not None:
            for prim in g.meshes[node.mesh].primitives:
                if prim.mode not in (None, 4):
                    continue
                material = g.materials[prim.material].name if prim.material is not None else ''
                result = classify(name, ancestors, material or '')
                if result is None:
                    continue
                target, group = result
                pos = accessor(g, blob, prim.attributes.POSITION).astype(np.float64)
                idx = (accessor(g, blob, prim.indices).reshape(-1, 3).astype(np.int64) if prim.indices is not None
                       else np.arange(len(pos)).reshape(-1, 3))
                uv = accessor(g, blob, prim.attributes.TEXCOORD_0).astype(np.float64) if prim.attributes.TEXCOORD_0 is not None else None
                p4 = np.hstack([pos, np.ones((len(pos), 1))]) @ world.T
                parts.setdefault(target, {}).setdefault(group, []).append((p4[:, :3], idx, uv))
        for child in node.children or []:
            walk(child, world, ancestors + [name])

    for root in g.scenes[g.scene or 0].nodes:
        walk(root, np.eye(4), [])
    return parts


def merge(chunks):
    vs, fs, uvs = [], [], []
    offset = 0
    has_uv = all(c[2] is not None for c in chunks)
    for v, f, uv in chunks:
        vs.append(v)
        fs.append(f + offset)
        if has_uv:
            uvs.append(uv)
        offset += len(v)
    return np.vstack(vs), np.vstack(fs), (np.vstack(uvs) if has_uv else None)


def decimate(v, f, target, uv=None):
    """Quadric decimation; UVs (when kept) are carried over from the nearest original vertex."""
    if len(f) <= target:
        return v, f, uv
    vv, ff = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - target / len(f))
    vv = vv.astype(np.float64)
    if uv is not None:
        from scipy.spatial import cKDTree
        _, nearest = cKDTree(v).query(vv)
        uv = uv[nearest]
    return vv, ff.astype(np.int64), uv


def normals(v, f):
    n = np.zeros_like(v)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    length = np.linalg.norm(n, axis=1, keepdims=True)
    length[length == 0] = 1
    return n / length


def write_usdz(groups, path):
    usdc = path[:-5] + '.usdc'
    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, '/car')
    stage.SetDefaultPrim(root.GetPrim())
    total = 0
    for key, (v, f, uv) in sorted(groups.items()):
        mesh = UsdGeom.Mesh.Define(stage, f'/car/{key}')
        mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in v]))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(f)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([int(i) for i in f.reshape(-1)]))
        mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in normals(v, f)]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        if uv is not None:
            st = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
            st.Set(Vt.Vec2fArray([Gf.Vec2f(float(a), float(1 - b)) for a, b in uv]))
        total += len(f)
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), path)
    os.remove(usdc)
    return total


def convert(spec, out):
    g, blob = load(spec['src'])
    parts = collect(g, blob, spec['classify'])
    body = {k: merge(v) for k, v in parts['body'].items()}
    allv = np.vstack([v for v, _, _ in body.values()])
    lo, hi = allv.min(0), allv.max(0)
    ext = hi - lo
    up_axis = int(np.argmin(ext))
    length_axis = int(np.argmax(ext))
    side_axis = 3 - up_axis - length_axis
    center = (lo + hi) / 2
    f = np.zeros(3)
    f[length_axis] = spec['forward_sign'](parts, length_axis, center)
    u = np.zeros(3)
    u[up_axis] = spec.get('up_sign', 1)
    s = np.cross(f, u)
    scale = LENGTH / ext[length_axis]

    def to_game(v):
        c = v - center
        return np.stack([c @ f, c @ u, c @ s], axis=1) * scale

    body = {k: (to_game(v), fa, uv) for k, (v, fa, uv) in body.items()}
    wheels = {k: {g2: merge(c) for g2, c in v.items()} for k, v in parts.items() if k != 'body'}
    wheels = {k: {g2: (to_game(v), fa, uv) for g2, (v, fa, uv) in v.items()} for k, v in wheels.items()}

    # Ground: lowest point of the tyres (or of the body when wheels are part of it)
    pts = [v for v, _, _ in body.values()] + [v for w in wheels.values() for v, _, _ in w.values()]
    ground = min(p[:, 1].min() for p in pts)
    lift = np.array([0, -ground, 0])
    body = {k: (v + lift, fa, uv) for k, (v, fa, uv) in body.items()}
    wheels = {k: {g2: (v + lift, fa, uv) for g2, (v, fa, uv) in w.items()} for k, w in wheels.items()}

    if 'roof' in spec:
        body = spec['roof'](body)
    if 'split_wheels' in spec:
        body, wheels = spec['split_wheels'](body)

    spots = []
    wheel_radius = 0.34
    if wheels:
        for key, groups in sorted(wheels.items()):
            allw = np.vstack([v for v, _, _ in groups.values()])
            c = (allw.min(0) + allw.max(0)) / 2
            wheel_radius = (allw.max(0) - allw.min(0))[1] / 2
            spots.append([round(float(c[0]), 3), round(float(c[1]), 3), round(float(c[2]), 3), bool(c[0] > 0)])
        # Export the first wheel, centered on its axle
        first = sorted(wheels)[0]
        groups = wheels[first]
        allw = np.vstack([v for v, _, _ in groups.values()])
        c = (allw.min(0) + allw.max(0)) / 2
        model_side = 1 if c[2] > 0 else -1
        wgroups = {}
        for g2, (v, fa, uv) in groups.items():
            wgroups[g2] = decimate(v - c, fa, spec.get('wheel_budget', spec['budget']).get(g2, 1500), uv if g2 == 'textured' else None)
        wtris = write_usdz(wgroups, os.path.join(out, f"{spec['id']}_wheel.usdz"))
    else:
        model_side = 1
        wtris = 0

    bgroups = {}
    for g2, (v, fa, uv) in body.items():
        bgroups[g2] = decimate(v, fa, spec['budget'].get(g2, 2500), uv if g2 == 'textured' else None)
    btris = write_usdz(bgroups, os.path.join(out, f"{spec['id']}_body.usdz"))
    allb = np.vstack([v for v, _, _ in body.values()])
    rear = float(allb[:, 0].min())
    print(f"{spec['id']}: body {btris} tris, wheel {wtris} tris, groups {sorted(bgroups)}")
    for texture in spec.get('textures', []):
        texture(g, blob, out)
    return {
        'id': spec['id'], 'hasWheelModel': bool(wheels), 'wheelModelSide': model_side,
        'wheelRadius': round(float(wheel_radius), 3), 'wheels': spots,
        'exhausts': [[round(rear + 0.02, 3), e[0], e[1]] for e in spec['exhausts']],
        'height': round(float(allb[:, 1].max()), 3), 'width': round(float(allb[:, 2].max() - allb[:, 2].min()), 3),
    }


# ---------------------------------------------------------------- per-car rules

def orient(v, f, outward):
    """Flips triangles so their normals point along outward(centroid)."""
    f = f.copy()
    for n, tri in enumerate(f):
        a, b, c = v[tri]
        if np.dot(np.cross(b - a, c - a), outward((a + b + c) / 3)) < 0:
            f[n] = tri[[0, 2, 1]]
    return f


def headlight_forward(parts, axis, center):
    head = np.vstack([v for v, _, _ in parts['body'].get('headlight', [])])
    return 1.0 if head[:, axis].mean() > center[axis] else -1.0


def concept_classify(name, ancestors, material):
    chain = ancestors + [name]
    if name.startswith('License') or 'Wiper' in name:
        return None
    if any(n.startswith('Interior') for n in chain) or 'Steering' in name:
        return 'body', 'interior'
    wheel = next((n for n in chain if n.startswith('Wheel')), None)
    target = {'WheelFrontL': 'fl', 'WheelFrontR': 'fr', 'WheelRearL': 'rl', 'WheelRearR': 'rr'}.get(wheel, 'body')
    m = material
    if m.startswith('Paint 1'):
        group = 'paint'
    elif m.startswith('Paint 2'):
        group = 'paint2'
    elif m == 'Glass':
        group = 'glass'
    elif m == 'Brakelight':
        group = 'taillight'
    elif m in ('Headlight', 'Signallight'):
        group = 'headlight'
    elif m == 'Mirror':
        group = 'chrome'
    elif m in ('Rim1', 'Rim2'):
        group = 'rim'
    elif m in ('Tireside', 'Tiretread'):
        group = 'tire'
    elif m == 'Brake':
        group = 'caliper'
    elif m == 'Disc':
        group = 'metal'
    else:
        group = 'darkplastic'
    return target, group


def toy_classify(name, ancestors, material):
    if name == 'Fabric' or name.startswith('Camera'):
        return None
    if name == 'Glass':
        return 'body', 'glass'
    if name == 'ToyCar':
        return 'body', 'textured'
    return None


def toy_split_wheels(body):
    """The toy car is one mesh; cut the four wheels out (faces inside each wheel's cylinder) so
    they can spin and steer."""
    v, f, uv = body['textured']
    taken = np.zeros(len(f), dtype=bool)
    wheels = {}
    for key, cx, side in [('fl', 1.555, -1), ('fr', 1.555, 1), ('rl', -1.192, -1), ('rr', -1.192, 1)]:
        inside = ((v[:, 0] - cx) ** 2 + (v[:, 1] - 0.302) ** 2 < 0.318 ** 2) & (v[:, 2] * side > 0.62)
        faces = inside[f].all(axis=1) & ~taken
        taken |= faces
        used = np.unique(f[faces])
        remap = -np.ones(len(v), dtype=np.int64)
        remap[used] = np.arange(len(used))
        wheels[key] = {'textured': (v[used], remap[f[faces]], uv[used])}
    rest = f[~taken]
    used = np.unique(rest)
    remap = -np.ones(len(v), dtype=np.int64)
    remap[used] = np.arange(len(used))
    body = dict(body)
    body['textured'] = (v[used], remap[rest], uv[used])
    return body, wheels


def toy_texture(g, blob, out):
    material = next(m for m in g.materials if m.name == 'ToyCar')
    index = material.pbrMetallicRoughness.baseColorTexture.index
    image = g.images[g.textures[index].source]
    bv = g.bufferViews[image.bufferView]
    data = blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
    ext = '.png' if image.mimeType == 'image/png' else '.jpg'
    from PIL import Image
    import io
    img = Image.open(io.BytesIO(data)).convert('RGB')
    img.thumbnail((1024, 1024))
    # Paint areas (the green body colour) become neutral grey so the game can tint them with any
    # paint colour through retro_mask.png; decals, tyres and chrome keep their colours.
    a = np.asarray(img).astype(np.float64) / 255
    r, gr, b = a[..., 0], a[..., 1], a[..., 2]
    mask = (gr > r * 1.25) & (gr > b * 1.1)
    shade = np.clip(gr / np.median(gr[mask]) * 0.92, 0, 1)
    a[mask] = shade[mask][:, None]
    Image.fromarray((a * 255).astype(np.uint8)).save(os.path.join(out, 'retro_basecolor.jpg'), quality=88)
    Image.fromarray((mask * 255).astype(np.uint8)).resize((512, 512)).convert('RGB').save(os.path.join(out, 'retro_mask.png'))
    print('retro texture', img.size, ext)


def toy_forward(parts, axis, center):
    # The round white headlights sit at the end where the glass mean is lower (checked with a
    # textured render); the red taillights are at the other end.
    glass = np.vstack([v for v, _, _ in parts['body']['glass']])
    return -1.0 if glass[:, axis].mean() > center[axis] else 1.0


if __name__ == '__main__':
    concept, toy, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    common = {'tire': 900, 'rim': 2600, 'caliper': 500, 'hub': 300, 'metal': 1500}
    specs = [
        {'id': 'concept', 'src': concept, 'classify': concept_classify, 'forward_sign': headlight_forward,
         'exhausts': [(0.38, 0.32), (0.38, -0.32)],
         'budget': dict(common, paint=26000, interior=4000, paint2=9000, glass=5000, chrome=1200, taillight=800, headlight=800, darkplastic=6000, rim=3200)},
        {'id': 'retro', 'src': toy, 'classify': toy_classify, 'forward_sign': toy_forward,
         'exhausts': [(0.3, 0.45)], 'split_wheels': toy_split_wheels, 'wheel_budget': {'textured': 3000},
         'budget': {'glass': 2500, 'textured': 36000}, 'textures': [toy_texture]},
    ]
    catalog = [convert(spec, out) for spec in specs]
    with open(os.path.join(out, 'cars.json'), 'w') as fh:
        json.dump(catalog, fh, indent=1)
    print(json.dumps(catalog, indent=1))
