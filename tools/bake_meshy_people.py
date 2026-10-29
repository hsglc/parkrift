"""Bakes the two Meshy pedestrians (a woman and a man: realistic, 2K textured, rigged by Meshy
with its walking and running clips plus idle, angry, dodge, knock-down and phone clips from its
animation library) into pose frames for the game, with Blender as a Python module.

The game animates people by swapping a node's geometry (cheap for dozens of people, no
skinning), so every clip is sampled into frames of the same mesh: the skinned mesh is reduced
once (decimation before the armature, so all frames share topology, UVs and triangles) and each
frame stores only positions and normals.

Output per character:
  Hop/Models/ped_<name>.bin   'PED1', vertex count, index count, clip count; UVs (float32 x2),
                              indices (uint32); per clip: name, frame count, frames per second,
                              loop flag, then per frame positions (float16 x3) and normals
                              (float16 x3). Metres, game axes (y up), facing +x, feet on y = 0.
  Hop/Textures/ped_<name>_{diff,nor,rough}.jpg

Usage: python bake_meshy_people.py <glb root with woman/, man/> <Hop/Models> <Hop/Textures>
"""
import sys, os, struct, math
import bpy
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

SRC, MODELS, TEXTURES = sys.argv[-3:]
TRIANGLES = 14000
# clip: (frames, loop, root motion: 'cycle' removes it every frame, 'start' keeps the travel)
# Longest stretch of a clip used (seconds): the angry clip runs on for 20 s of talking
LIMIT = {'angry': 2.6, 'phone': 3.0, 'idle': 3.0}   # idle and phone play back and forth in the game
CLIPS = {
    'walk': (16, True, 'cycle'),
    'run': (12, True, 'cycle'),
    'idle': (10, True, 'cycle'),
    'phone': (12, True, 'cycle'),
    'angry': (16, True, 'cycle'),
    'dodge': (12, False, 'start'),
    'knockdown': (14, False, 'start'),
}
TURN = Matrix.Rotation(math.pi / 2, 4, 'Z')          # Meshy faces -y; the game wants +x


