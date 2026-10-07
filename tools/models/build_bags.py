"""Модели поясной сумки и рюкзака New-York Roleplay (Blender / bpy).

Запуск:  python3 tools/models/build_bags.py
Делает:
  tools/models/bags.blend                    исходник с анимациями (open/close)
  tools/models/src/*.smd, *.qc               для компиляции в .mdl (studiomdl / Crowbar)
  content/materials/models/nyrp/bags/*.vtf/.vmt  текстуры
  gamemode/modules/bags/cl_bag_meshes.lua    геометрия + анимация для отрисовки в игре через Mesh()
  branding/bags_preview.png                  превью

Оси модели (единицы Source): +X — от владельца вперёд, +Y — влево, +Z — вверх.
"""
import math
import os
import struct

import bpy  # noqa: I001 — bpy первым, он регистрирует bmesh/mathutils
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "tools", "models", "src")
GM = os.path.join(ROOT, "gamemodes", "newyorkrp")
MATDIR = os.path.join(GM, "content", "materials", "models", "nyrp", "bags")
FPS = 30
OPEN_FRAMES = 24

MATERIALS = {
    # имя: (базовый цвет, шум, «ткань»)
    "bag_fabric": ((64, 62, 60), 10, True),
    "bag_strap": ((32, 32, 36), 6, True),
    "bag_metal": ((150, 150, 155), 8, False),
    "bag_accent": ((247, 198, 0), 6, True),
    "bag_inner": ((70, 64, 58), 6, True),
}


# ---------------------------------------------------------------- helpers ---

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.fps = FPS
    scn.frame_start, scn.frame_end = 0, OPEN_FRAMES
    for name, (col, _, _) in MATERIALS.items():
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*(c / 255 for c in col), 1)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*((c / 255) ** 2.2 for c in col), 1)
        bsdf.inputs["Roughness"].default_value = 0.4 if name == "bag_metal" else 0.85
        if name == "bag_metal":
            bsdf.inputs["Metallic"].default_value = 0.9


def new_object(name, bm, material, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials[material])
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def rounded_box(size, center=(0, 0, 0), bevel=1.0, segments=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, profile=0.5, affect="EDGES")
    return bm


def cut(bm, z, keep_above):
    """Режет меш плоскостью z и закрывает срез."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1),
                                 clear_inner=keep_above, clear_outer=not keep_above)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    return bm


def tube(points, radius_x, radius_z, segments=6):
    """Лента/ремень по ломаной: прямоугольное скруглённое сечение."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        p = Vector(p)
        a = Vector(points[max(i - 1, 0)])
        b = Vector(points[min(i + 1, len(points) - 1)])
        tangent = (b - a).normalized()
        up = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
        side = tangent.cross(up).normalized()
        up = side.cross(tangent).normalized()
        ring = []
        for s in range(segments):
            ang = 2 * math.pi * s / segments
            off = side * math.cos(ang) * radius_x + up * math.sin(ang) * radius_z
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for s in range(segments):
            bm.faces.new((r0[s], r0[(s + 1) % segments], r1[(s + 1) % segments], r1[s]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def ellipse_path(cx, cy, rx, ry, z, a0, a1, n=24):
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / n), cy + ry * math.sin(a0 + (a1 - a0) * i / n), z)
            for i in range(n + 1)]


def set_origin(ob, pivot):
    """Переносит origin объекта в точку pivot (мировые координаты), меш не двигается."""
    pivot = Vector(pivot)
    ob.data.transform(Matrix.Translation(-pivot))
    ob.location = pivot
    for child in ob.children:  # дочерние меши заданы в мировых координатах
        child.matrix_parent_inverse = Matrix.Translation(-pivot)


def box_uv(ob, scale=0.12):
    me = ob.data
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co + ob.location
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uv.data[li].uv = (u * scale, v * scale)


# ---------------------------------------------------------------- models ---

