"""Refines Polyfork's low poly cars in Blender before tools/convert_polyfork_cars.py converts them:
  - bodies: fused into one surface (voxel remesh), smoothed so edges and corners round off (a
    softer, more modern car), decimated back to ~14k triangles, original colours copied back,
  - wheels: a small bevel,
  - smooth shading, with hard edges kept where faces meet at a steep angle.
Vertex colours, node names (wheel-fl, ...) and the hierarchy are kept.

Usage: blender python: refine_polyfork_cars.py <folder with <asset>.glb> <output folder>
"""
import sys, os, math
import bpy, bmesh

SRC, OUT = sys.argv[-2], sys.argv[-1]
VOXEL = float(os.environ.get('VOXEL', '0.03'))
SMOOTH_STEPS = int(os.environ.get('SMOOTH_STEPS', '12'))
ASSETS = ['wedge-coupe-80s-9f8b5e', 'muscle-car-60s-524d46', 'convertible-60s-b76f89', 'hatchback-80s-e95554',
          'boxy-sedan-70s-7d55f7', 'station-wagon-70s-11d67b', 'pickup-truck-70s-8c0080', 'family-crossover-suv-42027f']


def refine(asset):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset + '.glb'))
    for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        mesh = obj.data
        # Weld the flat-shading duplicates so the bevel sees real edges
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.0004)
        bpy.ops.object.mode_set(mode='OBJECT')
        wheel = any(p.name.startswith('wheel') for p in iter_parents(obj))
        if not wheel:
            # Modern, rounder body: the separate boxy pieces are fused into one surface (voxel
            # remesh), smoothed so edges and corners round off, brought back to ~14k triangles,
            # and the original colours are copied back from the nearest face of the original
            original = obj.copy()
            original.data = mesh.copy()
            bpy.context.scene.collection.objects.link(original)
            obj.data.remesh_voxel_size = VOXEL
            obj.data.remesh_voxel_adaptivity = 0.0
            bpy.ops.object.voxel_remesh()
            mesh = obj.data
            smooth = obj.modifiers.new('smooth', 'LAPLACIANSMOOTH')
            smooth.iterations = SMOOTH_STEPS
            smooth.lambda_factor = 0.8
            smooth.use_volume_preserve = True
            smooth.use_normalized = True
            bpy.ops.object.modifier_apply(modifier='smooth')
            dec = obj.modifiers.new('dec', 'DECIMATE')
            dec.ratio = min(1.0, int(os.environ.get('FACES', '10000')) / max(1, len(mesh.polygons)))
            dec.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier='dec')
            mesh = obj.data
            src_colour, data_type = copy_face_colours(original, obj, asset)
            add_lamps(original, obj, src_colour, data_type)
            mesh = obj.data
            bpy.data.objects.remove(original, do_unlink=True)
        else:
            bevel = obj.modifiers.new('bevel', 'BEVEL')
            bevel.width = 0.012
            bevel.segments = 2
            bevel.limit_method = 'ANGLE'
            bevel.angle_limit = math.radians(32)
            bevel.harden_normals = True
            bevel.use_clamp_overlap = True
            bpy.ops.object.modifier_apply(modifier='bevel')
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50), keep_sharp_edges=True)
        if 'Smooth by Angle' in obj.modifiers:
            bpy.ops.object.modifier_apply(modifier='Smooth by Angle')
        print(asset, obj.name, 'faces', len(mesh.polygons))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, asset + '.glb'), export_format='GLB',
                              export_normals=True, export_vertex_color='ACTIVE', export_all_vertex_colors=True,
                              export_apply=True, export_yup=True)


CARS = {   # asset -> paint knobs, knobs recoloured dark (as in convert_polyfork_cars.CARS)
    'wedge-coupe-80s-9f8b5e': ({'upper': 0.92}, {}),
    'muscle-car-60s-524d46': ({'upper': 0.92, 'lower': 0.5}, {'roof': '#1a1f27'}),
    'convertible-60s-b76f89': ({'body': 0.92}, {}),
    'hatchback-80s-e95554': ({'upper': 0.92, 'lower': 0.5}, {}),
    'boxy-sedan-70s-7d55f7': ({'upper': 0.92, 'lower': 0.5}, {}),
    'station-wagon-70s-11d67b': ({'body': 0.92}, {}),
    'pickup-truck-70s-8c0080': ({'primary': 0.92, 'secondary': 0.5}, {'roof': '#1a1f27'}),
    'family-crossover-suv-42027f': ({'body': 0.92}, {}),
}
LAMP_LINEAR = []
TONES = {}