def import_clip(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = max((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: len(o.data.polygons))
    arm = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
    action = arm.animation_data.action if arm and arm.animation_data else None
    return mesh, arm, action


def hips(arm):
    names = [b.name for b in arm.pose.bones]
    for n in names:
        if 'hip' in n.lower() or 'pelvis' in n.lower():
            return arm.pose.bones[n]
    return arm.pose.bones[0]


def textures(mesh):
    found = {}
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type != 'TEX_IMAGE' or not node.image:
            continue
        for link in node.outputs[0].links:
            t = link.to_node
            if t.type == 'NORMAL_MAP':
                found['normal'] = node.image
            elif t.type == 'BSDF_PRINCIPLED':
                found['color' if link.to_socket.name == 'Base Color' else 'mr'] = node.image
            elif t.type in ('SEPARATE_COLOR', 'SEPRGB'):
                found['mr'] = node.image
    return found


def pixels(image):
    w, h = image.size
    a = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[::-1]


def save_textures(name, mesh):
    maps = textures(mesh)
    c = pixels(maps['color'])
    Image.fromarray((np.clip(c[..., :3], 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(TEXTURES, f'ped_{name}_diff.jpg'), quality=92)
    if 'normal' in maps:
        n = pixels(maps['normal'])
        Image.fromarray((np.clip(n[..., :3], 0, 1) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(
            os.path.join(TEXTURES, f'ped_{name}_nor.jpg'), quality=90)
    if 'mr' in maps:
        m = pixels(maps['mr'])
        Image.fromarray((np.clip(m[..., 1], 0, 1) * 255).astype(np.uint8)).convert('RGB').resize((1024, 1024), Image.LANCZOS).save(
            os.path.join(TEXTURES, f'ped_{name}_rough.jpg'), quality=88)


def reduce(mesh):
    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    if tris <= TRIANGLES:
        return
    mod = mesh.modifiers.new('reduce', 'DECIMATE')
    mod.ratio = TRIANGLES / tris
    mod.use_collapse_triangulate = True
    # Before the armature: one reduced mesh, then skinned (all frames share it)
    while mesh.modifiers.find('reduce') > 0:
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.modifier_move_up(modifier='reduce')


def sample(mesh, arm, frame, offset):
    """The skinned, reduced mesh at a frame: triangles, positions, normals, UVs (game axes)."""
    scene = bpy.context.scene
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(depsgraph)
    data = ev.to_mesh()
    data.calc_loop_triangles()
    m = mesh.matrix_world
    world = [m @ v.co for v in data.vertices]
    # Root motion: subtract the hips' ground position (every frame, or the first one's)
    root = offset if offset is not None else (arm.matrix_world @ hips(arm).head) if arm else Vector((0, 0, 0))
    # Split vertices by loop so UV seams stay sharp: one game vertex per (vertex, uv)
    uv_layer = data.uv_layers.active.data
    key_index = {}
    verts, uvs, normals, indices = [], [], [], []
    normal_matrix = m.to_3x3().inverted().transposed()
    for tri in data.loop_triangles:
        for li in tri.loops:
            loop = data.loops[li]
            uv = uv_layer[li].uv
            key = (loop.vertex_index, round(uv.x, 5), round(uv.y, 5))
            k = key_index.get(key)
            if k is None:
                k = len(verts)
                key_index[key] = k
                p = TURN @ (world[loop.vertex_index] - Vector((root.x, root.y, 0)))
                n = (TURN.to_3x3() @ (normal_matrix @ data.vertices[loop.vertex_index].normal)).normalized()
                verts.append((p.x, p.z, -p.y))
                normals.append((n.x, n.z, -n.y))
                uvs.append((uv.x, 1 - uv.y))
            indices.append(k)
    ev.to_mesh_clear()
    return verts, normals, uvs, indices, root


def bake(name):
    folder = os.path.join(SRC, name)
    out = bytearray()
    shared = None
    ground = None
    clips = []
    for clip, (count, loop, motion) in CLIPS.items():
        mesh, arm, action = import_clip(os.path.join(folder, clip + '.glb'))
        if shared is None:
            save_textures(name, mesh)
        reduce(mesh)
        start, end = action.frame_range if action else (1, 24)
        fps = bpy.context.scene.render.fps
        if clip in LIMIT:
            end = min(end, start + LIMIT[clip] * fps)
        span = end - start
        frames = []
        first_root = None
        for k in range(count):
            t = start + span * k / (count if loop else max(1, count - 1))
            verts, normals, uvs, indices, root = sample(mesh, arm, t, first_root if motion == 'start' else None)
            if motion == 'start' and first_root is None:
                first_root = root
            frames.append((verts, normals))
            if shared is None:
                shared = (uvs, indices)
                ground = min(v[1] for v in verts)
            elif len(verts) != len(shared[0]) or indices != shared[1]:
                raise SystemExit(f'{name}/{clip}: topology differs ({len(verts)} vs {len(shared[0])})')
        duration = span / fps
        clips.append((clip, frames, count / max(duration, 0.1), loop))
        print(f'  {name} {clip}: {count} frames over {duration:.2f} s', flush=True)
    uvs, indices = shared
    vc, ic = len(uvs), len(indices)
    out += b'PED1' + struct.pack('<III', vc, ic, len(clips))
    out += np.array(uvs, np.float32).tobytes()
    out += np.array(indices, np.uint32).tobytes()
    for clip, frames, fps, loop in clips:
        label = clip.encode()
        out += struct.pack('<B', len(label)) + label + struct.pack('<IfB', len(frames), fps, 1 if loop else 0)
        for verts, normals in frames:
            p = np.array(verts, np.float32)
            p[:, 1] -= ground                   # feet on the ground
            out += p.astype(np.float16).tobytes()
            out += np.array(normals, np.float32).astype(np.float16).tobytes()
    with open(os.path.join(MODELS, f'ped_{name}.bin'), 'wb') as f:
        f.write(bytes(out))
    print(f'PED {name}: {vc} vertices, {ic // 3} triangles, {len(out) / 1e6:.1f} MB', flush=True)


for person in ('woman', 'man'):
    bake(person)
