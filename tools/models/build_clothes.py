"""Модели предметов одежды New-York Roleplay (Blender / bpy).

Запуск:  python3 tools/models/build_clothes.py
Использует помощники из build_bags.py. Результат:
  tools/models/clothes.blend, tools/models/src/clothes/*.smd|*.qc
  content/materials/models/nyrp/clothes/*.vtf|*.vmt
  gamemode/modules/items/cl_item_meshes.lua
  branding/clothes_preview.png
"""
import math
import os

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector

import build_bags as bb

ROOT = bb.ROOT
SRC = os.path.join(ROOT, "tools", "models", "src", "clothes")
MATDIR = os.path.join(bb.GM, "content", "materials", "models", "nyrp", "clothes")

MATS = {
    "cl_navy": ((30, 40, 70), 6, True),
    "cl_white": ((214, 214, 218), 8, True),
    "cl_black": ((26, 26, 28), 5, True),
    "cl_leather": ((92, 58, 38), 7, False),
    "cl_denim": ((52, 76, 116), 10, True),
    "cl_red": ((160, 36, 40), 6, True),
    "cl_maskblue": ((150, 196, 220), 5, True),
    "cl_lens": ((16, 18, 24), 2, False),
    "cl_metal": ((160, 160, 165), 6, False),
    "cl_accent": ((247, 198, 0), 5, True),
    "cl_card": ((236, 238, 242), 3, False),
    "cl_photo": ((120, 128, 140), 4, False),
}


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name, (col, _, _) in MATS.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*((c / 255) ** 2.2 for c in col), 1)
        bsdf.inputs["Roughness"].default_value = 0.15 if name in ("cl_lens", "cl_metal") else 0.8
        if name == "cl_metal":
            bsdf.inputs["Metallic"].default_value = 0.9


def obj(name, bm, mat, root, matrix=None):
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=list(bm.verts))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials[mat])
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = root
    return ob


def sphere(r, center=(0, 0, 0), seg=20, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))
    return bm


def cylinder(r, depth, seg=24):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth)
    return bm


def ring_path(cx, cy, cz, r, axis="x", n=20, a0=0.0, a1=2 * math.pi):
    pts = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        if axis == "x":
            pts.append((cx, cy + r * math.cos(a), cz + r * math.sin(a)))
        else:
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), cz))
    return pts


def M(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    from mathutils import Euler
    return (Matrix.Translation(loc) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
            @ Matrix.Diagonal((*scale, 1)))


# ------------------------------------------------------------------ items ---

def cap(root):
    dome = sphere(4.0, seg=24, rings=12)
    bb.cut(dome, 0.0, True)
    obj("cap_dome", dome, "cl_navy", root, M((0, 0, 0.3), scale=(1, 1, 0.78)))
    brim = cylinder(3.6, 0.3, 28)
    obj("cap_brim", brim, "cl_navy", root, M((3.4, 0, 0.45), scale=(1.0, 1.05, 1)))
    obj("cap_button", sphere(0.45, seg=10, rings=6), "cl_navy", root, M((0, 0, 3.45)))
    obj("cap_logo", bb.rounded_box((0.2, 2.0, 1.2), bevel=0.06, segments=1), "cl_accent", root,
        M((3.35, 0, 1.6), rot=(0, -38, 0)))


def sunglasses(root):
    for y in (-1.6, 1.6):
        obj(f"glasses_lens_{y}", cylinder(1.25, 0.18, 24), "cl_lens", root, M((0, y, 1.3), rot=(0, 90, 0), scale=(1, 1.15, 1)))
        obj(f"glasses_rim_{y}", bb.tube(ring_path(0, y, 1.3, 1.3, n=24), 0.14, 0.14, 6), "cl_black", root,
            M((0, 0, 0), scale=(1, 1, 1)))
        obj(f"glasses_temple_{y}", bb.tube([(0, y * 1.75, 1.75), (-1.0, y * 1.85, 1.8), (-4.8, y * 1.85, 1.7), (-5.5, y * 1.8, 1.1)],
                                            0.12, 0.2, 6), "cl_black", root)
    obj("glasses_bridge", bb.tube([(0, -0.4, 1.7), (0.05, 0, 1.95), (0, 0.4, 1.7)], 0.12, 0.12, 6), "cl_black", root)


def mask(root):
    bm = bmesh.new()
    nx, ny = 14, 8
    W, H = 6.0, 3.6
    verts = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            y = -W / 2 + W * i / nx
            z = -H / 2 + H * j / ny
            x = -0.11 * y * y - 0.05 * z * z + (0.12 if j % 3 == 1 else 0)  # изгиб + складки
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.15)
    obj("mask_body", bm, "cl_maskblue", root, M((0, 0, 0.6), rot=(0, 80, 0)))
    for y in (-1, 1):
        pts = [(-0.2 - 0.6 * math.sin(a) * 1.5, y * (3.0 + 1.4 * math.sin(a)), 0.25 + 0.0 * a) for a in
               [math.pi * k / 10 for k in range(11)]]
        obj(f"mask_loop_{y}", bb.tube(pts, 0.08, 0.08, 5), "cl_white", root)
    obj("mask_wire", bb.rounded_box((0.15, 2.2, 0.15), bevel=0.05, segments=1), "cl_metal", root, M((0.2, 0, 2.3)))


