"""Bakes Polyfork's free low poly characters (commercial use, no attribution; see README) into the
game's pose meshes, with Polyfork's free Mixamo-named clips (Walk, Idle, Run).

The game animates people by swapping a node's geometry, so each character becomes one USDZ whose
top-level prims p0..p9 are the poses:
  p0..p7  eight frames of the Walk clip (in place)
  p8      standing (Idle, first frame)
  p9      startled (a frame of the Run clip)
Each pose is one flat-shaded mesh with a single material whose colours come from a small palette
texture (one draw call per person); it faces +X (the characters face +Z) and stands on y = 0.

Skinning is done here: the skeleton's rest pose has identity rotations (translations in the node
matrices), the clips give local rotations per bone and a hips offset, and every vertex follows
its joints through the inverse bind matrices.

Usage: python3 convert_polyfork_people.py <glb folder> <clips folder> <Hop/Models> id [id ...]
"""
import sys, os, json
import numpy as np
import pygltflib
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils

WALK_FRAMES = 8


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1]])


class Character:
    def __init__(self, path):
        self.g = pygltflib.GLTF2().load(path)
        self.blob = self.g.binary_blob()
        self.parent = {}
        for i, n in enumerate(self.g.nodes):
            for c in n.children or []:
                self.parent[c] = i

    def acc(self, i):
        a = self.g.accessors[i]
        bv = self.g.bufferViews[a.bufferView]
        comp = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}[a.componentType]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a.type]
        size = np.dtype(comp).itemsize * n
        stride = bv.byteStride or size
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        raw = np.frombuffer(self.blob, dtype=np.uint8, count=stride * (a.count - 1) + size, offset=off)
        rows = np.lib.stride_tricks.as_strided(raw, shape=(a.count, size), strides=(stride, 1))
        out = np.frombuffer(rows.copy().tobytes(), dtype=comp).reshape(a.count, n).astype(np.float64)
        if a.normalized and comp != np.float32:
            out /= np.iinfo(comp).max
        return out

    def local_rest(self, i):
        n = self.g.nodes[i]
        if n.matrix:
            return np.array(n.matrix, dtype=np.float64).reshape(4, 4).T
        m = np.eye(4)
        if n.translation:
            m[:3, 3] = n.translation
        if n.rotation:
            m = m @ quat_matrix(n.rotation)
        if n.scale:
            m = m @ np.diag(list(n.scale) + [1])
        return m

    def world(self, pose):
        """World matrices of every node; `pose` maps bone name -> (quaternion, hips offset)."""
        cache = {}

        def w(i):
            if i in cache:
                return cache[i]
            local = self.local_rest(i)
            name = self.g.nodes[i].name
            if name in pose:
                q, offset = pose[name]
                t = local[:3, 3].copy()
                if offset is not None:
                    t = t + offset
                local = quat_matrix(q)
                local[:3, 3] = t
            m = w(self.parent[i]) @ local if i in self.parent else local
            cache[i] = m
            return m
        return w

    def posed(self, pose):
        """Triangles (positions, colours) of every skinned mesh in a pose."""
        w = self.world(pose)
        tris, cols = [], []
        for ni, node in enumerate(self.g.nodes):
            if node.mesh is None:
                continue
            skin = self.g.skins[node.skin] if node.skin is not None else None
            for prim in self.g.meshes[node.mesh].primitives:
                pos = self.acc(prim.attributes.POSITION)
                col = self.acc(prim.attributes.COLOR_0)[:, :3] if prim.attributes.COLOR_0 is not None else np.full((len(pos), 3), 0.7)
                p4 = np.c_[pos, np.ones(len(pos))]
                if skin is not None:
                    ibm = self.acc(skin.inverseBindMatrices).reshape(-1, 4, 4).transpose(0, 2, 1)
                    mats = np.stack([w(j) @ ibm[k] for k, j in enumerate(skin.joints)])
                    joints = self.acc(prim.attributes.JOINTS_0).astype(int)
                    weights = self.acc(prim.attributes.WEIGHTS_0)
                    out = np.zeros((len(pos), 4))
                    for k in range(4):
                        out += weights[:, k:k + 1] * np.einsum('nij,nj->ni', mats[joints[:, k]], p4)
                else:
                    out = (w(ni) @ p4.T).T
                idx = self.acc(prim.indices).astype(int).reshape(-1) if prim.indices is not None else np.arange(len(pos))
                tris.append(out[idx, :3].reshape(-1, 3, 3))
                cols.append(col[idx].reshape(-1, 3, 3).mean(axis=1))
        return np.concatenate(tris), np.concatenate(cols)


def clip_pose(clip, frame):
    pose = {}
    for bone, values in clip['tracks'].items():
        q = values[frame * 4:frame * 4 + 4]
        pose[bone] = (q, None)
    h = clip['hips'][frame * 3:frame * 3 + 3]
    q, _ = pose['Hips']
    pose['Hips'] = (q, np.array(h, dtype=np.float64))
    return pose


