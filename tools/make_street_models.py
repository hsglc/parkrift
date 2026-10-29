"""Models the city's street trees and traffic light in Blender (all original), smooth and in
more detail than the boxes and spheres they replace, and writes them as USDZ for the game.

Trees (tree_0..2.usdz, meshes "bark" and "leaves", metres, y up, standing on the origin):
  a curved trunk with a root flare and four to five tapering limbs, under a crown built from
  a dozen noise-displaced blobs fused into one rounded, lumpy canopy (voxel remesh) and reduced
  to a light mesh, shaded smooth. UVs are box-projected so the bark (Poly Haven bark_platanus)
  and the painted foliage texture (tools/make_foliage_texture.py) repeat at a natural scale.

Traffic light (signal.usdz, lenses facing +x, pole on the origin), meshes by part so the game
gives each its material: "pole" (tapered round mast with a flared foot and a cap), "housing"
(rounded three-lamp head), "visor" (hoods over the lenses), "plate" (backboard) and "border"
(its white edge), "lens" (smoked glass), "button" (push button box). The lit lens the game adds
sits at the same three points as before: x 0.075, heights 4.248, 3.896, 3.522 m.

Usage: blender -b -P make_street_models.py -- <Hop/Models>   (or Blender as a Python module)
"""
import sys, os, math, random
import bpy, bmesh
from mathutils import Vector, Matrix, noise

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
OUT = args[0]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def apply_all(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def smooth(obj, angle=50):
    for p in obj.data.polygons:
        p.use_smooth = True
    try:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
        apply_all(obj)
    except Exception:
        pass


def box_uv(obj, size):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=size)
    bpy.ops.object.mode_set(mode='OBJECT')


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


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


# ------------------------------------------------------------------ trees