def tshirt(root):
    obj("tshirt_body", bb.rounded_box((7.0, 8.0, 1.2), bevel=0.45, segments=3), "cl_white", root, M((0, 0, 0.6)))
    obj("tshirt_fold", bb.rounded_box((0.4, 8.1, 0.25), bevel=0.1, segments=1), "cl_white", root, M((-1.2, 0, 1.25)))
    obj("tshirt_collar", bb.tube(ring_path(2.6, 0, 1.25, 1.3, axis="z", n=14, a0=math.pi * 0.5, a1=math.pi * 1.5), 0.25, 0.18, 6),
        "cl_white", root)
    obj("tshirt_print", bb.rounded_box((2.2, 2.4, 0.06), bevel=0.04, segments=1), "cl_accent", root, M((-0.3, 0, 1.24)))


def jacket(root):
    obj("jacket_body", bb.rounded_box((8.0, 9.0, 2.0), bevel=0.7, segments=3), "cl_leather", root, M((0, 0, 1.0)))
    obj("jacket_collar", bb.tube(ring_path(3.0, 0, 2.05, 1.8, axis="z", n=16, a0=math.pi * 0.5, a1=math.pi * 1.5), 0.55, 0.35, 8),
        "cl_leather", root)
    obj("jacket_zip", bb.rounded_box((5.4, 0.22, 0.1), bevel=0.04, segments=1), "cl_metal", root, M((-0.5, 0, 2.02)))
    for y in (-2.8, 2.8):
        obj(f"jacket_pocket_{y}", bb.rounded_box((1.8, 0.2, 0.08), bevel=0.04, segments=1), "cl_black", root, M((-1.8, y, 2.02), rot=(0, 0, 20 * (1 if y > 0 else -1))))


def gloves(root):
    for k, y in enumerate((-2.3, 2.3)):
        sx = 1 if k == 0 else -1
        parts = bmesh.new()
        tmp = bpy.data.meshes.new("t")
        for bmx in (bb.rounded_box((3.6, 3.0, 0.9), bevel=0.4, segments=2),
                    *[bb.rounded_box((2.2 - abs(i - 1.5) * 0.25, 0.62, 0.7), center=(2.8 - abs(i - 1.5) * 0.12, -1.05 + i * 0.7, 0), bevel=0.28, segments=2) for i in range(4)],
                    bb.rounded_box((1.8, 0.7, 0.7), center=(0.9, 1.9 * sx, 0), bevel=0.28, segments=2),
                    bb.rounded_box((1.6, 3.1, 1.0), center=(-2.3, 0, 0), bevel=0.35, segments=2)):
            bmx.to_mesh(tmp)
            bmx.free()
            parts.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        obj(f"glove_{k}", parts, "cl_black", root, M((0, y, 0.5), rot=(0, 0, 8 * sx)))


def jeans(root):
    obj("jeans_body", bb.rounded_box((7.0, 9.0, 1.6), bevel=0.5, segments=3), "cl_denim", root, M((0, 0, 0.8)))
    obj("jeans_waist", bb.rounded_box((1.2, 9.1, 1.7), bevel=0.3, segments=2), "cl_denim", root, M((3.2, 0, 0.85)))
    obj("jeans_button", cylinder(0.3, 0.15, 12), "cl_metal", root, M((3.3, 0, 1.75)))
    for y in (-2.2, 2.2):
        obj(f"jeans_pocket_{y}", bb.tube([(2.6, y - 1.0, 1.62), (1.6, y - 0.9, 1.62), (1.2, y, 1.62), (1.6, y + 0.9, 1.62), (2.6, y + 1.0, 1.62)],
                                          0.06, 0.04, 4), "cl_accent", root)