def build_waistbag():
    root = bpy.data.objects.new("waistbag", None)
    bpy.context.collection.objects.link(root)
    L, D, H = 13.0, 5.0, 7.0   # длина (Y), глубина (X), высота (Z)
    seam = 1.2

    body = new_object("waistbag_body", cut(rounded_box((D, L, H), bevel=2.0, segments=4), seam, False),
                      "bag_fabric", root)
    lid = new_object("waistbag_lid", cut(rounded_box((D, L, H), bevel=2.0, segments=4), seam, True),
                     "bag_fabric", root)
    set_origin(lid, (-D / 2, 0, seam))

    # внутренняя тёмная поверхность (видна при открытии)
    inner = new_object("waistbag_inner", rounded_box((D - 1.0, L - 1.0, 0.2), center=(0, 0, seam - 0.15), bevel=0.08, segments=1),
                       "bag_inner", root)

    # молния по шву
    zip_band = new_object("waistbag_zipband", cut(cut(rounded_box((D + 0.25, L + 0.25, H + 0.25), bevel=2.1, segments=4),
                                                      seam + 0.25, False), seam - 0.25, True), "bag_strap", root)
    slider = rounded_box((0.9, 1.2, 0.5), center=(D / 2 + 0.1, L / 2 - 2.6, seam + 0.1), bevel=0.15, segments=2)
    pull = rounded_box((0.18, 0.7, 1.1), center=(D / 2 + 0.45, L / 2 - 2.6, seam - 0.55), bevel=0.06, segments=1)
    zipper = new_object("waistbag_zipper", slider, "bag_metal", root)
    zpull = new_object("waistbag_zipper_pull", pull, "bag_accent", zipper)
    set_origin(zipper, (D / 2 + 0.1, L / 2 - 2.6, seam + 0.1))

    # передний карман и жёлтая нашивка
    new_object("waistbag_pocket", rounded_box((1.2, L * 0.62, H * 0.42), center=(D / 2 + 0.25, 0, -1.9), bevel=0.45, segments=2),
               "bag_fabric", root)
    new_object("waistbag_patch", rounded_box((0.12, 3.4, 0.9), center=(D / 2 + 0.9, 0, -1.8), bevel=0.04, segments=1),
               "bag_accent", root)

    # пояс вокруг талии (позади сумки)
    # эллипс вокруг талии: от левого торца сумки через спину к правому
    path = ellipse_path(-7.2, 0, 7.4, 8.4, 0.2, math.pi * 0.3, math.pi * 1.7, 30)
    path = [(-1.0, L / 2 - 0.6, 0.2)] + path + [(-1.0, -L / 2 + 0.6, 0.2)]
    new_object("waistbag_belt", tube(path, 0.22, 1.3, 8), "bag_strap", root)
    buckle = rounded_box((0.5, 1.6, 2.2), center=(-14.5, 0, 0.2), bevel=0.15, segments=2)
    new_object("waistbag_buckle", buckle, "bag_metal", root)

    for ob in root.children_recursive:
        box_uv(ob)

    # анимация открытия: бегунок едет по шву, затем крышка откидывается назад
    scn = bpy.context.scene
    for f, (zy, rot) in {0: (L / 2 - 2.6, 0), 12: (-L / 2 + 2.6, 0), 14: (-L / 2 + 2.6, -8), OPEN_FRAMES: (-L / 2 + 2.6, -72)}.items():
        scn.frame_set(f)
        zipper.location.y = zy
        zipper.keyframe_insert("location", index=1)
        lid.rotation_euler.y = math.radians(rot)
        lid.keyframe_insert("rotation_euler", index=1)
    return root, {"lid": lid, "zipper": zipper}