def limb(points, radii, name, sides=10):
    """A tapering tube along points (a poly curve with per-point radius), as a mesh."""
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = 1.0
    curve.bevel_resolution = max(1, (sides - 4) // 2)
    curve.use_fill_caps = True
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co, r in zip(spline.points, points, radii):
        p.co = (co[0], co[1], co[2], 1)
        p.radius = r
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def bezier_points(a, b, bend, steps=6):
    out = []
    mid = (a + b) / 2 + bend
    for i in range(steps + 1):
        t = i / steps
        out.append(a * (1 - t) ** 2 + mid * 2 * t * (1 - t) + b * t * t)
    return out


def make_tree(seed):
    reset()
    random.seed(seed)
    height = random.uniform(2.3, 2.7)          # where the trunk splits
    lean = Vector((random.uniform(-0.15, 0.15), random.uniform(-0.15, 0.15), 0))
    parts = []
    # Trunk with a root flare: radius swells over the last 30 cm
    pts = bezier_points(Vector((0, 0, 0)), Vector((0, 0, height)) + lean, Vector((random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), 0)), 10)
    radii = [0.17 * (1.0 + 0.9 * max(0, 1 - p.z / 0.35) ** 2) * (1 - 0.25 * p.z / height) for p in pts]
    parts.append(limb(pts, radii, 'trunk', sides=14))
    top = pts[-1]
    # Limbs up into the crown
    count = random.choice([4, 5])
    crown_center = top + Vector((0, 0, 1.7))
    for i in range(count):
        a = 2 * math.pi * i / count + random.uniform(-0.35, 0.35)
        reach = random.uniform(1.0, 1.5)
        end = top + Vector((math.cos(a) * reach, math.sin(a) * reach, random.uniform(1.3, 1.9)))
        bend = Vector((math.cos(a) * 0.1, math.sin(a) * 0.1, -0.25))
        pts = bezier_points(top - Vector((0, 0, 0.2)), end, bend, 6)
        radii = [0.12 * (1 - 0.75 * k / (len(pts) - 1)) for k in range(len(pts))]
        parts.append(limb(pts, radii, f'limb{i}', sides=10))
    bark = join(parts, 'bark')
    smooth(bark, 60)
    box_uv(bark, 0.9)

    # Crown core: blobs round an ellipsoid, displaced by noise and fused by a voxel remesh,
    # shaded with the painted foliage (the dense inside of the canopy)
    blobs = []
    centers = []
    for i in range(13):
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(0.2, 1.35)
        h = random.uniform(-0.55, 0.85)
        c = crown_center + Vector((math.cos(a) * r, math.sin(a) * r, h))
        size = random.uniform(0.85, 1.25) * (1.15 - 0.25 * abs(h))
        centers.append((c, size))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=size * 0.82, location=c)
        blob = bpy.context.view_layer.objects.active
        blob.scale = (1.0, 1.0, random.uniform(0.75, 0.95))
        bpy.ops.object.transform_apply(scale=True)
        for v in blob.data.vertices:
            w = blob.matrix_world @ v.co
            d = noise.noise(w * 1.6 + Vector((seed, 0, 0)))
            v.co += v.normal * (0.16 * d)
        blobs.append(blob)
    core = join(blobs, 'core')
    remesh = core.modifiers.new('remesh', 'REMESH')
    remesh.mode = 'VOXEL'
    remesh.voxel_size = 0.12
    apply_all(core)
    sm = core.modifiers.new('smooth', 'SMOOTH')
    sm.factor = 0.6
    sm.iterations = 6
    dec = core.modifiers.new('decimate', 'DECIMATE')
    dec.ratio = min(1.0, 1400 / max(1, tris(core)))
    apply_all(core)
    smooth(core, 80)
    box_uv(core, 1.4)

    # Leaf sprays: cards (a transparent spray of twigs and leaves each) all over the canopy,
    # rooted inside it and pointing out, at every angle, so it reads as real foliage with
    # light coming through its edges
    mesh = bpy.data.meshes.new('leaves')
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new('st')
    cards = 0
    tries = 0
    while cards < 300 and tries < 5000:
        tries += 1
        c, size = random.choice(centers)
        d = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1) * 0.8 + 0.25)).normalized()
        base = c + d * size * random.uniform(0.55, 0.95)
        # Not inside another blob's middle (keeps cards on the outside)
        if any((base - o).length < s2 * 0.45 for o, s2 in centers):
            continue
        up = (d + Vector((random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(-0.2, 0.5)))).normalized()
        side = up.cross(Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1)))).normalized()
        if side.length < 0.1:
            continue
        w = random.uniform(1.0, 1.45)
        hgt = w * random.uniform(0.9, 1.1)
        p0 = base - side * w / 2 - up * hgt * 0.15
        p1 = base + side * w / 2 - up * hgt * 0.15
        p2 = p1 + up * hgt
        p3 = p0 + up * hgt
        quad = [p0, p1, p2, p3]
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
        # The lit face looks out of the crown (normals inward came out black on top)
        normal = (p1 - p0).cross(p3 - p0)
        outward = (base - crown_center).normalized() + Vector((0, 0, 0.6))
        if normal.dot(outward) < 0:
            quad = [p1, p0, p3, p2]
            uvs = [(1, 0), (0, 0), (0, 1), (1, 1)]
        verts = [bm.verts.new(p) for p in quad]
        face = bm.faces.new(verts)
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv
        cards += 1
    bm.to_mesh(mesh)
    bm.free()
    leaves = bpy.data.objects.new('leaves', mesh)
    bpy.context.scene.collection.objects.link(leaves)
    path = os.path.join(OUT, f'tree_{seed}.usdz')
    export([bark, core, leaves], path)
    hi = max((leaves.matrix_world @ v.co).z for v in leaves.data.vertices)
    print(f'TREE {seed}: bark {tris(bark)} tris, core {tris(core)}, cards {cards} ({tris(leaves)} tris), top {hi:.2f} m')


# ------------------------------------------------------------------ traffic light

def cylinder(name, radius, depth, location, verts=32, rotation=(0, 0, 0), radius2=None):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    return obj