def sneakers(root):
    for k, y in enumerate((-2.0, 2.0)):
        ob = M((0, y, 0), rot=(0, 0, -6 if k == 0 else 6))
        obj(f"sneaker_sole_{k}", bb.rounded_box((9.0, 3.3, 0.8), bevel=0.35, segments=2), "cl_white", root, ob @ M((0, 0, 0.4)))
        obj(f"sneaker_upper_{k}", bb.rounded_box((7.2, 3.0, 2.4), bevel=0.95, segments=3), "cl_red", root, ob @ M((-0.6, 0, 1.8)))
        obj(f"sneaker_toe_{k}", bb.rounded_box((2.6, 3.0, 1.4), bevel=0.6, segments=3), "cl_white", root, ob @ M((3.0, 0, 1.15)))
        obj(f"sneaker_collar_{k}", bb.rounded_box((2.6, 2.6, 0.5), bevel=0.2, segments=2), "cl_black", root, ob @ M((-2.6, 0, 3.0)))
        for i in range(4):
            obj(f"sneaker_lace_{k}_{i}", bb.rounded_box((0.25, 1.9, 0.15), bevel=0.06, segments=1), "cl_white", root,
                ob @ M((1.4 - i * 0.8, 0, 2.95 - i * 0.03)))


def idcard(root):
    obj("card_body", bb.rounded_box((5.4, 3.4, 0.08), bevel=0.03, segments=1), "cl_card", root, M((0, 0, 0.04)))
    obj("card_header", bb.rounded_box((5.0, 0.7, 0.02), bevel=0.005, segments=1), "cl_navy", root, M((0, 1.15, 0.09)))
    obj("card_stripe", bb.rounded_box((5.0, 0.12, 0.02), bevel=0.005, segments=1), "cl_accent", root, M((0, 0.72, 0.09)))
    obj("card_photo", bb.rounded_box((1.3, 1.6, 0.02), bevel=0.005, segments=1), "cl_photo", root, M((-1.75, -0.35, 0.09)))
    for i in range(4):
        obj(f"card_line_{i}", bb.rounded_box((2.2 - i * 0.3, 0.12, 0.02), bevel=0.005, segments=1), "cl_photo", root,
            M((0.45 - i * 0.15, 0.25 - i * 0.38, 0.09)))


ITEMS = {
    "cap": cap, "sunglasses": sunglasses, "mask": mask, "tshirt": tshirt,
    "jacket": jacket, "gloves": gloves, "jeans": jeans, "sneakers": sneakers, "idcard": idcard,
}


# ------------------------------------------------------------------ export ---

def collect(root):
    out = {}
    for ob in root.children:
        m = ob.matrix_world
        nm = m.to_3x3().inverted().transposed()
        mat = ob.data.materials[0].name
        for tri in bb.mesh_tris(ob):
            out.setdefault(mat, []).append([(m @ co, (nm @ n).normalized(), uv) for co, n, uv in tri])
    return out


def write_smd(path, mats):
    with open(path, "w") as f:
        f.write('version 1\nnodes\n0 "root" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\ntriangles\n')
        for mat, tris in mats.items():
            for tri in tris:
                f.write(mat + "\n")
                for co, n, (u, v) in tri:
                    f.write(f"0 {co.x:.5f} {co.y:.5f} {co.z:.5f} {n.x:.5f} {n.y:.5f} {n.z:.5f} {u:.5f} {v:.5f} 1 0 1.0\n")
        f.write("end\n")