def build_backpack():
    root = bpy.data.objects.new("backpack", None)
    bpy.context.collection.objects.link(root)
    W, D, H = 14.0, 7.5, 20.0

    body = new_object("backpack_body", rounded_box((D, W, H), bevel=2.6, segments=4), "bag_fabric", root)
    new_object("backpack_inner", rounded_box((D - 1.6, W - 1.6, 0.2), center=(0, 0, H / 2 - 0.7), bevel=0.08, segments=1),
               "bag_inner", root)

    # клапан: крышка сверху + свисающая передняя часть
    fbm = rounded_box((D + 0.8, W + 0.5, 1.2), center=(0.2, 0, H / 2 + 0.05), bevel=0.55, segments=3)
    front = rounded_box((1.0, W * 0.8, 7.0), center=(D / 2 + 0.35, 0, H / 2 - 3.2), bevel=0.45, segments=3)
    flap_bm = bmesh.new()
    for part in (fbm, front):
        tmp = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp)
        part.free()
        flap_bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    flap = new_object("backpack_flap", flap_bm, "bag_fabric", root)
    patch = new_object("backpack_patch", rounded_box((0.15, 4.2, 1.2), center=(D / 2 + 0.9, 0, H / 2 - 4.4), bevel=0.05, segments=1),
                       "bag_accent", flap)
    for y in (-W * 0.25, W * 0.25):
        new_object(f"backpack_buckle_{'l' if y > 0 else 'r'}", rounded_box((0.5, 1.5, 1.5), center=(D / 2 + 0.95, y, H / 2 - 6.6),
                                                                          bevel=0.15, segments=2), "bag_metal", flap)
        new_object(f"backpack_strapf_{'l' if y > 0 else 'r'}", rounded_box((0.25, 1.1, 8.0), center=(D / 2 + 0.25, y, -1.5),
                                                                          bevel=0.08, segments=1), "bag_strap", root)
    new_object("backpack_handle", tube([(-1.5, -2.5, H / 2 + 0.7), (-1.5, -1.8, H / 2 + 2.0), (-1.5, 1.8, H / 2 + 2.0),
                                        (-1.5, 2.5, H / 2 + 0.7)], 0.5, 0.25, 6), "bag_strap", flap)
    set_origin(flap, (-D / 2 + 0.2, 0, H / 2 + 0.5))

    new_object("backpack_pocket", rounded_box((2.6, W * 0.72, H * 0.36), center=(D / 2 + 0.9, 0, -H / 2 + 4.8), bevel=1.0, segments=3),
               "bag_fabric", root)
    new_object("backpack_pocket_zip", rounded_box((0.3, W * 0.6, 0.35), center=(D / 2 + 2.25, 0, -H / 2 + 7.2), bevel=0.1, segments=1),
               "bag_metal", root)

    # лямки за спиной (в сторону владельца, -X)
    for y in (-3.6, 3.6):
        pts = [(-D / 2 + 0.4, y, H / 2 - 2.0), (-D / 2 - 1.6, y * 1.05, H / 2 - 3.5), (-D / 2 - 3.0, y * 1.15, 3.0),
               (-D / 2 - 2.6, y * 1.2, -4.0), (-D / 2 - 1.2, y * 1.25, -H / 2 + 3.5), (-D / 2 + 0.3, y * 1.25, -H / 2 + 2.0)]
        new_object(f"backpack_strap_{'l' if y > 0 else 'r'}", tube(pts, 1.25, 0.3, 8), "bag_strap", root)

    for ob in root.children_recursive:
        box_uv(ob)

    scn = bpy.context.scene
    for f, rot in {0: 0, 6: -6, OPEN_FRAMES: -118}.items():
        scn.frame_set(f)
        flap.rotation_euler.y = math.radians(rot)
        flap.keyframe_insert("rotation_euler", index=1)
    return root, {"flap": flap}


# ------------------------------------------------------------------ export ---

def bone_of(ob, bones):
    """Ближайший анимируемый предок объекта (или root)."""
    o = ob
    while o is not None:
        if o.name in bones:
            return o.name
        o = o.parent
    return "root"


