import bpy, sys, bmesh
import numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index("--")+1:]
src, dst, ratio = argv[0], argv[1], float(argv[2])
# Meshy splits its meshes along every UV seam, so the triangles of one surface
# are separate pieces sharing positions. Decimated apart, each piece shrinks
# away from its neighbours and the model shows gaps. Welding coincident
# vertices first (this distance, in the file's units) joins them into one
# surface; the UVs live on the face corners, so the seams survive. 0 skips it.
weld = float(argv[3]) if len(argv) > 3 else 1e-5
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=src)
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
# Unparent and bake the import's Y-up -> Z-up rotation into the vertices.
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o is not mesh: bpy.data.objects.remove(o)
def open_edges(tag):
    me = mesh.data
    idx = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("edge_index", idx)
    uses = np.bincount(idx, minlength=len(me.edges))
    print("OPEN %s: %d of %d edges on one face only (%.1f%%), %d verts, %d faces" % (
        tag, int((uses == 1).sum()), len(me.edges), 100.0 * (uses == 1).sum() / max(1, len(me.edges)),
        len(me.vertices), len(me.polygons)))
open_edges("source")
if weld > 0:
    w = mesh.modifiers.new("weld", 'WELD'); w.merge_threshold = weld; w.mode = 'ALL'
    bpy.ops.object.modifier_apply(modifier="weld")
    open_edges("welded")
# The ratio is of the source's triangles, whatever the weld did to the count.
m = mesh.modifiers.new("dec", 'DECIMATE'); m.ratio = ratio; m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
open_edges("decimated")
# Origin at the base centre (Blender Z is up here).
vs = [v.co for v in mesh.data.vertices]
minz = min(v.z for v in vs)
cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
cy = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
for v in mesh.data.vertices: v.co -= Vector((cx, cy, minz))
mesh.data.update()
mesh.name = "tree"; mesh.data.name = "tree"
print("POLYS", len(mesh.data.polygons), "VERTS", len(mesh.data.vertices), "DIMS", tuple(round(d, 3) for d in mesh.dimensions))
bpy.ops.wm.usd_export(filepath=dst, selected_objects_only=False, export_materials=True,
                      convert_orientation=True, generate_preview_surface=True, generate_materialx_network=False, usdz_downscale_size="KEEP",
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                      root_prim_path="/Root")
print("EXPORTED", dst)
