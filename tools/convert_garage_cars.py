"""Converts detailed (Sketchfab, CC BY 4.0) car models into light USDZ files for the garage,
using Blender as a Python module (pip install bpy). Writes <id>_body.usdz, <id>_wheel.usdz and
prints the Swift spec numbers (wheel centers, radius, exhaust height).

The models must be Draco-decoded first (Blender's pip build has no Draco):
    node decode.mjs in.glb plain.glb

Steps per car: import, flatten transforms, scale to `length` meters, turn so the car faces +X
(Blender; +X forward, +Z up, +Y left), cut the four wheels out (all faces inside each tyre's
cylinder) so they can spin and steer, decimate, shrink textures to 512 px (base color only), name
the paint and glass materials, and export the body and the front-left wheel as USDZ (Y up).

Usage: python convert_garage_cars.py <plain glb folder> <Hop/Models>
"""
import sys, os, re, math
import bpy, bmesh
from mathutils import Vector, Matrix

CARS = [
    # id, file, length (m), paint material regex, glass regex, tyre regex, red light regex
    dict(id='strada', file='m4.glb', length=4.65, paint=r'CarPaint$', glass=r'^(GlassClear|Window|WindowDark)',
         tire=r'Tire', red=r'GlassRed'),
    dict(id='toro', file='huracan.glb', length=4.55, paint=r'Paint', glass=r'Glass_Parts|^Glass',
         tire=r'tyre', red=r'Red_Glass'),
    dict(id='arrow', file='570S-2016.glb', length=4.55, paint=r'M_CarPaint_Max', glass=r'Glass_Window|Black_Glass',
         tire=r'WheelspolySurface1SG1|Tire|tyre', red=r'LightGlass_Red'),
    dict(id='bison', file='urus-2019.glb', length=4.95, paint=r'Paint_Material', glass=r'Window_Material',
         tire=r'Wheel', red=r'LightEmissive'),
    dict(id='classico', file='f40.glb', length=4.4, paint=r'^material$', glass=r'F40_Glass|F40_Window',
         tire=r'Scene_-_Root', red=r'brakelight'),
]

# Maker badges, logos and number plates are removed (no third-party trademarks in the game)
REMOVE = r'badge|logo|ManufacturerPlate|plate'

