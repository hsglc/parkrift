"""Converts the garage cars generated with Meshy AI (original designs, text-to-image then
image-to-3d "smart topology") into the game's USDZ files, using Blender as a Python module.

The cars were generated with a uniform lime-green paint so the paint areas can be found in the
texture: they become neutral grey in <id>_basecolor.jpg and white in <id>_mask.png, and the game
tints them with the chosen paint (like the retro car).

Smart topology keeps tyres, rims and hubs as separate pieces, so the wheels are found as the
connected pieces inside each tyre's box. Writes <id>_body.usdz (one mesh named "textured"),
<id>_wheel.usdz (front-left wheel, meshes "tire" and "rim") and prints the Swift spec numbers.

Refinement in Blender before export (the generated meshes are lumpy and one flat surface):
  - the body is ironed out (corrective smooth: small bumps go, the shape and panel lines stay)
    and shaded smooth, with hard edges kept at real creases,
  - bright lamp faces at the front become a "headlight" mesh (lit at night); everything else
    stays "textured", painted through the mask,
  - Meshy's texture is used pixel for pixel: only the lime paint becomes grey (its exact shading
    kept) so the game can tint it.

Usage: python convert_meshy_cars.py <folder with <id>/model.glb> <Hop/Models>
"""
import sys, os, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix

CARS = [
    # id, length (m)
    dict(id='italia', length=4.5),
    dict(id='arrow', length=4.7),
    dict(id='strada', length=4.1),
    dict(id='toro', length=4.75),
    dict(id='bison', length=4.5),
    dict(id='classico', length=4.4),
]

# Traffic and parked cars (NPC=1): Meshy cars of their own, generated the same way. Saved as
# npc_<id>_*; the police car keeps its own livery (no paint mask) and its light bar lenses become
# "lamp_red" / "lamp_blue" meshes that the chase flashes.
NPC_CARS = [
    dict(id='npc_hatch', src='hatch', length=4.0),
    dict(id='npc_sedan', src='sedan', length=4.7),
    dict(id='npc_suv', src='suv', length=4.6),
    dict(id='npc_pickup', src='pickup', length=5.3),
    dict(id='npc_police', src='police', length=4.9, livery=True),
]
NPC = bool(os.environ.get('NPC'))
if NPC:
    CARS = NPC_CARS

# Traffic cars are seen smaller and many at a time: their maps are half the garage cars' size
BASE_SIZE = 2048 if NPC else 4096
MASK_SIZE = 1024 if NPC else 2048
NORMAL_SIZE = 1024 if NPC else 2048
ROUGH_SIZE = 512 if NPC else 1024
TEXELS = {}
# Off by default: the model is used exactly as Meshy made it (its geometry, normals and UVs, so its
# normal map lines up) and only the paint mask, wheels and lamps are split out. REWORK=1 turns on
# the older reshaping (subdivision, ironed normals, flattened and re-tinted glass), which fought
# Meshy's normal map in the game and made the bodies look crumpled.
REWORK = bool(os.environ.get('REWORK'))
GLASS_TINT = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in list(bpy.context.scene.objects):
        o.select_set(o.type == 'MESH')
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    for o in list(bpy.context.scene.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Weld the UV-seam duplicates so each piece is one connected part, then give the welded
    # mesh Meshy's own normals back (its normal map was made against them)
    original = obj.copy()
    original.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(original)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    transfer = obj.modifiers.new('meshy_normals', 'DATA_TRANSFER')
    transfer.object = original
    transfer.use_loop_data = True
    transfer.data_types_loops = {'CUSTOM_NORMAL'}
    transfer.loop_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.modifier_apply(modifier='meshy_normals')
    bpy.data.objects.remove(original, do_unlink=True)
    return obj


def bounds(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def orient(obj, car):
    """Scale to `length`, face +X (Meshy cars come facing -X), tyres on z = 0."""
    lo, hi = bounds([v.co for v in obj.data.vertices])
    scale = car['length'] / (hi.x - lo.x)
    center = (lo + hi) / 2
    obj.data.transform(Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center))
    lo, hi = bounds([v.co for v in obj.data.vertices])
    obj.data.transform(Matrix.Translation(Vector((0, 0, -lo.z))))
    obj.data.update()


def pieces(obj):
    """Connected parts: list of (face indices, lo, hi)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    result = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        faces = []
        while stack:
            x = stack.pop()
            if x.index in seen:
                continue
            seen.add(x.index)
            faces.append(x.index)
            for e in x.edges:
                stack += [g for g in e.link_faces if g.index not in seen]
        points = [v.co.copy() for i in faces for v in bm.faces[i].verts]
        lo, hi = bounds(points)
        result.append((faces, lo, hi))
    bm.free()
    return result


def find_wheels(parts):
    """The four tyres: the biggest parts touching the ground in each corner, then every part
    inside a tyre's box joins its wheel."""
    corners = {}
    for faces, lo, hi in parts:
        if lo.z > 0.03:
            continue
        size = hi - lo
        if size.x > 1.2 or size.y > 0.6:
            continue   # body or skirt, not a tyre
        c = (lo + hi) / 2
        key = (c.x > 0, c.y > 0)
        if key not in corners or len(faces) > len(corners[key][0]):
            corners[key] = (faces, lo, hi)
    wheels = {}
    for key, (faces, lo, hi) in corners.items():
        grow = Vector((0.03, 0.03, 0.03))
        a, b = lo - grow, hi + grow
        members = [f for f, l, h in parts
                   if l.x >= a.x and l.y >= a.y and l.z >= a.z and h.x <= b.x and h.y <= b.y and h.z <= b.z]
        tyre = set(faces)
        radius = (hi.z - lo.z) / 2
        center = (lo + hi) / 2
        center.z = radius
        wheels[key] = (center, radius, tyre, {i for m in members for i in m})
    return wheels


def split(obj, faces, name):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        f.select = f.index in faces
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    new = [o for o in bpy.context.selected_objects if o != obj][0]
    new.name = name
    new.data.name = name
    return new


def linked_image(socket_names):
    """The texture image feeding one of the given material sockets (directly or through a
    normal map / separate node), or None."""
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        for node in mat.node_tree.nodes:
            if node.type != 'TEX_IMAGE' or not node.image:
                continue
            todo = [l.to_node for l in node.outputs[0].links] + [l.to_node for l in node.outputs[0].links]
            names = {l.to_socket.name for l in node.outputs[0].links}
            for n in todo:
                for out in n.outputs:
                    names |= {l.to_socket.name for l in out.links}
            if names & set(socket_names):
                return node.image
    return None


def pixels(image):
    w, h = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3].copy()