def write_character(poses, path):
    """One mesh per pose with a single material: the colours live in a small palette texture
    (8 x 8 px per colour) and every triangle's UVs point at its colour, so a person is one draw
    call (one material per colour made 20 draw calls per person)."""
    from PIL import Image
    usdc = path[:-5] + '.usdc'
    palette_name = os.path.basename(path)[:-5] + '_palette.png'
    palette_path = os.path.join(os.path.dirname(usdc), palette_name)
    keys = sorted({tuple(np.round(c, 3)) for _, cols in poses.values() for c in cols})
    slot = {k: i for i, k in enumerate(keys)}
    cell = 8
    columns = 16
    rows = (len(keys) + columns - 1) // columns
    image = np.zeros((rows * cell, columns * cell, 3), dtype=np.uint8)
    for k, i in slot.items():
        r, c = divmod(i, columns)
        # glTF vertex colours are linear; the texture is sRGB
        srgb = np.clip(np.array(k), 0, 1) ** (1 / 2.2)
        image[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = (srgb * 255).round()
    Image.fromarray(image).save(palette_path)

    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, '/person')
    stage.SetDefaultPrim(root.GetPrim())
    mat = UsdShade.Material.Define(stage, '/person/mats/skin')
    shader = UsdShade.Shader.Define(stage, '/person/mats/skin/surface')
    shader.CreateIdAttr('UsdPreviewSurface')
    shader.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(0.85)
    shader.CreateInput('metallic', Sdf.ValueTypeNames.Float).Set(0.0)
    reader = UsdShade.Shader.Define(stage, '/person/mats/skin/st')
    reader.CreateIdAttr('UsdPrimvarReader_float2')
    reader.CreateInput('varname', Sdf.ValueTypeNames.Token).Set('st')
    tex = UsdShade.Shader.Define(stage, '/person/mats/skin/palette')
    tex.CreateIdAttr('UsdUVTexture')
    tex.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(palette_name)
    tex.CreateInput('st', Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), 'result')
    tex.CreateOutput('rgb', Sdf.ValueTypeNames.Float3)
    shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.ConnectableAPI(), 'rgb')
    mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), 'surface')

    total = 0
    width, height = columns * cell, rows * cell
    for name, (tris, cols) in poses.items():
        n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        pts = tris.reshape(-1, 3)
        uvs = []
        for c in cols:
            r, col = divmod(slot[tuple(np.round(c, 3))], columns)
            u = (col * cell + cell / 2) / width
            v = 1 - (r * cell + cell / 2) / height
            uvs += [(u, v)] * 3
        mesh = UsdGeom.Mesh.Define(stage, f'/person/{name}')
        mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, p)) for p in pts]))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(tris)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(list(range(len(pts)))))
        mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in np.repeat(n, 3, axis=0)]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        st = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
        st.Set(Vt.Vec2fArray([Gf.Vec2f(float(a), float(b)) for a, b in uvs]))
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(mat)
        total += len(tris)
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), path)
    os.remove(usdc)
    os.remove(palette_path)
    return total, len(keys)


def convert(cid, index, glbs, clips_dir, out):
    character = Character(os.path.join(glbs, cid + '.glb'))
    walk = json.load(open(os.path.join(clips_dir, 'anim-walk.json')))
    idle = json.load(open(os.path.join(clips_dir, 'anim-idle.json')))
    run = json.load(open(os.path.join(clips_dir, 'anim-run.json')))
    frames = len(walk['times'])
    poses = {}
    picks = [(walk, int(round(k * frames / WALK_FRAMES)) % frames) for k in range(WALK_FRAMES)]
    picks += [(idle, 0), (run, len(run['times']) // 4)]
    for k, (clip, frame) in enumerate(picks):
        tris, cols = character.posed(clip_pose(clip, frame))
        pts = tris.reshape(-1, 3)
        # In place: center on the hips (middle band), feet on the ground, face +X
        y0 = pts[:, 1].min()
        band = pts[(pts[:, 1] > y0 + 0.8) & (pts[:, 1] < y0 + 1.1)]
        cx, cz = (band[:, 0].mean(), band[:, 2].mean()) if len(band) else (0, 0)
        pts = pts - np.array([cx, y0, cz])
        turned = np.stack([pts[:, 2], pts[:, 1], -pts[:, 0]], axis=1)
        poses[f'p{k}'] = (turned.reshape(-1, 3, 3), cols)
    tris, mats = write_character(poses, os.path.join(out, f'person_p{index}.usdz'))
    height = poses['p8'][0].reshape(-1, 3)[:, 1].max()
    print(f'PERSON {index} {cid}: {tris // len(poses)} tris per pose, {mats} colours, height {height:.2f} m')


if __name__ == '__main__':
    glbs, clips_dir, out = sys.argv[1:4]
    for index, cid in enumerate(sys.argv[4:]):
        convert(cid, index, glbs, clips_dir, out)