def to_linear(c255):
    import numpy as np
    c = np.asarray(c255, dtype=float) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def clean_palette(src, linear, asset):
    """A modern, clean colour set for the smooth body: everything that is not glass, a lamp or
    dark trim (chrome strips, grey bumpers, odd small parts) becomes body paint, so after the
    rounding no piece looks bare or unpainted."""
    import json
    import numpy as np
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from polyfork_car_classes import classify, hex255
    c = np.clip(linear, 0, 1)
    c255 = np.round(np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255)
    centres = np.array([p.center[:] for p in src.polygons])
    fwd = -centres[:, 1]
    fwd = fwd - (fwd.max() + fwd.min()) / 2
    length = np.ptp(fwd)
    params = json.load(open(os.path.join(SRC, asset + '-params.json')))['params']
    knobs = {k: v['default'] for k, v in params.items() if v['type'] == 'color'}
    paint, recolor = CARS[asset]
    classes, _ = classify(c255, fwd, length, knobs, paint, recolor)
    main = hex255(knobs[next(iter(paint))])
    out = c255.copy()
    out[np.isin(classes, ['chrome', 'other'])] = main
    out[classes == 'dark'] = hex255('#0c0e14')
    for k, v in recolor.items():
        out[np.linalg.norm(c255 - hex255(knobs[k]), axis=1) < 4.5] = hex255(v)
    TONES['main'] = to_linear(main)
    TONES['dark'] = to_linear(hex255('#0c0e14'))
    LAMP_LINEAR[:] = list(to_linear(np.unique(out[np.isin(classes, ['headlight', 'taillight'])], axis=0)))
    print(asset, {k: int((classes == k).sum()) for k in set(classes)}, flush=True)
    return to_linear(out)


def merge_islands(keys, neighbours, lamp_keys, small=40, lamp_small=4):
    """Patches of one colour smaller than `small` faces take the colour around them."""
    for _ in range(3):
        seen = [False] * len(keys)
        changed = False
        for start in range(len(keys)):
            if seen[start]:
                continue
            island, stack = [], [start]
            seen[start] = True
            while stack:
                i = stack.pop()
                island.append(i)
                for j in neighbours[i]:
                    if not seen[j] and keys[j] == keys[start]:
                        seen[j] = True
                        stack.append(j)
            limit = lamp_small if keys[start] in lamp_keys else small
            if len(island) >= limit:
                continue
            members = set(island)
            votes = {}
            for i in island:
                for j in neighbours[i]:
                    if j not in members:
                        votes[keys[j]] = votes.get(keys[j], 0) + 1
            if votes:
                top = max(votes.items(), key=lambda kv: kv[1])[0]
                for i in island:
                    keys[i] = top
                changed = True
        if not changed:
            break
    return keys


