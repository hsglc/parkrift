"""Light versions of the traffic cars' bodies for distance: the textured shell of each
npc_<id>_body.usdz reduced to about a fifth (collapse decimation keeps the UVs, so the same
texture and paint mask still fit), written as npc_<id>_body_lod.usdz with the mesh "textured".
The game swaps it in a little way off (TrafficVehicles.body).

Usage: python (bpy) make_npc_lods.py <Hop/Models>
"""
import os, sys
import bpy

MODELS = sys.argv[-1]
for name in ('hatch', 'sedan', 'suv', 'pickup', 'police'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=os.path.join(MODELS, f'npc_{name}_body.usdz'))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    shell = next(o for o in meshes if o.name.startswith('textured'))
    for o in list(bpy.data.objects):
        if o is not shell:
            bpy.data.objects.remove(o, do_unlink=True)
    shell.parent = None
    bpy.context.view_layer.objects.active = shell
    shell.select_set(True)
    before = sum(len(p.vertices) - 2 for p in shell.data.polygons)
    mod = shell.modifiers.new('d', 'DECIMATE')
    mod.ratio = 0.22
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='d')
    after = len(shell.data.polygons)
    shell.name = 'textured'
    shell.data.name = 'textured'
    shell.data.materials.clear()
    if shell.data.uv_layers:
        shell.data.uv_layers[0].name = 'st'
    for p in shell.data.polygons:
        p.use_smooth = True
    bpy.ops.wm.usd_export(filepath=os.path.join(MODELS, f'npc_{name}_body_lod.usdz'), selected_objects_only=True,
                          export_materials=False, export_uvmaps=True, export_normals=True, convert_orientation=True,
                          export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          export_animation=False, triangulate_meshes=True, merge_parent_xform=True)
    print(f'NPC {name}: {before} -> {after} triangles')