def write_lua(path, items):
    with open(path, "w") as f:
        f.write("-- Сгенерировано tools/models/build_clothes.py — не редактировать вручную.\n")
        f.write("-- Вершины упакованы как в cl_bag_meshes.lua (base64 int16), декодирует NYRP.DecodeMesh.\n")
        f.write("NYRP.ItemMeshes = NYRP.ItemMeshes or {}\n")
        for name, mats in items.items():
            pts = [co for tris in mats.values() for tri in tris for co, _, _ in tri]
            mn = [min(p[i] for p in pts) for i in range(3)]
            mx = [max(p[i] for p in pts) for i in range(3)]
            f.write(f"NYRP.ItemMeshes.{name} = {{\n")
            f.write(f"\tmins = Vector({bb.lua_num(mn[0])}, {bb.lua_num(mn[1])}, {bb.lua_num(mn[2])}),\n")
            f.write(f"\tmaxs = Vector({bb.lua_num(mx[0])}, {bb.lua_num(mx[1])}, {bb.lua_num(mx[2])}),\n")
            f.write("\tparts = {\n")
            for mat, tris in mats.items():
                verts = [v for tri in tris for v in tri]
                f.write(f'\t\t["models/nyrp/clothes/{mat}"] = "{bb.pack_verts(verts)}",\n')
            f.write("\t},\n}\n")
    print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


def textures():
    import random
    os.makedirs(MATDIR, exist_ok=True)
    size = 64
    for name, (col, noise, weave) in MATS.items():
        rng = random.Random(name)
        img = []
        for y in range(size):
            for x in range(size):
                k = rng.randint(-noise, noise)
                if weave:
                    k += 5 if ((x // 2) + (y // 2)) % 2 == 0 else -4
                img.append(tuple(max(0, min(255, c + k)) for c in col))
        bb.write_vtf(os.path.join(MATDIR, name + ".vtf"), img, size)
        extra = ""
        if name in ("cl_lens", "cl_metal", "cl_leather"):
            extra = '\t"$phong" "1"\n\t"$phongexponent" "40"\n\t"$phongboost" "3"\n\t"$phongfresnelranges" "[0.4 0.8 1]"\n'
        with open(os.path.join(MATDIR, name + ".vmt"), "w") as f:
            f.write(f'"VertexLitGeneric"\n{{\n\t"$basetexture" "models/nyrp/clothes/{name}"\n{extra}}}\n')


def preview(path):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 40
    scn.cycles.device = "CPU"
    scn.render.resolution_x, scn.render.resolution_y = 1600, 800
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.04, 0.08, 1)
    scn.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 70
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (40, 15, 55)
    tgt = bpy.data.objects.new("t", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 15, 0)
    c = cam.constraints.new("TRACK_TO")
    c.target = tgt
    scn.camera = cam
    for loc, e in (((40, -20, 60), 900000), ((-30, 50, 40), 300000)):
        ld = bpy.data.lights.new("l", "POINT")
        ld.energy = e
        ld.shadow_soft_size = 10
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        bpy.context.collection.objects.link(lo)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(SRC, exist_ok=True)
    setup()
    items = {}
    for i, (name, fn) in enumerate(ITEMS.items()):
        root = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(root)
        fn(root)
        for ob in root.children:
            bb.box_uv(ob, 0.2)
        bpy.context.view_layer.update()
        items[name] = collect(root)
        write_smd(os.path.join(SRC, f"{name}.smd"), items[name])
        with open(os.path.join(SRC, f"{name}.qc"), "w") as f:
            f.write(f'$modelname "nyrp/clothes/{name}.mdl"\n$body body "{name}.smd"\n$staticprop\n'
                    f'$cdmaterials "models/nyrp/clothes/"\n$surfaceprop "cloth"\n$sequence idle "{name}.smd" fps 30\n'
                    f'$collisionmodel "{name}.smd" {{ $concave $mass 1 }}\n')
        root.location = ((i % 3) * 16 - 16, (i // 3) * 14, 0)
        print(name, sum(len(t) for t in items[name].values()), "tris")
    textures()
    import mdlc
    for name, mats in items.items():
        tris = {m: [[(tuple(co), tuple(n), uv) for co, n, uv in tri] for tri in tl] for m, tl in mats.items()}
        mdlc.compile_model(os.path.join(bb.GM, "content", "models", "nyrp", "clothes"), name, f"nyrp/clothes/{name}.mdl",
                           tris, "models/nyrp/clothes", "plastic" if name == "idcard" else "cloth", 0.5)
    print("compiled", list(items))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "tools", "models", "clothes.blend"))
    preview(os.path.join(ROOT, "branding", "clothes_preview.png"))


if __name__ == "__main__":
    main()
