"""Turns Poly Haven (CC0) models into venue props, the same way as the Meshy street props:
joined, reduced to a mobile budget, stood on the origin at real size, written as USDZ with
"<name>", "<name>_lod" and "<name>_far" meshes, and their colour, normal and roughness maps as
JPGs (made into asset-catalog texture sets by make_texture_sets.py).

Usage: python (bpy) convert_polyhaven_props.py <models dir> <Hop/Models> <maps out dir>
"""
import sys, os, json
import bpy
import numpy as np
from PIL import Image

SRC, MODELS, MAPS = sys.argv[-3:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# source: (game name, triangles up close, height in metres)
PROPS = {
    'Barrel_01': ('v_barrel', 2600, 0.95),
    'wooden_crate_01': ('v_crate', 6000, 0.75),
    'concrete_road_barrier_02': ('v_barrier', 6000, 1.0),
}


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def textures(obj):
    found = {}
    for node in obj.data.materials[0].node_tree.nodes:
        if node.type != 'TEX_IMAGE' or not node.image:
            continue
        for link in node.outputs[0].links:
            target = link.to_node
            if target.type == 'NORMAL_MAP':
                found['normal'] = node.image
            elif target.type == 'BSDF_PRINCIPLED':
                found['color' if link.to_socket.name == 'Base Color' else 'mr'] = node.image
            elif target.type in ('SEPARATE_COLOR', 'SEPRGB'):
                found['mr'] = node.image
    return found


def pixels(image):
    w, h = image.size
    a = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[::-1]


def decimate(obj, target):
    faces = len(obj.data.polygons)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    while faces > target * 1.05:
        mod = obj.modifiers.new('d', 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = max(target / faces, 0.08)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier='d')
        new = len(obj.data.polygons)
        if new >= faces:
            break
        faces = new


def stand(obj, height):
    from mathutils import Matrix
    co = np.array([v.co[:] for v in obj.data.vertices])
    zmin, zmax = co[:, 2].min(), co[:, 2].max()
    cx = (co[:, 0].min() + co[:, 0].max()) / 2
    cy = (co[:, 1].min() + co[:, 1].max()) / 2
    s = height / (zmax - zmin)
    obj.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -zmin)))
    obj.data.update()


def export(objs, name):
    for obj in objs:
        obj.data.name = obj.name
        obj.data.uv_layers[0].name = 'st'
        obj.data.materials.clear()
        for p in obj.data.polygons:
            p.use_smooth = True
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.wm.usd_export(filepath=os.path.join(MODELS, name + '.usdz'), selected_objects_only=True,
                          export_materials=False, export_uvmaps=True, export_normals=True,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
                          export_global_up_selection='Y', export_animation=False, triangulate_meshes=True,
                          export_lights=False, export_cameras=False, merge_parent_xform=True)


os.makedirs(MAPS, exist_ok=True)
for source, (name, target, height) in PROPS.items():
    path = os.path.join(SRC, source, source + '.gltf')
    print(name, flush=True)
    obj = load(path)
    maps = textures(obj)
    colour = pixels(maps['color'])
    Image.fromarray((np.clip(colour[..., :3], 0, 1) * 255).astype(np.uint8)).save(os.path.join(MAPS, f'{name}_diff.jpg'), quality=92)
    if 'normal' in maps:
        n = pixels(maps['normal'])
        Image.fromarray((np.clip(n[..., :3], 0, 1) * 255).astype(np.uint8)).save(os.path.join(MAPS, f'{name}_nor.jpg'), quality=92)
    if 'mr' in maps:
        mr = pixels(maps['mr'])
        Image.fromarray((np.clip(mr[..., 1], 0, 1) * 255).astype(np.uint8)).convert('RGB').save(os.path.join(MAPS, f'{name}_rough.jpg'), quality=88)
    decimate(obj, target)
    stand(obj, height)
    obj.name = name
    meshes = [obj]
    for suffix, count in (('_lod', max(400, target // 4)), ('_far', max(200, target // 10))):
        lod = meshes[-1].copy()
        lod.data = meshes[-1].data.copy()
        lod.name = name + suffix
        bpy.context.collection.objects.link(lod)
        decimate(lod, count)
        meshes.append(lod)
    co = np.array([v.co[:] for v in obj.data.vertices])
    print('  ', name, len(obj.data.polygons), 'tris, size', (co.max(0) - co.min(0)).round(2).tolist(), flush=True)
    export(meshes, name)
