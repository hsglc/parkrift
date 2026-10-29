"""Turns the Meshy street props (image-to-3D from the reference sheet the user supplied) into game
assets: four street trees in their kerbed planters and two traffic lights.

Each GLB is joined, reduced to a mobile budget (collapse decimation keeps the UVs, so Meshy's
texture still fits), stood on the origin (centred on its base) and scaled to real size, then
written as USDZ (one mesh named after the prop, metres, y up) with its colour, normal and
roughness maps as JPGs.

Traffic lights additionally: turned so the lenses face +x, the three lit lenses of the main head
found in the texture (saturated red / amber / green), painted over as dark smoked glass (the game
lights one at a time), and their centres written to <name>.json in game axes.

Usage: python (bpy) convert_meshy_street.py <glb dir> <Hop/Models> <Hop/Textures>
"""
import sys, os, json, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
from PIL import Image

SRC, MODELS, TEXTURES = sys.argv[-3:]

PROPS = {
    # name: (triangles up close, height in metres). A second, lighter mesh "<name>_lod" is
    # drawn from further away.
    'tree_green': (45000, 7.6),
    'tree_light': (45000, 7.0),
    'tree_yellow': (45000, 6.8),
    'tree_pink': (45000, 6.4),
    'signal_pole': (40000, 4.7),
    'signal_ped': (40000, 4.7),
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
    """The material's colour, metal/rough and normal images, by the socket they feed."""
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
            elif target.type == 'SEPARATE_COLOR' or target.type == 'SEPRGB':
                found['mr'] = node.image
    return found


def pixels(image):
    w, h = image.size
    a = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[::-1]          # top row first, like PIL


def decimate(obj, target):
    faces = len(obj.data.polygons)
    # Very dense scans: two passes keep the collapse stable
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    while faces > target * 1.05:
        ratio = max(target / faces, 0.08)
        mod = obj.modifiers.new('d', 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier='d')
        new = len(obj.data.polygons)
        print('  decimate', faces, '->', new, flush=True)
        if new >= faces:
            break
        faces = new


def stand(obj, height):
    """Base centred on the origin, lowest point at 0, scaled to `height`."""
    co = np.array([v.co[:] for v in obj.data.vertices])
    zmin, zmax = co[:, 2].min(), co[:, 2].max()
    base = co[co[:, 2] < zmin + (zmax - zmin) * 0.04]
    cx = (base[:, 0].min() + base[:, 0].max()) / 2
    cy = (base[:, 1].min() + base[:, 1].max()) / 2
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


def save_maps(name, colour, normal, mr):
    # Full Meshy resolution (2K) for colour and normal
    Image.fromarray((np.clip(colour[..., :3], 0, 1) * 255).astype(np.uint8)) \
        .save(os.path.join(TEXTURES, f'{name}_diff.jpg'), quality=92)
    if normal is not None:
        Image.fromarray((np.clip(normal[..., :3], 0, 1) * 255).astype(np.uint8)) \
            .save(os.path.join(TEXTURES, f'{name}_nor.jpg'), quality=92)
    if mr is not None:
        rough = (np.clip(mr[..., 1], 0, 1) * 255).astype(np.uint8)
        Image.fromarray(rough).convert('RGB').resize((1024, 1024), Image.LANCZOS) \
            .save(os.path.join(TEXTURES, f'{name}_rough.jpg'), quality=88)


def lens_class(rgb):
    """0 red, 1 amber, 2 green, -1 not a lit lens."""
    r, g, b = rgb
    mx, mn = max(rgb), min(rgb)
    if mx < 0.3 or mx - mn < 0.2:
        return -1
    if r > 0.5 and g < r * 0.55 and b < r * 0.55:
        return 0
    if r > 0.5 and g > r * 0.6 and b < g * 0.55:
        return 1
    if g > 0.4 and g > r * 1.4 and g > b * 1.05:
        return 2
    return -1


def signal(obj, colour):
    """Turns the light to face +x, finds the three lit lenses of the top head and paints them dark.
    Returns their centres (game axes) and the colour map with the lenses dark."""
    h, w = colour.shape[:2]
    uv = obj.data.uv_layers[0].data
    zmax = max(v.co.z for v in obj.data.vertices)
    zmin = min(v.co.z for v in obj.data.vertices)
    height = zmax - zmin
    lens_faces = {0: [], 1: [], 2: []}
    coloured = []           # every lens-coloured face, whatever way it faces (the glass' rim too)
    for p in obj.data.polygons:
        u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
        px = colour[min(h - 1, int((1 - v) * h)), min(w - 1, int(u * w))]
        k = lens_class(px[:3])
        if k >= 0:
            coloured.append(p.index)
        # Meshy keeps the picture's front: the lenses face -y (glTF +z)
        if k >= 0 and p.center.z > zmin + height * 0.6 and p.normal.y < -0.35:
            lens_faces[k].append(p.index)
    # Keep the top head only: each colour's faces above the bottom of the red lens' cluster minus a margin
    polys = obj.data.polygons
    for k in lens_faces:
        if lens_faces[k]:
            top = max(polys[i].center.z for i in lens_faces[k])
            lens_faces[k] = [i for i in lens_faces[k] if polys[i].center.z > top - height * 0.06]
    angle = -math.pi / 2                     # -y turned to +x
    obj.data.transform(Matrix.Rotation(-angle, 4, 'Z'))
    obj.data.update()
    centres = []
    mask = Image.new('L', (w, h), 0)
    from PIL import ImageDraw, ImageFilter
    draw = ImageDraw.Draw(mask)
    found = [i for k in lens_faces for i in lens_faces[k]]
    if found:
        lo = min(polys[i].center.z for i in found) - height * 0.05
        hi = max(polys[i].center.z for i in found) + height * 0.05
        for i in coloured:
            if lo < polys[i].center.z < hi:
                pts = [(uv[l].uv.x * w, (1 - uv[l].uv.y) * h) for l in polys[i].loop_indices]
                draw.polygon(pts, fill=255)
    for k in (0, 1, 2):
        faces = lens_faces[k]
        if not faces:
            centres.append(None)
            continue
        zs = np.array([polys[i].center.z for i in faces])
        # The highest cluster of this colour (the ped head sits lower)
        top = zs.max()
        faces = [i for i, z in zip(faces, zs) if z > top - height * 0.06]
        area = sum(polys[i].area for i in faces)
        c = sum((polys[i].center * polys[i].area for i in faces), Vector((0, 0, 0))) / area
        front = max(polys[i].center.x for i in faces)
        centres.append([front + 0.01, c.z, -c.y])          # Blender -> game: (x, z, -y)
        for i in faces:
            pts = [(uv[l].uv.x * w, (1 - uv[l].uv.y) * h) for l in polys[i].loop_indices]
            draw.polygon(pts, fill=255)
    m = np.asarray(mask.filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255
    dark = colour.copy()
    lum = colour[..., :3].mean(axis=2, keepdims=True)
    glass = np.concatenate([lum * 0.12 + 0.02, lum * 0.11 + 0.02, lum * 0.11 + 0.025], axis=2)
    dark[..., :3] = colour[..., :3] * (1 - m[..., None]) + glass * m[..., None]
    return centres, dark


for name, (target, height) in PROPS.items():
    path = os.path.join(SRC, name + '.glb')
    if not os.path.exists(path):
        continue
    print(name, flush=True)
    obj = load(path)
    maps = textures(obj)
    colour = pixels(maps['color'])
    normal = pixels(maps['normal']) if 'normal' in maps else None
    mr = pixels(maps['mr']) if 'mr' in maps else None
    decimate(obj, target)
    stand(obj, height)
    info = {}
    if name.startswith('signal'):
        centres, colour = signal(obj, colour)
        info['lenses'] = centres
        print('  lenses', centres)
    co = np.array([v.co[:] for v in obj.data.vertices])
    info['size'] = [float(co[:, 0].max() - co[:, 0].min()), float(co[:, 2].max()), float(co[:, 1].max() - co[:, 1].min())]
    info['triangles'] = len(obj.data.polygons)
    with open(os.path.join(SRC, name + '.json.out'), 'w') as f:
        json.dump(info, f)
    print('  ', info, flush=True)
    save_maps(name, colour, normal, mr)
    obj.name = name
    # Lighter meshes for further away: "<name>_lod" (a fifth) and "<name>_far" (about 2,500
    # triangles, also the shadow caster)
    meshes = [obj]
    for suffix, count in (('_lod', target // 5), ('_far', 2500)):
        lod = meshes[-1].copy()
        lod.data = meshes[-1].data.copy()
        lod.name = name + suffix
        bpy.context.collection.objects.link(lod)
        decimate(lod, count)
        info[suffix.strip('_') + '_triangles'] = len(lod.data.polygons)
        meshes.append(lod)
    with open(os.path.join(SRC, name + '.json.out'), 'w') as f:
        json.dump(info, f)
    export(meshes, name)