def texture(obj, car, out):
    """Paint areas -> grey base + white mask, applied pixel for pixel to Meshy's own texture.

    The cars were generated in one lime-green paint. A texel belongs to the paint when its hue is
    green (green clearly above red and blue), however dark or light it is, so shaded paint and the
    soft lime-to-black edges Meshy painted stay paint. Its grey level is its green level against
    the lime itself, so shading and edge fades keep exactly their original strength; the game
    multiplies it by the chosen colour. Every other texel is kept exactly as Meshy made it.

    The 4K retexture also brings a normal map (fine panel lines, tyre treads, grilles) and a
    roughness map; both are written for the game at 2048 / 1024 px."""
    from PIL import Image
    image = linked_image(['Base Color']) or next(i for i in bpy.data.images if i.size[0] > 0)
    w, h = image.size
    a = pixels(image).astype(np.float64)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    chroma = g - np.maximum(r, b)
    # Green by ratio, not by amount: paint in deep shadow (dark lime) is still paint
    painted = (g > 0.03) & (g > r * 1.12) & (g > b * 1.35)
    if car.get('livery'):
        painted[:] = False
    else:
        strong = painted & (chroma > np.percentile(chroma[painted], 60))
        lime_g = np.median(g[strong])
        # Its shading kept, a little softened (a gloss coat shows baked shadows harder than matte)
        level = np.clip(g / lime_g, 0, 1.1) ** 0.7 * 0.86
        a[painted] = np.clip(level[painted], 0, 1)[:, None]

    size = min(w, BASE_SIZE)
    base = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    if size != w:
        base = base.resize((size, size), Image.LANCZOS)
    TEXELS[car['id']] = (a, painted)
    base.save(os.path.join(out, car['id'] + '_basecolor.jpg'), quality=90)
    # The mask at half size, box-filtered: soft paint edges (the shader samples it linearly)
    m = Image.fromarray((painted * 255).astype(np.uint8))
    m = m.resize((MASK_SIZE, MASK_SIZE), Image.BOX)
    # RGB, not grayscale: SceneKit turns 8-bit gray images into an R8 sRGB texture, a format the
    # simulator and Macs do not have (the app crashed there)
    if not car.get('livery'):
        m.convert('RGB').save(os.path.join(out, car['id'] + '_mask.png'))

    normal = linked_image(['Normal'])
    if normal is not None:
        n = Image.fromarray((np.clip(pixels(normal), 0, 1) * 255).astype(np.uint8))
        n.resize((NORMAL_SIZE, NORMAL_SIZE), Image.LANCZOS).save(os.path.join(out, car['id'] + '_normal.jpg'), quality=92)
    rough_img = linked_image(['Roughness'])
    if rough_img is not None:
        # Meshy's own gloss and metal, texel for texel (glTF: roughness in green, metal in blue)
        mr = pixels(rough_img)
        for channel, suffix in ((1, '_rough.jpg'), (2, '_metal.jpg')):
            Image.fromarray((np.clip(mr[..., channel], 0, 1) * 255).astype(np.uint8)).convert('RGB') \
                .resize((ROUGH_SIZE, ROUGH_SIZE), Image.LANCZOS).save(os.path.join(out, car['id'] + suffix), quality=92)
    print(f"  {car['id']}: texture {w} px, paint {painted.mean():.2f}, normal {normal is not None}, rough {rough_img is not None}")
    return painted.mean()