def rounded_box(name, size, location, bevel=0.03, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.view_layer.objects.active
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    m = obj.modifiers.new('bevel', 'BEVEL')
    m.width = bevel
    m.segments = segments
    m.limit_method = 'ANGLE'
    apply_all(obj)
    obj.name = name
    return obj


def bevel_edges(obj, width, segments=3):
    m = obj.modifiers.new('bevel', 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    apply_all(obj)


def make_signal():
    reset()
    lens_z = [4.248, 3.896, 3.522]       # game heights (y up) of red, amber, green
    lens_x = 0.075
    # Pole: flared foot, tapered mast, cap; the head hangs in front of it
    pole_parts = []
    px = -0.42                           # the mast stands behind the head's backboard
    foot = cylinder('foot', 0.15, 0.32, (px, 0, 0.16), radius2=0.085)
    bevel_edges(foot, 0.015)
    pole_parts.append(foot)
    mast = cylinder('mast', 0.07, 4.3, (px, 0, 2.47), radius2=0.055)
    pole_parts.append(mast)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.065, location=(px, 0, 4.64))
    cap = bpy.context.view_layer.objects.active
    cap.scale = (1, 1, 0.6)
    pole_parts.append(cap)
    collar = cylinder('collar', 0.085, 0.06, (px, 0, 0.36))
    bevel_edges(collar, 0.012)
    pole_parts.append(collar)
    # Brackets holding the head
    for z in (3.45, 4.33):
        pole_parts.append(rounded_box('bracket', (0.17, 0.06, 0.06), (px + 0.09, 0, z), bevel=0.014))
    pole = join(pole_parts, 'pole')
    smooth(pole, 40)

    # Head: rounded housing behind the lenses
    hx = lens_x - 0.18                    # housing centre (depth 0.32, front face at lens_x - 0.02)
    housing = rounded_box('housing', (0.32, 0.36, 1.12), (hx, 0, 3.885), bevel=0.06, segments=4)
    smooth(housing, 40)
    # Visors: open half-tubes over each lens, angled slightly down
    visors = []
    for z in lens_z:
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.15, depth=0.2, location=(lens_x + 0.08, 0, z),
                                            rotation=(0, math.pi / 2, 0))
        tube = bpy.context.view_layer.objects.active
        bm = bmesh.new()
        bm.from_mesh(tube.data)
        # Keep the upper part only (a hood), remove the caps
        doomed = [f for f in bm.faces if f.calc_center_median().z < -0.04 or abs(f.normal.x) > 0.9]
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
        bm.to_mesh(tube.data)
        bm.free()
        sol = tube.modifiers.new('solid', 'SOLIDIFY')
        sol.thickness = 0.012
        apply_all(tube)
        tube.rotation_euler = (0, math.radians(-6), 0)
        bpy.ops.object.transform_apply(rotation=True)
        visors.append(tube)
    visor = join(visors, 'visor')
    smooth(visor, 50)
    # Lens glass (unlit): shallow domes
    lenses = []
    for z in lens_z:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=12, radius=0.13, location=(lens_x - 0.07, 0, z))
        dome = bpy.context.view_layer.objects.active
        dome.scale = (0.45, 1, 1)
        bpy.ops.object.transform_apply(scale=True)
        lenses.append(dome)
    lens = join(lenses, 'lens')
    smooth(lens, 80)
    # Backboard with a white border
    plate = rounded_box('plate', (0.02, 0.56, 1.32), (hx - 0.18, 0, 3.885), bevel=0.05, segments=4)
    border = rounded_box('border', (0.012, 0.6, 1.36), (hx - 0.192, 0, 3.885), bevel=0.06, segments=4)
    # Push button box for pedestrians
    button = rounded_box('button', (0.1, 0.12, 0.2), (px + 0.09, 0, 1.15), bevel=0.02)
    for o in (plate, border, button):
        smooth(o, 40)
    parts = [pole, housing, visor, lens, plate, border, button]
    # Game axes: lenses face +x as before
    export(parts, os.path.join(OUT, 'signal.usdz'))
    print('SIGNAL', ', '.join(f'{o.name} {tris(o)}' for o in parts))


if __name__ == '__main__':
    for seed in range(3):
        make_tree(seed)
    make_signal()