BODY_BUDGET = 70000
WHEEL_BUDGET = 5000
TEXTURE_SIZE = 512


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def flatten():
    """Applies every transform so vertex positions are in world space, removes empties."""
    for o in list(bpy.context.scene.objects):
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects()[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.select_all(action='DESELECT')
    for o in list(bpy.context.scene.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    for o in mesh_objects():
        o.select_set(True)
        if o.data.users > 1:
            o.data = o.data.copy()
    bpy.context.view_layer.objects.active = mesh_objects()[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def remove_faces(obj, pattern):
    """Deletes every face whose material name matches `pattern`."""
    regex = re.compile(pattern, re.I)
    slots = {i for i, slot in enumerate(obj.material_slots) if slot.material and regex.search(slot.material.name)}
    if not slots:
        return 0
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    doomed = [f for f in bm.faces if f.material_index in slots]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')
    return len(doomed)


def material_faces(obj, pattern):
    regex = re.compile(pattern, re.I)
    slots = {i for i, slot in enumerate(obj.material_slots) if slot.material and regex.search(slot.material.name)}
    return [p for p in obj.data.polygons if p.material_index in slots]


def transform(obj, matrix):
    obj.data.transform(matrix)
    obj.data.update()


def bounds(obj):
    xs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return lo, hi


def orient(obj, car):
    """Scale to the car's length and turn it to face +X with the tyres on z = 0."""
    lo, hi = bounds(obj)
    ext = hi - lo
    length_axis = 0 if ext.x > ext.y else 1
    scale = car['length'] / ext[length_axis]
    center = (lo + hi) / 2
    transform(obj, Matrix.Scale(scale, 4) @ Matrix.Translation(-center))
    # Rear = where the red lights are
    red = material_faces(obj, car['red'])
    if red:
        rear = sum((p.center[length_axis] for p in red), 0.0) / len(red)
    else:
        rear = -1
    forward_sign = -1 if rear > 0 else 1
    if length_axis == 1:
        angle = -math.pi / 2 if forward_sign > 0 else math.pi / 2   # +Y or -Y -> +X
    else:
        angle = 0 if forward_sign > 0 else math.pi
    transform(obj, Matrix.Rotation(angle, 4, 'Z'))
    lo, hi = bounds(obj)
    transform(obj, Matrix.Translation(Vector((0, 0, -lo.z))))
    return forward_sign


def find_wheels(obj, car):
    """Four tyre clusters (by quadrant) -> center, radius, half width."""
    faces = material_faces(obj, car['tire'])
    verts = obj.data.vertices
    clusters = {}
    for p in faces:
        c = p.center
        key = (c.x > 0, c.y > 0)
        clusters.setdefault(key, []).extend(verts[i].co.copy() for i in p.vertices)
    wheels = {}
    for key, points in clusters.items():
        lo = Vector((min(v.x for v in points), min(v.y for v in points), min(v.z for v in points)))
        hi = Vector((max(v.x for v in points), max(v.y for v in points), max(v.z for v in points)))
        center = (lo + hi) / 2
        radius = (hi.z - lo.z) / 2
        center.z = radius   # the tyre touches the ground
        wheels[key] = (center, radius, (hi.y - lo.y) / 2)
    return wheels


def cut_wheel(obj, center, radius, half_width, name):
    """Moves every face inside the wheel's cylinder to a new object."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bpy.ops.mesh.select_all(action='DESELECT')
    count = 0
    for f in bm.faces:
        inside = True
        for v in f.verts:
            d = math.hypot(v.co.x - center.x, v.co.z - center.z)
            if d > radius * 1.04 or abs(v.co.y - center.y) > half_width + 0.04:
                inside = False
                break
        f.select = inside
        count += inside
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    new = [o for o in bpy.context.selected_objects if o != obj][0]
    new.name = name
    return new, count


def split_by_material(obj, prefix, name):
    """Moves the faces whose material name starts with `prefix` into a new object `name`."""
    slots = {i for i, slot in enumerate(obj.material_slots) if slot.material and slot.material.name.startswith(prefix)}
    if not slots:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    for f in bm.faces:
        f.select = f.material_index in slots
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    new = [o for o in bpy.context.selected_objects if o != obj]
    if not new:
        return None
    new[0].name = name
    new[0].data.name = name
    return new[0]


def decimate(obj, budget):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris <= budget:
        return tris
    mod = obj.modifiers.new('decimate', 'DECIMATE')
    mod.ratio = budget / tris
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def simplify_materials(car):
    """Base color textures only (512 px), named paint/glass/redlight for the game to restyle."""
    paint = re.compile(car['paint'], re.I)
    glass = re.compile(car['glass'], re.I)
    red = re.compile(car['red'], re.I)
    for mat in bpy.data.materials:
        name = mat.name
        index = bpy.data.materials.find(name)
        if name.startswith(('paint_', 'glass_', 'redlight_', 'mat_')):
            pass
        elif paint.search(name):
            mat.name = f'paint_{index}'
        elif glass.search(name):
            mat.name = f'glass_{index}'
        elif red.search(name):
            mat.name = f'redlight_{index}'
        else:
            mat.name = f'mat_{index}'   # source names carry maker names
        if not mat.use_nodes:
            continue
        nodes = mat.node_tree.nodes
        bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf:
            continue
        for socket in ['Normal', 'Roughness', 'Metallic', 'Coat Normal', 'Transmission Weight', 'Specular IOR Level']:
            if socket in bsdf.inputs:
                for link in list(bsdf.inputs[socket].links):
                    mat.node_tree.links.remove(link)
    for image in bpy.data.images:
        if image.size[0] > TEXTURE_SIZE or image.size[1] > TEXTURE_SIZE:
            factor = TEXTURE_SIZE / max(image.size)
            image.scale(max(1, int(image.size[0] * factor)), max(1, int(image.size[1] * factor)))
            image.pack()


def export(objects, path):
    # Generic names only (source names carry maker names)
    for o in objects:
        o.data.name = o.name
        for k, uv in enumerate(o.data.uv_layers):
            uv.name = 'st' if k == 0 else f'st{k}'
        for k, attr in enumerate(list(o.data.attributes)):
            if not attr.name.startswith(('.', 'position', 'sharp', 'material_index', 'st')) and attr.domain == 'CORNER' and attr.data_type == 'BYTE_COLOR':
                pass
    for image in bpy.data.images:
        image.name = f'tex_{bpy.data.images.find(image.name)}'
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.wm.usd_export(filepath=path, selected_objects_only=True, export_materials=True,
                          export_textures_mode='NEW', overwrite_textures=True, export_uvmaps=True, export_normals=True,
                          generate_preview_surface=True, generate_materialx_network=False, convert_orientation=True,
                          export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          export_animation=False, triangulate_meshes=True, export_lights=False, export_cameras=False,
                          convert_world_material=False, usdz_downscale_size='512', merge_parent_xform=True)


def convert(car, src, out):
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(src, car['file']))
    obj = flatten()
    obj.name = car['id']
    removed = remove_faces(obj, REMOVE)
    print(f"  {car['id']}: removed {removed} badge/logo faces")
    orient(obj, car)
    wheels = find_wheels(obj, car)
    simplify_materials(car)
    if len(wheels) != 4:
        print(f"!! {car['id']}: found {len(wheels)} tyre clusters")
    parts = {}
    names = {(True, True): 'wheel_fl', (True, False): 'wheel_fr', (False, True): 'wheel_rl', (False, False): 'wheel_rr'}
    for key, (center, radius, half) in wheels.items():
        part, count = cut_wheel(obj, center, radius, half, names[key])
        parts[names[key]] = (part, center, radius)
    # Paint, glass and red lamps as their own objects (node names the game looks for)
    pieces = [obj]
    for prefix, node in [('paint_', 'paint'), ('glass_', 'glass'), ('redlight_', 'taillight')]:
        piece = split_by_material(obj, prefix, node)
        if piece:
            pieces.append(piece)
    obj.name = 'body'
    obj.data.name = 'body'
    total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pieces)
    body_tris = 0
    for piece in pieces:
        tris = sum(len(p.vertices) - 2 for p in piece.data.polygons)
        body_tris += decimate(piece, max(300, int(BODY_BUDGET * tris / max(total, 1))))
    export(pieces, os.path.join(out, car['id'] + '_body.usdz'))
    fl, center, radius = parts['wheel_fl']
    transform(fl, Matrix.Translation(-center))
    wheel_tris = decimate(fl, WHEEL_BUDGET)
    export([fl], os.path.join(out, car['id'] + '_wheel.usdz'))
    lo, hi = bounds(obj)
    # Game axes: x forward, y up, z right (= -Blender y)
    spots = []
    for name in ['wheel_fl', 'wheel_fr', 'wheel_rl', 'wheel_rr']:
        _, c, r = parts[name]
        spots.append(f'({c.x:.3f}, {c.z:.3f}, {-c.y:.3f}, {"true" if name.startswith("wheel_f") else "false"})')
    print(f"SPEC {car['id']}: body {body_tris} tris, wheel {wheel_tris} tris, radius {radius:.3f}, "
          f"rear {lo.x:.3f}, height {hi.z:.3f}, width {hi.y - lo.y:.3f}")
    print(f"SPOTS {car['id']}: [{', '.join(spots)}]")


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    src, out = args[0], args[1]
    only = args[2:] if len(args) > 2 else None
    for car in CARS:
        if only and car['id'] not in only:
            continue
        convert(car, src, out)