def mesh_tris(ob):
    deps = bpy.context.evaluated_depsgraph_get()
    eo = ob.evaluated_get(deps)
    me = eo.to_mesh()
    me.calc_loop_triangles()
    uv = me.uv_layers.active.data
    out = []
    for tri in me.loop_triangles:
        vs = []
        for li in tri.loops:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            n = tri.normal if not tri.use_smooth else me.loops[li].normal
            vs.append((co.copy(), Vector(n).copy(), tuple(uv[li].uv)))
        out.append(vs)
    eo.to_mesh_clear()
    return out


def collect(root, anim_parts):
    """Геометрия в координатах «покоя»: по частям, в системе координат части (pivot = 0)."""
    bpy.context.scene.frame_set(0)
    bones = {o.name: o for o in anim_parts.values()}
    parts = {"root": {}}
    for name in bones:
        parts[name] = {}
    for ob in root.children_recursive:
        if ob.type != "MESH":
            continue
        bname = bone_of(ob, bones)
        bone_inv = bones[bname].matrix_world.inverted() if bname != "root" else Matrix.Identity(4)
        m = bone_inv @ ob.matrix_world
        nm = m.to_3x3().inverted().transposed()
        mat = ob.data.materials[0].name
        for tri in mesh_tris(ob):
            parts[bname].setdefault(mat, []).append([(m @ co, (nm @ n).normalized(), uv) for co, n, uv in tri])
    return parts, bones


def sample_anim(bones):
    frames = []
    for f in range(OPEN_FRAMES + 1):
        bpy.context.scene.frame_set(f)
        row = {}
        for name, ob in bones.items():
            loc = ob.matrix_world.to_translation()
            rot = ob.matrix_world.to_euler("XYZ")
            row[name] = (tuple(loc), tuple(rot))
        frames.append(row)
    bpy.context.scene.frame_set(0)
    return frames


def write_smd_ref(path, parts, bones, rest):
    names = ["root"] + list(bones)
    with open(path, "w") as f:
        f.write("version 1\nnodes\n")
        for i, n in enumerate(names):
            f.write(f'{i} "{n}" {-1 if i == 0 else 0}\n')
        f.write("end\nskeleton\ntime 0\n")
        f.write("0 0 0 0 0 0 0\n")
        for i, n in enumerate(names[1:], 1):
            (x, y, z), (rx, ry, rz) = rest[n]
            f.write(f"{i} {x:.6f} {y:.6f} {z:.6f} {rx:.6f} {ry:.6f} {rz:.6f}\n")
        f.write("end\ntriangles\n")
        for bi, bname in enumerate(names):
            bm = Matrix.Identity(4)
            if bname != "root":
                (x, y, z), (rx, ry, rz) = rest[bname]
                from mathutils import Euler
                bm = Matrix.Translation((x, y, z)) @ Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4()
            nm = bm.to_3x3()
            for mat, tris in parts[bname].items():
                for tri in tris:
                    f.write(mat + "\n")
                    for co, n, (u, v) in tri:
                        wc = bm @ co
                        wn = (nm @ n).normalized()
                        f.write(f"{bi} {wc.x:.6f} {wc.y:.6f} {wc.z:.6f} {wn.x:.6f} {wn.y:.6f} {wn.z:.6f} {u:.6f} {v:.6f} 1 {bi} 1.0\n")
        f.write("end\n")


def write_smd_anim(path, bones, frames):
    names = ["root"] + list(bones)
    with open(path, "w") as f:
        f.write("version 1\nnodes\n")
        for i, n in enumerate(names):
            f.write(f'{i} "{n}" {-1 if i == 0 else 0}\n')
        f.write("end\nskeleton\n")
        for t, row in enumerate(frames):
            f.write(f"time {t}\n0 0 0 0 0 0 0\n")
            for i, n in enumerate(names[1:], 1):
                (x, y, z), (rx, ry, rz) = row[n]
                f.write(f"{i} {x:.6f} {y:.6f} {z:.6f} {rx:.6f} {ry:.6f} {rz:.6f}\n")
        f.write("end\n")