def refine(obj, levels=1, crease_angle=38, small_faces=0, small_size=0.0, fold_angle=100, hold=True):
    """One Catmull-Clark subdivision: four times the triangles, smoother curves and round
    silhouettes; edges sharper than `crease_angle` (panel lines, window frames, lips) are
    creased so they stay crisp instead of melting.

    Thin folded blades (splitter fins, cowl vents, wiper bases: edges folded past `fold_angle`)
    and open borders turned into spikes when smoothed, so near them the subdivided mesh keeps
    the original shape (a plain split of each face) and blends into the smooth surface over one
    ring of faces. Small loose pieces are not subdivided at all."""
    small = set()
    if small_faces:
        for faces, lo, hi in pieces(obj):
            if len(faces) < small_faces or (hi - lo).length < small_size:
                small |= set(faces)
    keep = split(obj, small, obj.name + '_small') if small else None

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    layer = bm.edges.layers.float.get('crease_edge') or bm.edges.layers.float.new('crease_edge')
    limit, fold = math.radians(crease_angle), math.radians(fold_angle)
    sharp = 0
    held_points = set()
    for e in bm.edges:
        if len(e.link_faces) != 2:
            if hold:
                held_points |= {v.index for v in e.verts}
            continue
        angle = e.calc_face_angle(0)
        if angle > fold and hold:
            held_points |= {v.index for v in e.verts}
        elif angle > limit:
            e[layer] = 1.0
            sharp += 1
    bm.verts.ensure_lookup_table()
    ring = {n.index for i in held_points for e in bm.verts[i].link_edges for n in e.verts} - held_points
    weight = {v.index: 0.0 if v.index in held_points else (0.5 if v.index in ring else 1.0) for v in bm.verts}
    # Weight of every point the subdivision makes: corners, edge middles and face middles
    key = lambda co: (round(co.x, 5), round(co.y, 5), round(co.z, 5))
    at = {}
    for v in bm.verts:
        at[key(v.co)] = weight[v.index]
    for e in bm.edges:
        at[key((e.verts[0].co + e.verts[1].co) / 2)] = min(weight[v.index] for v in e.verts)
    for f in bm.faces:
        at[key(f.calc_center_median())] = min(weight[v.index] for v in f.verts)
    bm.to_mesh(obj.data)
    bm.free()

    def subdivided(source, kind):
        copy = source.copy()
        copy.data = source.data.copy()
        bpy.context.scene.collection.objects.link(copy)
        bpy.ops.object.select_all(action='DESELECT')
        copy.select_set(True)
        bpy.context.view_layer.objects.active = copy
        mod = copy.modifiers.new('refine', 'SUBSURF')
        mod.levels = levels
        mod.render_levels = levels
        mod.subdivision_type = kind
        mod.uv_smooth = 'PRESERVE_BOUNDARIES' if kind == 'CATMULL_CLARK' else 'NONE'
        mod.boundary_smooth = 'PRESERVE_CORNERS'
        mod.use_creases = True
        mod.quality = 3
        bpy.ops.object.modifier_apply(modifier='refine')
        return copy

    smooth = subdivided(obj, 'CATMULL_CLARK')
    plain = subdivided(obj, 'SIMPLE')
    sm, pm = smooth.data, plain.data
    same = len(sm.vertices) == len(pm.vertices) and len(sm.loops) == len(pm.loops) and \
        all(a.vertices[:] == b.vertices[:] for a, b in zip(sm.polygons, pm.polygons))
    if not same:
        print(f"  {obj.name}: subdivisions differ, plain smoothing used")
        mesh = sm
    else:
        w = np.array([at.get(key(v.co), 1.0) for v in pm.vertices], dtype=np.float64)
        sp = np.array([v.co[:] for v in sm.vertices])
        pp = np.array([v.co[:] for v in pm.vertices])
        moved = pp + (sp - pp) * w[:, None]
        for v, co in zip(pm.vertices, moved):
            v.co = co
        # UVs follow the same blend, so the texture stays on the faces it belongs to
        for layer_s, layer_p in zip(sm.uv_layers, pm.uv_layers):
            for i, loop in enumerate(pm.loops):
                k = w[loop.vertex_index]
                if k > 0:
                    a, b = layer_p.data[i].uv, layer_s.data[i].uv
                    layer_p.data[i].uv = (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
        pm.update()
        mesh = pm
        print(f"  {obj.name}: {int((w < 1).sum())} of {len(w)} points held near folds and borders")
    old = obj.data
    obj.data = mesh.copy()
    obj.data.name = old.name
    for o in (smooth, plain):
        bpy.data.objects.remove(o, do_unlink=True)
    if keep is not None:
        bpy.ops.object.select_all(action='DESELECT')
        keep.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.join()
    return sharp, len(small)


def lightbar(obj, car):
    """Red and blue lens faces of a roof light bar (saturated texels on the roof)."""
    texels = TEXELS[car['id']][0]
    h, w = texels.shape[:2]
    mesh = obj.data
    uv = mesh.uv_layers[0].data
    lo, hi = bounds([v.co for v in mesh.vertices])
    found = {'lamp_red': set(), 'lamp_blue': set()}
    for poly in mesh.polygons:
        if poly.center.z < hi.z - 0.14:
            continue
        u = sum(uv[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uv[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        r, g, b = texels[min(h - 1, max(0, int((1 - v) * h))), min(w - 1, max(0, int(u * w)))]
        if r > 0.35 and r > g * 2.2 and r > b * 2.2:
            found['lamp_red'].add(poly.index)
        elif b > 0.3 and b > r * 1.8 and b > g * 1.3:
            found['lamp_blue'].add(poly.index)
    return found


def export(objects, path):
    for o in objects:
        o.data.name = o.name
        for k, uv in enumerate(o.data.uv_layers):
            uv.name = 'st' if k == 0 else f'st{k}'
        o.data.materials.clear()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.wm.usd_export(filepath=path, selected_objects_only=True, export_materials=False,
                          export_uvmaps=True, export_normals=True, convert_orientation=True,
                          export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          export_animation=False, triangulate_meshes=True, export_lights=False, export_cameras=False,
                          merge_parent_xform=True)


def taillights(obj):
    """A full-width LED tail light bar that follows the car's rear surface. The cars were made
    from front three-quarter concept images, so Meshy guessed their tails: lamps that read as
    headlights and no red, which made the cars look like they drove backwards. The bar is
    placed by casting rays at the tail; the game lights it with its brake material."""
    from mathutils.bvhtree import BVHTree
    lo, hi = bounds([v.co for v in obj.data.vertices])
    # A spare wheel hung on the tailgate is left out of the rays, so the bar lies on the body
    # behind it instead of across the tyre
    skip = set()
    for faces, plo, phi in pieces(obj):
        size = phi - plo
        if plo.x < lo.x + 0.15 and size.x < 0.5 and 0.4 < size.y < 0.95 and 0.4 < size.z < 0.95 and len(faces) > 40:
            skip |= set(faces)
    mesh = obj.data
    verts = [v.co.copy() for v in mesh.vertices]
    polys = [list(p.vertices) for p in mesh.polygons if p.index not in skip]
    tree = BVHTree.FromPolygons(verts, polys)
    if skip:
        print(f"  {obj.name}: spare wheel left out of the tail light ({len(skip)} faces)")
    half = (hi.y - lo.y) / 2
    rear = lo.x

    def hit(y, z):
        location, _, _, _ = tree.ray_cast(Vector((rear - 1.0, y, z)), Vector((1, 0, 0)))
        return location

    # The upper edge of the tail: the highest height where the rear surface is still near the end
    top = None
    for near in (0.3, 0.5, 0.8):   # rounded tails curve away from the very end
        z = 0.3
        while z < hi.z * 0.95:
            h = hit(half * 0.3, z)
            if h is not None and h.x < rear + near:
                top = z
            z += 0.02
        if top is not None:
            break
    if top is None:
        print(f"  {obj.name}: no tail surface found")
        return None
    band = 0.035
    samples = 28

    def strip(z0, reach):
        verts, faces, row = [], [], []
        for k in range(samples + 1):
            y = -half * 0.86 + half * 1.72 * k / samples
            upper, lower = hit(y, z0 + band), hit(y, z0 - band)
            if upper is None or lower is None or max(upper.x, lower.x) > rear + reach or abs(upper.x - lower.x) > 0.3:
                row.append(None)
                continue
            i = len(verts)
            verts.append((upper.x - 0.012, y, z0 + band))
            verts.append((lower.x - 0.012, y, z0 - band))
            row.append(i)
        for a, b in zip(row[:-1], row[1:]):
            if a is not None and b is not None:
                faces.append((a, a + 1, b + 1, b))
        return verts, faces

    # From just under the top of the tail downwards, the first height where a bar fits (a steep
    # enough surface); narrow tails (open wheel pods) need a deeper reach
    start = max(0.45, min(top - 0.04, hi.z * 0.62))
    verts, faces, z0 = [], [], start
    for reach in (0.45, 0.8, 1.2):
        z = start
        while z >= 0.42 and len(faces) < 10:
            verts, faces = strip(z, reach)
            z0 = z
            z -= 0.02
        if len(faces) >= 10:
            break
    if not faces:
        print(f"  {obj.name}: no tail light faces")
        return None
    mesh = bpy.data.meshes.new('taillight')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    # Faces look backwards (-x)
    if sum(p.normal.x for p in mesh.polygons) > 0:
        for p in mesh.polygons:
            p.flip()
        mesh.update()
    light = bpy.data.objects.new('taillight', mesh)
    bpy.context.scene.collection.objects.link(light)
    print(f"  {obj.name}: tail light bar at {z0:.2f} m, {len(faces)} segments")
    return light


def iron(obj):
    """Smooth reflections without moving the surface: the shape stays exactly Meshy's (moving
    vertices dragged dark texture details over the paint), only its normals come from an
    ironed-out copy, so the gloss slides cleanly over small lumps."""
    bpy.ops.object.select_all(action='DESELECT')
    smooth = obj.copy()
    smooth.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(smooth)
    smooth.select_set(True)
    bpy.context.view_layer.objects.active = smooth
    mod = smooth.modifiers.new('iron', 'CORRECTIVE_SMOOTH')
    mod.factor = 0.7
    mod.iterations = 10
    mod.smooth_type = 'SIMPLE'
    mod.use_only_smooth = True
    mod.rest_source = 'ORCO'
    bpy.ops.object.modifier_apply(modifier='iron')
    bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(48), keep_sharp_edges=True)
    if 'Smooth by Angle' in obj.modifiers:
        bpy.ops.object.modifier_apply(modifier='Smooth by Angle')
    # Not on thin folded blades and open borders (splitter fins, cowl vents, wiper bases): the
    # ironed copy's normals flip there and showed as dark spikes
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    held = set()
    for e in bm.edges:
        if len(e.link_faces) != 2 or e.calc_face_angle(0) > math.radians(100):
            held |= {v.index for v in e.verts}
    for _ in range(2):
        held |= {n.index for i in list(held) for e in bm.verts[i].link_edges for n in e.verts}
    count = len(bm.verts)
    bm.free()
    group = obj.vertex_groups.new(name='iron')
    group.add([i for i in range(count) if i not in held], 1.0, 'REPLACE')
    transfer = obj.modifiers.new('normals', 'DATA_TRANSFER')
    transfer.vertex_group = 'iron'
    transfer.object = smooth
    transfer.use_loop_data = True
    transfer.data_types_loops = {'CUSTOM_NORMAL'}
    transfer.loop_mapping = 'POLYINTERP_NEAREST'
    transfer.mix_factor = 0.85
    bpy.ops.object.modifier_apply(modifier='normals')
    bpy.data.objects.remove(smooth, do_unlink=True)
    if 'iron' in obj.vertex_groups:
        obj.vertex_groups.remove(obj.vertex_groups['iron'])


def classify_faces(obj, car):
    """Glass and headlight faces from the texture under each face (UV centre)."""
    texels, paint = TEXELS[car['id']]
    h, w = texels.shape[:2]
    mesh = obj.data
    uv = mesh.uv_layers[0].data
    lo, hi = bounds([v.co for v in mesh.vertices])
    glass, head = set(), set()
    for poly in mesh.polygons:
        u = sum(uv[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uv[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int((1 - v) * h)))
        r, g, b = texels[y, x]
        if paint[y, x]:
            continue
        c = poly.center
        bright = (r + g + b) / 3
        spread = max(r, g, b) - min(r, g, b)
        height = (c.z - lo.z) / (hi.z - lo.z)
        # Windows: dark, colourless, high on the car, not facing down
        if bright < 0.16 and spread < 0.06 and height > 0.5 and poly.normal.z > -0.2:
            glass.add(poly.index)
        # Head lamps: bright and pale, at the very front, facing forward
        elif bright > 0.62 and spread < 0.2 and c.x > hi.x - 0.45 and poly.normal.x > 0.3 \
                and height < (0.4 if car.get('livery') else 0.75):
            head.add(poly.index)
    return glass, head


def tail_faces(obj, car):
    """Traffic cars: the red tail lamps Meshy painted at the back (they glow when braking)."""
    texels = TEXELS[car['id']][0]
    h, w = texels.shape[:2]
    mesh = obj.data
    uv = mesh.uv_layers[0].data
    lo, hi = bounds([v.co for v in mesh.vertices])
    faces = set()
    for poly in mesh.polygons:
        c = poly.center
        if c.x > lo.x + 0.5 or poly.normal.x > -0.2 or (c.z - lo.z) / (hi.z - lo.z) < 0.25:
            continue
        u = sum(uv[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uv[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        r, g, b = texels[min(h - 1, max(0, int((1 - v) * h))), min(w - 1, max(0, int(u * w)))]
        if r > 0.3 and r > g * 2 and r > b * 2:
            faces.add(poly.index)
    return faces


def clean_glass(obj, car, glass_faces, out):
    """Windows keep no paint: lime fringes Meshy painted along window edges were taken as paint
    and showed as coloured smears on the glass. Every texel under a window face (and a couple
    of texels around it) becomes the window's own dark tint and leaves the paint mask."""
    from PIL import Image, ImageDraw, ImageFilter
    if not glass_faces:
        return 0
    texels, painted = TEXELS[car['id']]
    h, w = texels.shape[:2]
    # Grow the windows over neighbouring pale, colourless faces up high: Meshy painted
    # reflections into some windows (grey and white streaks) that the dark test missed
    mesh = obj.data
    uvl = mesh.uv_layers[0].data
    lo, hi = bounds([v.co for v in mesh.vertices])
    def texel(poly):
        u = sum(uvl[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uvl[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        y, x = min(h - 1, max(0, int((1 - v) * h))), min(w - 1, max(0, int(u * w)))
        return y, x
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    grown = set(glass_faces)
    # Side windows Meshy painted pale grey (baked sky reflections): upright, colourless, mid
    # grey faces in the upper part of the body
    for poly in mesh.polygons:
        y, x = texel(poly)
        r, g, b = texels[y, x]
        height = (poly.center.z - lo.z) / (hi.z - lo.z)
        if not painted[y, x] and max(r, g, b) - min(r, g, b) < 0.06 and (r + g + b) / 3 < 0.42 \
                and height > 0.6 and abs(poly.normal.z) < 0.5:
            grown.add(poly.index)
    for _ in range(4):
        edge = set()
        for i in grown:
            for e in bm.faces[i].edges:
                for f in e.link_faces:
                    if f.index in grown:
                        continue
                    poly = mesh.polygons[f.index]
                    y, x = texel(poly)
                    r, g, b = texels[y, x]
                    height = (poly.center.z - lo.z) / (hi.z - lo.z)
                    if not painted[y, x] and max(r, g, b) - min(r, g, b) < 0.08 and (r + g + b) / 3 < 0.6 \
                            and height > 0.5 and abs(poly.normal.z) < 0.85:
                        edge.add(f.index)
        if not edge:
            break
        grown |= edge
    bm.free()
    # Not roof racks and rails: loose parts that sit wholly on top of the roof
    for faces, plo, phi in pieces(obj):
        if plo.z > lo.z + (hi.z - lo.z) * 0.85:
            grown -= set(faces)
    glass_faces = grown
    area = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(area)
    uv = obj.data.uv_layers[0].data
    for poly in obj.data.polygons:
        if poly.index in glass_faces:
            draw.polygon([(uv[i].uv[0] * w, (1 - uv[i].uv[1]) * h) for i in poly.loop_indices], fill=255)
    area = np.asarray(area.filter(ImageFilter.MaxFilter(5))) > 0
    tinted = area & ~painted
    tint = np.median(texels[tinted], axis=0) if tinted.any() else np.array([0.06, 0.07, 0.08])
    tint = np.minimum(tint, 0.12)   # always a dark tint
    GLASS_TINT[car['id']] = tint
    # One even tint over the whole window (the game adds live reflections on top)
    fixed = area & painted
    texels[area] = tint
    painted[area] = False
    base = Image.fromarray((np.clip(texels, 0, 1) * 255).astype(np.uint8))
    if w != min(w, BASE_SIZE):
        base = base.resize((BASE_SIZE, BASE_SIZE), Image.LANCZOS)
    base.save(os.path.join(out, car['id'] + '_basecolor.jpg'), quality=90)
    m = Image.fromarray((painted * 255).astype(np.uint8)).resize((MASK_SIZE, MASK_SIZE), Image.BOX)
    m.convert('RGB').save(os.path.join(out, car['id'] + '_mask.png'))
    # Glass is flat and glossy: no bumps from the normal map, no matte patches from roughness
    # (both showed as smudges on the windows)
    for suffix, value in (('_normal.jpg', (128, 128, 255)), ('_rough.jpg', (20, 20, 20))):
        path = os.path.join(out, car['id'] + suffix)
        if not os.path.exists(path):
            continue
        img = Image.open(path).convert('RGB')
        a = np.asarray(img).copy()
        hole = np.asarray(Image.fromarray((area * 255).astype(np.uint8)).resize(img.size, Image.BOX)) / 255.0
        a = (a * (1 - hole[..., None]) + np.array(value) * hole[..., None]).astype(np.uint8)
        Image.fromarray(a).save(path, quality=92 if suffix == '_normal.jpg' else 90)
    return int(fixed.sum())


def flatten_glass(obj, car, tint_max=0.13):
    """Irons the window panes themselves: Meshy's glass surfaces are wavy, and a glossy wave
    reflects the sky as grey smudges. Points that only touch window faces (dark even tint, not
    paint, upper body) are relaxed; the frames stay where they are."""
    texels, painted = TEXELS[car['id']]
    tint = GLASS_TINT.get(car['id'])
    h, w = texels.shape[:2]
    mesh = obj.data
    uv = mesh.uv_layers[0].data
    lo, hi = bounds([v.co for v in mesh.vertices])
    glass = set()
    for poly in mesh.polygons:
        u = sum(uv[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uv[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        y, x = min(h - 1, max(0, int((1 - v) * h))), min(w - 1, max(0, int(u * w)))
        r, g, b = texels[y, x]
        if tint is not None and not painted[y, x] and np.abs(texels[y, x] - tint).max() < 0.004 \
                and (poly.center.z - lo.z) / (hi.z - lo.z) > 0.45:
            glass.add(poly.index)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    inner = [v for v in bm.verts if v.link_faces and all(f.index in glass for f in v.link_faces)]
    for _ in range(12):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(glass), len(inner)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def convert(car, src, out):
    reset()
    obj = load(os.path.join(src, car.get('src', car['id']), 'model.glb'))
    obj.name = 'textured'
    orient(obj, car)
    paint_share = texture(obj, car, out)
    parts = pieces(obj)
    wheels = find_wheels(parts)
    if len(wheels) != 4:
        print(f"!! {car['id']}: found {len(wheels)} wheels")
    names = {(True, True): 'wheel_fl', (True, False): 'wheel_fr', (False, True): 'wheel_rl', (False, False): 'wheel_rr'}
    # Remove all four wheels from the body (keep the front-left one as the wheel model)
    all_wheel = set()
    for key, (_, _, _, members) in wheels.items():
        all_wheel |= members
    fl_center, fl_radius, _, _ = wheels[(True, True)]
    keep = split(obj, all_wheel, 'wheel')
    # Keep only the front-left wheel as the model
    bm = bmesh.new()
    bm.from_mesh(keep.data)
    doomed = [f for f in bm.faces if not (f.calc_center_median().x > 0 and f.calc_center_median().y > 0)]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(keep.data)
    bm.free()

    # Wheel: tyre piece -> "tire", the rest -> "rim"; centered on its axle
    keep.data.transform(Matrix.Translation(-fl_center))
    # The tyre is the rubber ring: Meshy's smart topology keeps it a piece of its own, which
    # never reaches in towards the hub. Taking faces by distance from the axle cut through the
    # rubber and left a saw edge of tyre faces painted as metal on the rim.
    tyre_faces = set()
    bm = bmesh.new()
    bm.from_mesh(keep.data)
    bm.faces.ensure_lookup_table()
    for faces, lo, hi in pieces(keep):
        inner = min(math.hypot(v.co.x, v.co.z) for i in faces for v in bm.faces[i].verts)
        if inner > fl_radius * 0.55:
            tyre_faces |= set(faces)
    texels = TEXELS[car['id']][0]
    th, tw = texels.shape[:2]
    uv = keep.data.uv_layers[0].data
    if not tyre_faces:
        # Welded wheel: dark rubber faces out from the rim's edge
        for f in bm.faces:
            c = f.calc_center_median()
            loops = keep.data.polygons[f.index].loop_indices
            u = sum(uv[i].uv[0] for i in loops) / len(loops)
            v = sum(uv[i].uv[1] for i in loops) / len(loops)
            r, g, b = texels[min(th - 1, int((1 - v) * th)), min(tw - 1, int(u * tw))]
            if math.hypot(c.x, c.z) > fl_radius * 0.7 and (r + g + b) / 3 < 0.2:
                tyre_faces.add(f.index)
    bm.free()
    print(f"  {car['id']}: tyre {len(tyre_faces)} faces")
    tire = split(keep, tyre_faces, 'tire')
    keep.name = 'rim'
    keep.data.name = 'rim'
    # Lamps are picked on the original faces (picked after subdividing they came out jagged)
    glass_faces, head_faces = classify_faces(obj, car)
    if REWORK:
        cleaned = clean_glass(obj, car, glass_faces, out)
        print(f"  {car['id']}: {len(glass_faces)} window faces, {cleaned} paint texels removed from glass")
    extra = []
    if car.get('livery'):
        # One at a time: each split renumbers the faces left in the body
        for name in ('lamp_red', 'lamp_blue'):
            faces = lightbar(obj, car)[name]
            if faces:
                extra.append(split(obj, faces, name))
                print(f"  {car['id']}: {name} {len(faces)} faces")
        # Picked again: the splits renumbered the faces
        glass_faces, head_faces = classify_faces(obj, car)
    if head_faces:
        extra.append(split(obj, head_faces, 'headlight'))
    if REWORK and not os.environ.get('NOREFINE'):
        sharp, kept = refine(obj, crease_angle=float(os.environ.get('CREASE', 38)), small_faces=60, small_size=0.35)
        for part in extra:
            refine(part)
        # Tyres: tread blocks held at their corners became a saw edge; the whole tyre is smoothed
        refine(tire, crease_angle=50, hold=False)
        refine(keep, crease_angle=50)
        print(f"  {car['id']}: refined, {sharp} creased edges, {kept} small faces kept as they were")
    if REWORK:
        panes, points = flatten_glass(obj, car)
        print(f"  {car['id']}: {panes} window faces ironed flat ({points} points)")
    if NPC:
        faces = tail_faces(obj, car)
        light = split(obj, faces, 'taillight') if faces else None
        print(f"  {car['id']}: tail lamps {len(faces)} faces")
    else:
        light = taillights(obj)
    if REWORK and not os.environ.get("NOIRON"):
        iron(obj)
    # Windows stay in Meshy's texture (pixel for pixel): splitting them by faces gave jagged edges
    print(f"  {car['id']}: headlights {len(head_faces)} faces")
    if os.environ.get('PREVIEW_GLB'):
        # The four wheels put back for the preview
        shown = [obj] + extra + ([light] if light else [])
        for key in wheels:
            c = wheels[key][0]
            for part in (tire, keep):
                copy = part.copy()
                copy.data = part.data.copy()
                copy.name = part.name + '_preview'
                bpy.context.scene.collection.objects.link(copy)
                if not key[1]:
                    copy.data.transform(Matrix.Scale(-1, 4, Vector((0, 1, 0))))
                    copy.data.flip_normals()
                copy.data.transform(Matrix.Translation(c))
                shown.append(copy)
        bpy.ops.object.select_all(action='DESELECT')
        for o in shown:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(os.environ['PREVIEW_GLB'], car['id'] + '.glb'), use_selection=True,
                                  export_format='GLB')
    export([obj] + extra + ([light] if light else []), os.path.join(out, car['id'] + '_body.usdz'))
    export([tire, keep], os.path.join(out, car['id'] + '_wheel.usdz'))

    lo, hi = bounds([v.co for v in obj.data.vertices])
    spots = []
    radius = sum(w[1] for w in wheels.values()) / len(wheels)
    for key in [(True, True), (True, False), (False, True), (False, False)]:
        c = wheels[key][0]
        spots.append(f'({c.x:.3f}, {c.z:.3f}, {-c.y:.3f}, {"true" if key[0] else "false"})')
    print(f"SPEC {car['id']}: body {tris(obj)} tris, wheel {tris(tire) + tris(keep)} tris, radius {radius:.3f}, "
          f"rear {lo.x:.3f}, height {hi.z:.3f}, width {hi.y - lo.y:.3f}, paint {paint_share:.2f}")
    print(f"SPOTS {car['id']}: [{', '.join(spots)}]")
    # 4K texels as float arrays are big: drop each car's before the next (six ran out of memory)
    TEXELS.pop(car['id'], None)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    src, out = args[0], args[1]
    only = args[2:] if len(args) > 2 else None
    for car in CARS:
        if only and car['id'] not in only:
            continue
        convert(car, src, out)
