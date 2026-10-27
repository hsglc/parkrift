"""Bakes the Meshy AI pedestrians (original characters, rigged by Meshy with walking and running
clips) into pose meshes for the game, using Blender as a Python module.

The game animates people by swapping a node's geometry (cheap for dozens of people), so each
character becomes one USDZ with meshes p0..p9:
  p0..p7  eight frames of the walk cycle (root motion removed)
  p8      standing (a walk frame with the feet together)
  p9      startled (a running frame, arms up and moving)
All face +X, feet on y = 0, decimated, one 512 px texture.

Usage: python convert_meshy_people.py <folder with p0..p5/walking.glb, running.glb> <Hop/Models>
"""
import sys, os, math
import bpy, bmesh
from mathutils import Vector, Matrix

PEOPLE = ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']
WALK_FRAMES = 8
BUDGET = 2600


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_clip(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    mesh = next(o for o in new if o.type == 'MESH')
    arm = next((o for o in new if o.type == 'ARMATURE'), None)
    action = None
    if arm and arm.animation_data and arm.animation_data.action:
        action = arm.animation_data.action
    return mesh, arm, action, new


def bake(mesh, frame, name):
    bpy.context.scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    data.transform(mesh.matrix_world)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def normalize(obj, height):
    """Feet on z = 0, centered, facing +X (Meshy characters face -Y in Blender)."""
    m = obj.data
    xs = [v.co for v in m.vertices]
    lo_z = min(v.z for v in xs)
    # Root motion: center on the hips (vertices in the middle height band)
    band = [v for v in xs if lo_z + height * 0.45 < v.z < lo_z + height * 0.6] or xs
    cx = sum(v.x for v in band) / len(band)
    cy = sum(v.y for v in band) / len(band)
    m.transform(Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation(Vector((-cx, -cy, -lo_z))))
    m.update()


def decimate(obj):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > BUDGET:
        mod = obj.modifiers.new('d', 'DECIMATE')
        mod.ratio = BUDGET / tris
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def feet_apart(obj):
    feet = [v.co for v in obj.data.vertices if v.co.z < 0.12]
    return max(v.x for v in feet) - min(v.x for v in feet) if feet else 9


def convert(pid, src, out):
    clear()
    folder = os.path.join(src, pid)
    walk_mesh, walk_arm, walk_action, _ = import_clip(os.path.join(folder, 'walking.glb'))
    start, end = walk_action.frame_range if walk_action else (1, 30)
    height = None
    poses = []
    for k in range(WALK_FRAMES):
        frame = int(round(start + (end - start) * k / WALK_FRAMES))
        obj = bake(walk_mesh, frame, f'p{k}')
        if height is None:
            zs = [v.co.z for v in obj.data.vertices]
            height = max(zs) - min(zs)
        normalize(obj, height)
        poses.append(obj)
    # Standing: the walk frame with the feet closest together
    stand_source = min(poses, key=feet_apart)
    stand = stand_source.copy()
    stand.data = stand_source.data.copy()
    stand.name = 'p8'
    bpy.context.scene.collection.objects.link(stand)
    poses.append(stand)
    # Startled: a frame of the running clip
    run_mesh, run_arm, run_action, run_new = import_clip(os.path.join(folder, 'running.glb'))
    rs, re_ = run_action.frame_range if run_action else (1, 20)
    startled = bake(run_mesh, int(rs + (re_ - rs) * 0.25), 'p9')
    normalize(startled, height)
    poses.append(startled)
    # Only the baked meshes remain
    for o in list(bpy.data.objects):
        if o not in poses:
            bpy.data.objects.remove(o, do_unlink=True)
    tris = [decimate(o) for o in poses]
    for o in poses:
        o.data.name = o.name
        for k, layer in enumerate(o.data.uv_layers):
            layer.name = 'st' if k == 0 else f'st{k}'
    for mat in bpy.data.materials:
        mat.name = f'{pid}_skin'
    for k, img in enumerate(bpy.data.images):
        img.name = f'{pid}_tex{k}'
    bpy.ops.object.select_all(action='DESELECT')
    for o in poses:
        o.select_set(True)
    bpy.context.view_layer.objects.active = poses[0]
    bpy.ops.wm.usd_export(filepath=os.path.join(out, f'person_{pid}.usdz'), selected_objects_only=True, export_materials=True,
                          export_textures_mode='NEW', overwrite_textures=True, export_uvmaps=True, export_normals=True,
                          generate_preview_surface=True, generate_materialx_network=False, convert_orientation=True,
                          export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          export_animation=False, triangulate_meshes=True, export_lights=False, export_cameras=False,
                          export_armatures=False, export_shapekeys=False,
                          usdz_downscale_size='512', merge_parent_xform=True)
    print(f'PERSON {pid}: height {height:.2f} m, tris {tris}')


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    for pid in PEOPLE:
        convert(pid, args[0], args[1])