def copy_face_colours(original, obj, asset):
    """Each new face takes the colour of the original face right under it (a ray along the
    face normal, both ways, then the closest point), one flat colour per face: no blending
    across pieces, so paint, glass and chrome keep clean borders."""
    import numpy as np
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    src = original.data
    layer = src.color_attributes[0]
    corner = np.zeros(len(src.loops) * 4)
    layer.data.foreach_get('color', corner)
    corner = corner.reshape(-1, 4)
    src_colour = np.array([corner[p.loop_start] for p in src.polygons])
    src_colour[:, :3] = clean_palette(src, src_colour[:, :3], asset)
    src_colour = np.round(src_colour, 4)
    tree = BVHTree.FromObject(original, bpy.context.evaluated_depsgraph_get())
    mesh = obj.data
    picked = np.zeros((len(mesh.polygons), 4))
    for f in mesh.polygons:
        c, n = f.center, f.normal
        best = None
        for d in (-n, n):
            hit = tree.ray_cast(c + d * -0.001, d, 0.12)
            if hit[0] is not None and (best is None or hit[3] < best[1]):
                best = (hit[2], hit[3])
        if best is None:
            _, _, idx, _ = tree.find_nearest(c)
            best = (idx, 0)
        picked[f.index] = src_colour[best[0]]
        # Bonnet and roof are never black: dark there is the engine bay or a recess showing
        # through after the rounding
        if n.z > 0.45 and np.allclose(picked[f.index][:3], TONES['dark'], atol=2e-3):
            picked[f.index][:3] = TONES['main']
    # Clean the borders: a face whose edge neighbours mostly share another colour takes it
    # (removes the saw teeth and single stray faces where pieces meet)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    neighbours = [[l.link_loop_radial_next.face.index for l in f.loops if l.link_loop_radial_next != l]
                  for f in bm.faces]
    bm.free()
    keys = [tuple(np.round(c, 3)) for c in picked]
    for _ in range(4):
        changed = 0
        new_keys = list(keys)
        for i, nb in enumerate(neighbours):
            votes = {}
            for j in nb:
                votes[keys[j]] = votes.get(keys[j], 0) + 1
            if not votes:
                continue
            top, count = max(votes.items(), key=lambda kv: kv[1])
            if top != keys[i] and count >= 2:
                new_keys[i] = top
                changed += 1
        keys = new_keys
        if not changed:
            break
    keys = merge_islands(keys, neighbours, lamp_keys={tuple(np.round(c, 3)) for c in LAMP_LINEAR})
    picked = np.array(keys)
    # Split the mesh where the colour changes, so the exported per-vertex colours stay flat
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    cut = [e for e in bm.edges if len(e.link_faces) == 2 and keys[e.link_faces[0].index] != keys[e.link_faces[1].index]]
    bmesh.ops.split_edges(bm, edges=cut)
    bm.to_mesh(mesh)
    bm.free()
    for old in list(mesh.color_attributes):
        mesh.color_attributes.remove(old)
    attr = mesh.color_attributes.new('Color', layer.data_type, 'CORNER')
    counts = np.array([f.loop_total for f in mesh.polygons])
    attr.data.foreach_set('color', np.repeat(picked, counts, axis=0).ravel().astype(np.float32))
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
    return src_colour, layer.data_type


def add_lamps(original, obj, src_colour, data_type):
    """The original head and tail lamp faces, lifted just above the smooth body and joined to
    it, so the lamps stay crisp and light up in the game."""
    import numpy as np
    lamp_keys = {tuple(np.round(c, 3)) for c in LAMP_LINEAR}
    keys = [tuple(np.round(c[:3], 3)) for c in src_colour]
    keep = {i for i, k in enumerate(keys) if k in lamp_keys}
    if not keep:
        return
    bm = bmesh.new()
    bm.from_mesh(original.data)
    bm.faces.ensure_lookup_table()
    colours = [src_colour[f.index] for f in bm.faces if f.index in keep]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context='FACES')
    bmesh.ops.split_edges(bm, edges=list(bm.edges))
    for f in bm.faces:
        for v in f.verts:
            v.co += f.normal * 0.012
    lamp_mesh = bpy.data.meshes.new('lamps')
    bm.to_mesh(lamp_mesh)
    bm.free()
    for old in list(lamp_mesh.color_attributes):
        lamp_mesh.color_attributes.remove(old)
    attr = lamp_mesh.color_attributes.new('Color', data_type, 'CORNER')
    counts = np.array([f.loop_total for f in lamp_mesh.polygons])
    attr.data.foreach_set('color', np.repeat(np.array(colours), counts, axis=0).ravel().astype(np.float32))
    lamp = bpy.data.objects.new('lamps', lamp_mesh)
    lamp.matrix_world = obj.matrix_world.copy()
    bpy.context.scene.collection.objects.link(lamp)
    bpy.ops.object.select_all(action='DESELECT')
    lamp.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


def iter_parents(obj):
    p = obj.parent
    while p:
        yield p
        p = p.parent


os.makedirs(OUT, exist_ok=True)
for asset in ASSETS:
    if os.environ.get('ONLY') and not any(k in asset for k in os.environ['ONLY'].split(',')):
        continue
    refine(asset)
