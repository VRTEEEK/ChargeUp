# Prepares a Meshy-style single-material lantern for the lantern slots.
#
#   Blender -b --python prep_lantern.py -- <in.usdz> <out.usdz> <targetTris> <heightM> [preview]
#
# Applies the import transform, scales to <heightM> tall, splits the faces
# whose base-colour texture is bright saturated amber (the panes and the
# inlaid stars) into a material named "Glass" (the app swaps it for the
# LanternGlass shader; docs/assets.md), names the rest "Brass", decimates to
# about <targetTris> triangles and exports a Y-up USDZ with its base centre
# at the origin. With "preview", Glass is flat cyan so the split can be seen.
import bpy, sys, colorsys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
src, dst, target, height = argv[0], argv[1], int(argv[2]), float(argv[3])
preview = len(argv) > 4 and argv[4] == "preview"
# Amber glass: warm hue, bright, saturated. The gold frame is less saturated.
HUE = (20.0, 60.0); MIN_V = 0.76; MIN_S = 0.66

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=src)
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o is not mesh: bpy.data.objects.remove(o)

me = mesh.data
brass = me.materials[0]
brass.name = "Brass"
glass = brass.copy(); glass.name = "Glass"
if preview:
    bsdf = [n for n in glass.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    for link in list(glass.node_tree.links):
        if link.to_node == bsdf and link.to_socket.name == "Base Color":
            glass.node_tree.links.remove(link)
    bsdf.inputs["Base Color"].default_value = (0, 1, 1, 1)
me.materials.append(glass)

img = [n.image for n in brass.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and n.image.colorspace_settings.name == 'sRGB'][0]
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
uv = me.uv_layers.active.data
glass_count = 0
for p in me.polygons:
    u = sum(uv[l].uv.x for l in p.loop_indices) / p.loop_total
    v = sum(uv[l].uv.y for l in p.loop_indices) / p.loop_total
    x = min(w - 1, max(0, int((u % 1) * w))); y = min(h - 1, max(0, int((v % 1) * h)))
    r, g, b, _ = px[y, x]
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    if HUE[0] <= hh * 360 <= HUE[1] and vv >= MIN_V and ss >= MIN_S:
        p.material_index = 1; glass_count += 1
    else:
        p.material_index = 0
print("GLASS faces", glass_count, "of", len(me.polygons))

# Scale to height, base centre at the origin (Blender Z is up here).
vs = [v.co for v in me.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
s = height / (hi.z - lo.z)
c = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
for v in me.vertices: v.co = (v.co - c) * s
me.update()

tris = sum(len(p.vertices) - 2 for p in me.polygons)
m = mesh.modifiers.new("dec", 'DECIMATE'); m.ratio = min(1.0, target / tris); m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
print("TRIS", sum(len(p.vertices) - 2 for p in me.polygons), "DIMS", tuple(round(d, 4) for d in mesh.dimensions))
# One mesh per material, so the app can measure the glass on its own
# (the LanternGlass fill rises over the glass's height, not the lantern's).
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='MATERIAL'); bpy.ops.object.mode_set(mode='OBJECT')
for o in bpy.data.objects:
    if o.type == 'MESH' and o.data.materials:
        o.name = o.data.materials[0].name; o.data.name = o.name
bpy.ops.wm.usd_export(filepath=dst, selected_objects_only=False, export_materials=True,
                      convert_orientation=True, generate_preview_surface=True, generate_materialx_network=False,
                      usdz_downscale_size="KEEP",
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                      root_prim_path="/Root")
print("EXPORTED", dst)
