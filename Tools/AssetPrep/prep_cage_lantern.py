# Prepares an open-cage lantern (no glass panes, e.g. max_lantern) for the
# lantern slots.
#
#   Blender -b --python prep_cage_lantern.py -- <in.usdz> <out.usdz> <targetTris> <heightM> \
#       <glassBottom> <glassTop> <glassRadius>
#
# The cage has nothing for the LanternGlass shader to fill, so this adds a
# glass column inside it, as real lanterns hold their light: an open-ended
# cylinder with a material named "Glass" (the app swaps it for the
# LanternGlass shader; docs/assets.md), so the light rises through the
# whole cage rather than sitting in it as a ball. The three numbers are
# fractions of the lantern's height: where the column starts and ends above
# the base and its radius. Measure the cage first (inner radius per height
# slice): the column sits just inside the bars, from the tray to under the
# dome, and anything hanging inside the cage hangs inside the glass. The
# model keeps its own texture as "Brass". Applies the
# import transform, scales to <heightM> tall, decimates the model to about
# <targetTris> triangles and exports a Y-up USDZ with its base centre at
# the origin, one mesh per material.
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
src, dst, target, height = argv[0], argv[1], int(argv[2]), float(argv[3])
glass_bottom, glass_top, glass_radius = float(argv[4]), float(argv[5]), float(argv[6])

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
me.materials[0].name = "Brass"
mesh.name = "Brass"; me.name = "Brass"

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

# No end caps: the tray closes the bottom and the dome hides the top.
depth = (glass_top - glass_bottom) * height
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=glass_radius * height, depth=depth, end_fill_type='NOTHING',
                                    location=(0, 0, (glass_bottom + glass_top) / 2 * height))
column = bpy.context.active_object
bpy.ops.object.shade_smooth()
glass = bpy.data.materials.new("Glass")
column.data.materials.append(glass)
column.name = "Glass"; column.data.name = "Glass"
print("GLASS z %.4f..%.4f r %.4f" % (glass_bottom * height, glass_top * height, glass_radius * height))

bpy.ops.wm.usd_export(filepath=dst, selected_objects_only=False, export_materials=True,
                      convert_orientation=True, generate_preview_surface=True, generate_materialx_network=False,
                      usdz_downscale_size="KEEP",
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                      root_prim_path="/Root")
print("EXPORTED", dst)
