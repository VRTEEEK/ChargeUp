# Prepares a Meshy charging-port disc (dome up, single material) for the
# port_ring slot.
#
#   Blender -b --python prep_port.py -- <in.usdz> <out.usdz> <targetTris> <diameterM> \
#       <glassRadius> <minSaturation> <coreRadius> [thicknessM] [preview]
#
# The port's glass and its gold frame share one amber hue, so colour alone
# cannot split them (prep_lantern.py's test). Here a face is "Glass" (the app
# swaps it for the LanternGlass shader, which the step visuals drive) when it
# is inside <glassRadius> (a fraction of the disc's radius, inside the inner
# gold ring), faces up, and its base colour is at least <minSaturation>
# saturated: the deep amber panes, not the paler bars. Inside <coreRadius>
# (inside the central star's frame) every upward face is Glass, since the
# star's own pane is pale and bright rather than saturated. Two passes of
# neighbour majority vote then clear specks. Everything else is "Brass".
# Scales to <diameterM> across, puts the base centre at the origin (+Y out
# of the skin), decimates to about <targetTris> and exports one mesh per
# material. With "preview", Glass is flat cyan so the split can be checked.
import bpy, bmesh, sys, colorsys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
src, dst, target, diameter = argv[0], argv[1], int(argv[2]), float(argv[3])
glass_radius, min_sat, core_radius = float(argv[4]), float(argv[5]), float(argv[6])
extra = argv[7:]
preview = "preview" in extra
# Optional: squash the disc to this thickness (a jewel, not a coin). Applied
# after the Glass split, which reads the unsquashed normals.
thickness = next((float(x) for x in extra if x != "preview"), None)

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

# Scale to the diameter, base centre at the origin (Blender Z is up here).
vs = [v.co for v in me.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
s = diameter / max(hi.x - lo.x, hi.y - lo.y)
c = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
for v in me.vertices: v.co = (v.co - c) * s
me.update()
radius = diameter / 2

img = [n.image for n in brass.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and n.image.colorspace_settings.name == 'sRGB'][0]
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
uv = me.uv_layers.active.data
is_glass = np.zeros(len(me.polygons), dtype=bool)
for p in me.polygons:
    cen = p.center
    r = (cen.x ** 2 + cen.y ** 2) ** 0.5
    if r > glass_radius * radius or p.normal.z < 0.2:
        continue
    if r < core_radius * radius:
        is_glass[p.index] = True
        continue
    u = sum(uv[l].uv.x for l in p.loop_indices) / p.loop_total
    v = sum(uv[l].uv.y for l in p.loop_indices) / p.loop_total
    x = min(w - 1, max(0, int((u % 1) * w))); y = min(h - 1, max(0, int((v % 1) * h)))
    _, sat, _ = colorsys.rgb_to_hsv(*px[y, x, :3])
    is_glass[p.index] = sat >= min_sat

# Majority vote over edge neighbours, twice: clears single-face specks and
# fills pinholes without moving the real edges of a pane.
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
neighbours = [[g.index for e in f.edges for g in e.link_faces if g is not f] for f in bm.faces]
bm.free()
for _ in range(2):
    votes = np.array([is_glass[n].mean() if n else is_glass[i] for i, n in enumerate(neighbours)])
    is_glass = np.where(votes > 0.5, True, np.where(votes < 0.5, False, is_glass))
for p in me.polygons:
    p.material_index = 1 if is_glass[p.index] else 0
print("GLASS faces", int(is_glass.sum()), "of", len(me.polygons))
if thickness:
    height = max(v.co.z for v in me.vertices)
    for v in me.vertices: v.co.z *= thickness / height
    me.update()

tris = sum(len(p.vertices) - 2 for p in me.polygons)
m = mesh.modifiers.new("dec", 'DECIMATE'); m.ratio = min(1.0, target / tris); m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
print("TRIS", sum(len(p.vertices) - 2 for p in me.polygons), "DIMS", tuple(round(d, 4) for d in mesh.dimensions))
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