def write_smd_phys(path, parts):
    pts = [co for part in parts.values() for tris in part.values() for tri in tris for co, _, _ in tri]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = [Vector((x, y, z)) for x in (mn.x, mx.x) for y in (mn.y, mx.y) for z in (mn.z, mx.z)]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    with open(path, "w") as f:
        f.write('version 1\nnodes\n0 "root" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\ntriangles\n')
        for q in quads:
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                f.write("phys\n")
                for i in tri:
                    p = c[i]
                    f.write(f"0 {p.x:.4f} {p.y:.4f} {p.z:.4f} 0 0 1 0 0 1 0 1.0\n")
        f.write("end\n")


def write_qc(name, mass):
    with open(os.path.join(SRC, name + ".qc"), "w") as f:
        f.write(f'''$modelname "nyrp/bags/{name}.mdl"
$body body "{name}_ref.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$illumposition 0 0 0
$sequence idle "{name}_idle.smd" fps {FPS} loop
$sequence open "{name}_open.smd" fps {FPS}
$sequence close "{name}_close.smd" fps {FPS}
$collisionmodel "{name}_phys.smd"
{{
	$mass {mass}
}}
''')


def pack_verts(verts):
    """Вершины -> base64 строка int16: pos*500, normal*32767, uv*1000 (8 значений на вершину)."""
    import base64
    out = bytearray()
    for co, n, (u, v) in verts:
        vals = (co.x * 500, co.y * 500, co.z * 500, n.x * 32767, n.y * 32767, n.z * 32767, u * 1000, (1 - v) * 1000)
        out += struct.pack("<8h", *(max(-32768, min(32767, int(round(x)))) for x in vals))
    return base64.b64encode(bytes(out)).decode()


