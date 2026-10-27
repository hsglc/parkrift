"""Converts the Meshy AI street props (original designs) into USDZ for the game, using Blender
as a Python module.

traffic light: scaled to 4.6 m, turned so the lenses face +X (game), feet at y = 0, decimated,
texture shrunk to 512 px. The red/amber/green lens centers are found from the texture colors and
printed for World3D (the lit lamp is moved between them).

Usage: python convert_meshy_props.py <traffic light glb> <Hop/Models>
"""
import sys, os, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix

HEIGHT = 4.6
BUDGET = 900


def main(src, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    for o in list(bpy.context.scene.objects):
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    for o in list(bpy.context.scene.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    m = obj.data
    lo = Vector((min(v.co.x for v in m.vertices), min(v.co.y for v in m.vertices), min(v.co.z for v in m.vertices)))
    hi = Vector((max(v.co.x for v in m.vertices), max(v.co.y for v in m.vertices), max(v.co.z for v in m.vertices)))
    scale = HEIGHT / (hi.z - lo.z)
    pole = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    # Lenses face -Y in the source; turn them to +X
    m.transform(Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-pole))
    m.update()

    # Lens centers from the texture colors
    image = next(i for i in bpy.data.images if i.size[0] > 0)
    w, h = image.size
    px = np.array(image.pixels[:]).reshape(h, w, 4)
    uv = m.uv_layers.active.data
    groups = {'red': [], 'amber': [], 'green': []}
    for p in m.polygons:
        u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
        r, g, b, _ = px[int(v * h) % h, int(u * w) % w]
        if r > 0.45 and g < 0.25 and b < 0.25:
            groups['red'].append(p.center.copy())
        elif r > 0.5 and 0.25 < g < 0.75 and b < 0.25:
            groups['amber'].append(p.center.copy())
        elif g > 0.4 and r < 0.3 and b < 0.45:
            groups['green'].append(p.center.copy())
    for name, points in groups.items():
        c = sum(points, Vector()) / len(points)
        front = max(p.x for p in points)
        # Game axes: x forward (lens facing), y up, z right (= -Blender y)
        print(f"LENS {name}: x {front:.3f}, y {c.z:.3f}, z {-c.y:.3f}")

    mod = obj.modifiers.new('decimate', 'DECIMATE')
    tris = sum(len(p.vertices) - 2 for p in m.polygons)
    mod.ratio = min(1, BUDGET / tris)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print('tris', sum(len(p.vertices) - 2 for p in obj.data.polygons))

    obj.name = 'signal'
    obj.data.name = 'signal'
    for k, layer in enumerate(obj.data.uv_layers):
        layer.name = 'st' if k == 0 else f'st{k}'
    for mat in bpy.data.materials:
        mat.name = 'signal'
    for k, img in enumerate(bpy.data.images):
        img.name = f'signal_tex{k}'
    bpy.ops.wm.usd_export(filepath=os.path.join(out, 'signal.usdz'), selected_objects_only=True, export_materials=True,
                          export_textures_mode='NEW', overwrite_textures=True, export_uvmaps=True, export_normals=True,
                          generate_preview_surface=True, generate_materialx_network=False, convert_orientation=True,
                          export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          export_animation=False, triangulate_meshes=True, export_lights=False, export_cameras=False,
                          usdz_downscale_size='512', merge_parent_xform=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0], args[1])
