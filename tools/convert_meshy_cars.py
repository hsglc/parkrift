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
  - faces are split by what the texture shows under them: windows become a "glass" mesh (the
    game's glossy dark glass), bright lamps at the front a "headlight" mesh (lit at night),
    the rest stays "textured" (painted through the mask),
  - the texture is sharpened a little and the paint shading evened out.

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

TEXTURE_SIZE = 1024
TEXELS = {}
MASK_SIZE = 512


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
    # Weld the UV-seam duplicates so each piece is one connected part
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
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


def texture(obj, car, out):
    """Paint areas (lime green) -> neutral grey base + white mask."""
    image = next(i for i in bpy.data.images if i.size[0] > 0)
    w, h = image.size
    a = np.array(image.pixels[:], dtype=np.float64).reshape(h, w, 4)[::-1, :, :3]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mask = (g > 0.3) & (g > b * 1.7) & (g > r * 1.02)
    # Even paint: keep only a little of the generated shading (it reads as blotches under gloss)
    shade = np.clip(0.6 + 0.28 * (g / np.median(g[mask])), 0, 1)
    a[mask] = shade[mask][:, None]
    from PIL import Image, ImageFilter
    base = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((TEXTURE_SIZE, TEXTURE_SIZE), Image.LANCZOS)
    base = base.filter(ImageFilter.UnsharpMask(radius=2, percent=70, threshold=2))
    TEXELS[car['id']] = (a, mask)
    base.save(os.path.join(out, car['id'] + '_basecolor.jpg'), quality=88)
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    # RGB, not grayscale: SceneKit turns 8-bit gray images into an R8 sRGB texture, a format the
    # simulator and Macs do not have (the app crashed there)
    m.resize((MASK_SIZE, MASK_SIZE), Image.LANCZOS).convert('RGB').save(os.path.join(out, car['id'] + '_mask.png'))
    return mask.mean()


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
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(obj, depsgraph)
    lo, hi = bounds([v.co for v in obj.data.vertices])
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
    """Small lumps out, shape kept: corrective smooth, then smooth shading with creases kept."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    smooth = obj.modifiers.new('iron', 'CORRECTIVE_SMOOTH')
    smooth.factor = 0.6
    smooth.iterations = 8
    smooth.smooth_type = 'SIMPLE'
    smooth.use_only_smooth = True
    smooth.rest_source = 'ORCO'
    bpy.ops.object.modifier_apply(modifier='iron')
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(42), keep_sharp_edges=True)
    if 'Smooth by Angle' in obj.modifiers:
        bpy.ops.object.modifier_apply(modifier='Smooth by Angle')
    # Normals weighted by face area: big panels stay flat and clean, no smeared reflections
    weighted = obj.modifiers.new('weighted', 'WEIGHTED_NORMAL')
    weighted.keep_sharp = True
    weighted.weight = 70
    bpy.ops.object.modifier_apply(modifier='weighted')


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
        elif bright > 0.62 and spread < 0.2 and c.x > hi.x - 0.45 and poly.normal.x > 0.3 and height < 0.75:
            head.add(poly.index)
    return glass, head


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def convert(car, src, out):
    reset()
    obj = load(os.path.join(src, car['id'], 'model.glb'))
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
    tyre_faces = set()
    bm = bmesh.new()
    bm.from_mesh(keep.data)
    bm.faces.ensure_lookup_table()
    # The tyre is the outermost ring: faces far from the axle
    for f in bm.faces:
        c = f.calc_center_median()
        if math.hypot(c.x, c.z) > fl_radius * 0.78:
            tyre_faces.add(f.index)
    bm.free()
    tire = split(keep, tyre_faces, 'tire')
    keep.name = 'rim'
    keep.data.name = 'rim'
    light = taillights(obj)
    iron(obj)
    glass_faces, head_faces = classify_faces(obj, car)
    extra = []
    if head_faces:
        extra.append(split(obj, head_faces, 'headlight'))
    glass_faces, _ = classify_faces(obj, car)
    if glass_faces:
        extra.append(split(obj, glass_faces, 'glass'))
    print(f"  {car['id']}: glass {len(glass_faces)} faces, headlights {len(head_faces)} faces")
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


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    src, out = args[0], args[1]
    only = args[2:] if len(args) > 2 else None
    for car in CARS:
        if only and car['id'] not in only:
            continue
        convert(car, src, out)