def lua_num(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def write_anim_lua(path, models):
    """Пути к .mdl частей и ключи анимации открытия (pos + Angle(pitch, yaw, roll) относительно модели)."""
    with open(path, "w") as f:
        f.write("-- Сгенерировано tools/models/build_bags.py — не редактировать вручную.\n")
        f.write("-- Части сумок — отдельные .mdl, анимация открытия: кадры {x, y, z, pitch, yaw, roll} на часть.\n")
        f.write("NYRP.BagModels = {\n")
        for name, (parts, bones, frames) in models.items():
            f.write(f"\t{name} = {{\n\t\tfps = {FPS},\n\t\tparts = {{\n")
            for bname in parts:
                short = bname.replace(name + "_", "")
                f.write(f'\t\t\t{short} = "models/nyrp/bags/{name}_{short}.mdl",\n')
            f.write("\t\t},\n\t\tanim = {\n")
            for bname in bones:
                f.write(f"\t\t\t{bname.replace(name + '_', '')} = {{\n")
                for row in frames:
                    (x, y, z), (rx, ry, rz) = row[bname]
                    vals = (x, y, z, math.degrees(ry), math.degrees(rz), math.degrees(rx))
                    f.write("\t\t\t\t{" + ", ".join(lua_num(v) for v in vals) + "},\n")
                f.write("\t\t\t},\n")
            f.write("\t\t},\n\t},\n")
        f.write("}\n")
    print("wrote", os.path.relpath(path, ROOT))


def compile_parts(name, parts):
    import mdlc
    out = os.path.join(GM, "content", "models", "nyrp", "bags")
    for bname, mats in parts.items():
        bname = bname.replace(name + "_", "")
        tris = {m: [[(tuple(co), tuple(n), uv) for co, n, uv in tri] for tri in tl] for m, tl in mats.items()}
        mdlc.compile_model(out, f"{name}_{bname}", f"nyrp/bags/{name}_{bname}.mdl", tris, "models/nyrp/bags", "cloth", 1.0)
        write_part_smd(os.path.join(SRC, f"{name}_{bname}.smd"), mats)
        with open(os.path.join(SRC, f"{name}_{bname}.qc"), "w") as f:
            f.write(f'$modelname "nyrp/bags/{name}_{bname}.mdl"\n$body body "{name}_{bname}.smd"\n'
                    f'$cdmaterials "models/nyrp/bags/"\n$surfaceprop "cloth"\n$sequence idle "{name}_{bname}.smd" fps 30\n'
                    f'$collisionmodel "{name}_phys.smd" {{ $mass 1 }}\n')
    print("compiled", name, list(parts))


def write_part_smd(path, mats):
    with open(path, "w") as f:
        f.write('version 1\nnodes\n0 "root" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\ntriangles\n')
        for mat, tris in mats.items():
            for tri in tris:
                f.write(mat + "\n")
                for co, n, (u, v) in tri:
                    f.write(f"0 {co.x:.5f} {co.y:.5f} {co.z:.5f} {n.x:.5f} {n.y:.5f} {n.z:.5f} {u:.5f} {v:.5f} 1 0 1.0\n")
        f.write("end\n")


def write_lua(path, models):
    with open(path, "w") as f:
        f.write("-- Сгенерировано tools/models/build_bags.py — не редактировать вручную.\n")
        f.write("-- Геометрия частей: base64 от int16 {x,y,z (*500), nx,ny,nz (*32767), u,v (*1000)} на вершину,\n")
        f.write("-- координаты относительно pivot части. Декодирует NYRP.DecodeMesh (cl_meshes.lua).\n")
        f.write("NYRP.BagMeshes = {\n")
        for name, (parts, bones, frames) in models.items():
            f.write(f"\t{name} = {{\n\t\tfps = {FPS},\n\t\tparts = {{\n")
            for bname, mats in parts.items():
                f.write(f"\t\t\t{bname} = {{\n")
                for mat, tris in mats.items():
                    verts = [v for tri in tris for v in tri]
                    f.write(f'\t\t\t\t["models/nyrp/bags/{mat}"] = "{pack_verts(verts)}",\n')
                f.write("\t\t\t},\n")
            f.write("\t\t},\n\t\tanim = {\n")
            for bname in bones:
                f.write(f"\t\t\t{bname} = {{")
                for row in frames:
                    (x, y, z), (rx, ry, rz) = row[bname]
                    f.write("{" + ",".join(lua_num(v) for v in (x, y, z, math.degrees(rx), math.degrees(ry), math.degrees(rz))) + "},")
                f.write("},\n")
            f.write("\t\t},\n\t},\n")
        f.write("}\n")
    print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


# ------------------------------------------------------------- textures ---

def write_vtf(path, rgb_rows, size):
    """VTF 7.2, BGR888, полный набор мипов, без low-res превью."""
    def mip(img, s):
        if s == size:
            return img
        k = size // s
        out = []
        for y in range(s):
            for x in range(s):
                acc = [0, 0, 0]
                for yy in range(k):
                    for xx in range(k):
                        p = img[(y * k + yy) * size + x * k + xx]
                        acc[0] += p[0]; acc[1] += p[1]; acc[2] += p[2]
                out.append(tuple(a // (k * k) for a in acc))
        return out

    mips = []
    s = size
    while s >= 1:
        mips.append(s)
        s //= 2
    header = struct.pack("<4s2II", b"VTF\0", 7, 2, 80)
    header += struct.pack("<HHIHH4x3f4xfIBIBBH", size, size, 0x0010, 1, 0,  # TEXTUREFLAGS_ANISOTROPIC
                          0.2, 0.2, 0.2, 1.0, 3, len(mips), 0xFFFFFFFF, 0, 0, 1)
    header += b"\0" * (80 - len(header))
    data = b""
    for s in reversed(mips):  # от маленького к большому
        img = mip(rgb_rows, s)
        data += b"".join(struct.pack("BBB", p[2], p[1], p[0]) for p in img)
    with open(path, "wb") as f:
        f.write(header + data)


def build_textures():
    import random
    os.makedirs(MATDIR, exist_ok=True)
    size = 64
    for name, (col, noise, weave) in MATERIALS.items():
        rng = random.Random(name)
        img = []
        for y in range(size):
            for x in range(size):
                k = rng.randint(-noise, noise)
                if weave:
                    k += 7 if ((x // 2) + (y // 2)) % 2 == 0 else -5
                    if y % 16 == 0 and x % 4 < 2:
                        k += 14  # строчка
                img.append(tuple(max(0, min(255, c + k)) for c in col))
        write_vtf(os.path.join(MATDIR, name + ".vtf"), img, size)
        with open(os.path.join(MATDIR, name + ".vmt"), "w") as f:
            extra = '\t"$phong" "1"\n\t"$phongexponent" "30"\n\t"$phongboost" "2"\n\t"$phongfresnelranges" "[0.5 0.8 1]"\n' if name == "bag_metal" else ""
            f.write(f'"VertexLitGeneric"\n{{\n\t"$basetexture" "models/nyrp/bags/{name}"\n{extra}}}\n')
    print("textures ok")


def render_preview(path):
    from PIL import Image
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"  # EEVEE требует GPU/EGL
    scn.cycles.samples = 48
    scn.cycles.device = "CPU"
    scn.render.resolution_x, scn.render.resolution_y = 960, 640
    scn.view_settings.exposure = 0.0
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.04, 0.08, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scn.world = world
    target = bpy.data.objects.new("target", None)
    bpy.context.collection.objects.link(target)
    target.location = (0, 0, 2)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (95, -55, 45)
    con = cam.constraints.new("TRACK_TO")
    con.target = target
    scn.camera = cam
    for loc, energy in (((60, -60, 80), 900000), ((-40, 60, 40), 250000), ((80, 40, -20), 120000)):
        ld = bpy.data.lights.new("l", "POINT")
        ld.energy = energy
        ld.shadow_soft_size = 10
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        bpy.context.collection.objects.link(lo)
    shots = []
    for f in (0, OPEN_FRAMES):
        scn.frame_set(f)
        scn.render.filepath = path.replace(".png", f"_{f}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(Image.open(scn.render.filepath))
    out = Image.new("RGB", (1920, 640))
    out.paste(shots[0], (0, 0))
    out.paste(shots[1], (960, 0))
    out.save(path)
    for f in (0, OPEN_FRAMES):
        os.remove(path.replace(".png", f"_{f}.png"))
    scn.frame_set(0)
    print("preview", os.path.relpath(path, ROOT))


def main():
    os.makedirs(SRC, exist_ok=True)
    reset_scene()
    models = {}
    for name, builder, mass, offset in (("waistbag", build_waistbag, 2, (0, -14, 0)), ("backpack", build_backpack, 5, (0, 14, 0))):
        root, anim = builder()
        parts, bones = collect(root, anim)
        frames = sample_anim(bones)
        rest = frames[0]
        write_smd_ref(os.path.join(SRC, f"{name}_ref.smd"), parts, bones, rest)
        write_smd_anim(os.path.join(SRC, f"{name}_idle.smd"), bones, [frames[0]])
        write_smd_anim(os.path.join(SRC, f"{name}_open.smd"), bones, frames)
        write_smd_anim(os.path.join(SRC, f"{name}_close.smd"), bones, frames[::-1])
        write_smd_phys(os.path.join(SRC, f"{name}_phys.smd"), parts)
        write_qc(name, mass)
        models[name] = (parts, bones, frames)
        compile_parts(name, parts)
        root.location = offset
        tri = sum(len(t) for p in parts.values() for t in p.values())
        print(name, "triangles:", tri)
    build_textures()
    os.makedirs(os.path.join(GM, "gamemode", "modules", "bags"), exist_ok=True)
    write_anim_lua(os.path.join(GM, "gamemode", "modules", "bags", "sh_bag_models.lua"), models)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "tools", "models", "bags.blend"))
    render_preview(os.path.join(ROOT, "branding", "bags_preview.png"))


if __name__ == "__main__":
    main()
