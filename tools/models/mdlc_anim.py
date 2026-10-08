"""mdlc_anim — компилятор анимированных моделей Source MDL v48 (много костей, последовательности).

Нужен для вьюмодели рук с сумкой: кости c_arms (руки игрока прицепляются бонмерджем) + кости сумки,
сетка сумки жёстко привязана к своим костям, анимации кодируются ANIMROT/ANIMPOS (RLE-потоки short).

compile_animated(out_dir, name, model_path, bones, meshes, sequences, cdmaterials)
  bones:     [{name, parent, pos(3), quat(4)}]  — позa покоя (локально к родителю)
  meshes:    {material: [(tri: [(pos, normal, uv, bone)] x3 (против часовой))]}  — в пространстве модели (поза покоя)
  sequences: [{name, fps, loop, frames: [[(pos, quat) на кость]]}]
"""
import math
import os
import struct
import zlib

import numpy as np

import mdlc
from mdlc import Buf

USED_ALL = 0x0007FF00  # BONE_USED_BY_* — кость вычисляется всегда (нужно для бонмерджа)


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def quat_angles(q):
    """Quaternion -> RadianEuler (обратно AngleQuaternion из Source: R = Rz(z)·Ry(y)·Rx(x))."""
    m = quat_to_mat(q)
    sy = -m[2, 0]
    y = math.asin(max(-1.0, min(1.0, sy)))
    if abs(sy) < 0.99999:
        x = math.atan2(m[2, 1], m[2, 2])
        z = math.atan2(m[1, 0], m[0, 0])
    else:
        x = math.atan2(-m[1, 2], m[1, 1])
        z = 0.0
    return (x, y, z)


def mat4(pos, quat):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(quat)
    m[:3, 3] = pos
    return m


def world_matrices(bones, locals_):
    w = []
    for i, b in enumerate(bones):
        m = mat4(*locals_[i])
        w.append(m if b["parent"] < 0 else w[b["parent"]] @ m)
    return w


def _unwrap(seq, ref):
    out, prev = [], ref
    for a in seq:
        while a - prev > math.pi:
            a -= 2 * math.pi
        while a - prev < -math.pi:
            a += 2 * math.pi
        out.append(a)
        prev = a
    return out


def _eulers(frames, bi, ref):
    """Эйлеры кости по кадрам: непрерывная ветвь (учитываем вторую ветвь x+pi, pi-y, z+pi)."""
    out, prev = [], np.array(ref, float)
    for f in frames:
        x, y, z = quat_angles(f[bi][1])
        best = None
        for c in ((x, y, z), (x + math.pi, math.pi - y, z + math.pi)):
            c = np.array([prev[j] + (c[j] - prev[j] + math.pi) % (2 * math.pi) - math.pi for j in range(3)])
            if best is None or np.abs(c - prev).sum() < np.abs(best - prev).sum():
                best = c
        out.append(best)
        prev = best
    return np.array(out)


def _rle(values):
    """Поток mstudioanimvalue_t: блоки по 255 кадров, без сжатия повторов (valid == total)."""
    out = bytearray()
    i = 0
    while i < len(values):
        chunk = values[i:i + 255]
        out += struct.pack("<BB", len(chunk), len(chunk))
        out += struct.pack(f"<{len(chunk)}h", *chunk)
        i += len(chunk)
    return bytes(out)


def _encode_anim(bones, frames, scales):
    """Цепочка mstudioanim_t для одной анимации."""
    blocks = []
    nf = len(frames)
    for bi, b in enumerate(bones):
        pos = np.array([f[bi][0] for f in frames])
        eul = _eulers(frames, bi, b["rot"])
        dpos = pos - np.array(b["pos"])
        drot = eul - np.array(b["rot"])
        moving_pos = np.abs(dpos).max() > 1e-4
        moving_rot = np.abs(drot).max() > 1e-5
        if not moving_pos and not moving_rot:
            continue
        flags = 0
        data = bytearray()
        ptrs = []
        if moving_rot:
            flags |= 0x08
            ptrs.append(("rot", drot, scales[bi]["rotscale"]))
        if moving_pos:
            flags |= 0x04
            ptrs.append(("pos", dpos, scales[bi]["posscale"]))
        header_len = 4 + 6 * len(ptrs)
        streams = []
        for kind, delta, scale in ptrs:
            offs = []
            for j in range(3):
                q = [int(round(v / scale[j])) if scale[j] > 0 else 0 for v in delta[:, j]]
                q = [max(-32767, min(32767, v)) for v in q]
                if all(v == 0 for v in q):
                    offs.append(None)
                else:
                    offs.append(_rle(q))
            streams.append(offs)
        # раскладка: header, valueptr(rot), valueptr(pos), затем потоки
        body = bytearray()
        ptr_bytes = []
        cursor = header_len
        stream_pos = []
        for pi, offs in enumerate(streams):
            row = []
            for j in range(3):
                if offs[j] is None:
                    row.append(0)
                else:
                    ptr_start = 4 + 6 * pi
                    row.append(cursor + len(body) - ptr_start)
                    body += offs[j]
            stream_pos.append(row)
        for row in stream_pos:
            ptr_bytes.append(struct.pack("<3h", *row))
        block = struct.pack("<BBh", bi, flags, 0) + b"".join(ptr_bytes) + body
        if len(block) % 2:
            block += b"\0"
        blocks.append(bytearray(block))
    if not blocks:  # анимация без движения: одна кость с RAWROT2 = покой
        b = bones[0]
        q = b["quat"]
        x, y, z, w = q
        qq = (int((x * 1048576.5) + 1048576) & 0x1FFFFF) | ((int((y * 1048576.5) + 1048576) & 0x1FFFFF) << 21) | \
             ((int((z * 1048576.5) + 1048576) & 0x1FFFFF) << 42) | ((1 if w < 0 else 0) << 63)
        blocks.append(bytearray(struct.pack("<BBhQ", 0, 0x20, 0, qq)))
    for i, bl in enumerate(blocks[:-1]):
        struct.pack_into("<h", bl, 2, len(bl))
    return b"".join(blocks)


def compile_animated(out_dir, name, model_path, bones, meshes, sequences, cdmaterials, surfaceprop="cloth"):
    nb = len(bones)
    # rot/rotscale/posscale по всем последовательностям
    for b in bones:
        b["rot"] = quat_angles(b["quat"])
    scales = []
    for bi, b in enumerate(bones):
        mp, mr = [1e-6] * 3, [1e-7] * 3
        for s in sequences:
            eul = _eulers(s["frames"], bi, b["rot"])
            for fi, f in enumerate(s["frames"]):
                p = f[bi][0]
                for j in range(3):
                    mp[j] = max(mp[j], abs(p[j] - b["pos"][j]))
                    mr[j] = max(mr[j], abs(eul[fi][j] - b["rot"][j]) * 1.01 + 1e-4)
        scales.append({"posscale": [v / 32000 for v in mp], "rotscale": [v / 32000 for v in mr]})

    rest_world = world_matrices(bones, [(b["pos"], b["quat"]) for b in bones])
    # меши: материалы -> вершины/индексы (+ кость на вершину)
    mesh_list = []
    for mat, tris in meshes.items():
        verts, index, lookup = [], [], {}
        for tri in tris:
            tri = [tri[0], tri[2], tri[1]]
            tan = mdlc._tangent(tri[0][0], tri[1][0], tri[2][0], tri[0][2], tri[1][2], tri[2][2], tri[0][1])
            for p, n, uv, bone in tri:
                key = (tuple(round(c, 4) for c in p), tuple(round(c, 3) for c in n), (round(uv[0], 4), round(uv[1], 4)), bone)
                if key not in lookup:
                    lookup[key] = len(verts)
                    verts.append((tuple(p), tuple(n), (uv[0], uv[1]), tan, bone))
                index.append(lookup[key])
        mesh_list.append((mat, verts, index))
    allp = [v[0] for _, vs, _ in mesh_list for v in vs]
    mn = tuple(min(p[i] for p in allp) for i in range(3))
    mx = tuple(max(p[i] for p in allp) for i in range(3))
    checksum = zlib.crc32(repr((model_path, nb, len(allp), [s["name"] for s in sequences])).encode()) & 0x7FFFFFFF

    b = Buf()
    b.put("4si i", b"IDST", 48, checksum)
    b.b += model_path.encode()[:63].ljust(64, b"\0")
    b.put("i", 0)
    b.put("3f", 0, 0, 0)
    b.put("3f", *[(mn[i] + mx[i]) / 2 for i in range(3)])
    b.put("3f", -40, -40, -40)
    b.put("3f", 40, 40, 40)
    b.put("3f", 0, 0, 0)
    b.put("3f", 0, 0, 0)
    b.put("i", 0x1)
    H = b.tell()
    b.b += b"\0" * (408 - H)
    fields = ("numbones boneindex numbonecontrollers bonecontrollerindex numhitboxsets hitboxsetindex "
              "numlocalanim localanimindex numlocalseq localseqindex activitylistversion eventsindexed "
              "numtextures textureindex numcdtextures cdtextureindex numskinref numskinfamilies skinindex "
              "numbodyparts bodypartindex numlocalattachments localattachmentindex numlocalnodes localnodeindex "
              "localnodenameindex numflexdesc flexdescindex numflexcontrollers flexcontrollerindex numflexrules "
              "flexruleindex numikchains ikchainindex nummouths mouthindex numlocalposeparameters "
              "localposeparamindex surfacepropindex keyvalueindex keyvaluesize numlocalikautoplaylocks "
              "localikautoplaylockindex mass contents numincludemodels includemodelindex virtualModel "
              "szanimblocknameindex numanimblocks animblockindex animblockModel bonetablebynameindex "
              "pVertexBase pIndexBase").split()
    off = {f: H + 4 * i for i, f in enumerate(fields)}

    def hset(field, value, fmt="i"):
        b.put_at(off[field], fmt, value)

    hset("mass", 1.0, "f")
    hset("contents", 1)
    b.put_at(400, "i", 408)
    hdr2 = b.tell()
    b.put("i", 0)
    b.put("i", 0)
    b.put("i", 0)
    b.put("f", 0)
    b.put("i", 0)
    b.str_ref(hdr2, model_path)
    b.b += b"\0" * (256 - (b.tell() - hdr2))

    # кости
    bone0 = b.tell()
    hset("numbones", nb)
    hset("boneindex", bone0)
    for i, bn in enumerate(bones):
        o = b.tell()
        b.str_ref(o, bn["name"])
        b.put("i", bn["parent"])
        b.put("6i", *([-1] * 6))
        b.put("3f", *bn["pos"])
        b.put("4f", *bn["quat"])
        b.put("3f", *bn["rot"])
        b.put("3f", *scales[i]["posscale"])
        b.put("3f", *scales[i]["rotscale"])
        inv = np.linalg.inv(rest_world[i])[:3, :]
        b.put("12f", *inv.ravel())
        b.put("4f", 0, 0, 0, 0)
        b.put("i", USED_ALL)
        b.put("3i", 0, 0, 0)
        b.str_ref(o, surfaceprop)
        b.put("i", 1)
        b.put("8i", *([0] * 8))
    hset("bonecontrollerindex", b.tell())
    hset("localattachmentindex", b.tell())

    # хитбокс на корневой кости сумки
    bag_bone = max(set(v[4] for _, vs, _ in mesh_list for v in vs), key=lambda k: sum(1 for _, vs, _ in mesh_list for v in vs if v[4] == k))
    hbs = b.tell()
    hset("numhitboxsets", 1)
    hset("hitboxsetindex", hbs)
    b.str_ref(hbs, "default")
    b.put("ii", 1, 12)
    hb = b.tell()
    b.put("ii", bag_bone, 0)
    b.put("3f", -8, -8, -8)
    b.put("3f", 8, 8, 8)
    b.str_ref(hb, "")
    b.put("8i", *([0] * 8))

    # таблица костей по имени
    hset("bonetablebynameindex", b.tell())
    for i in sorted(range(nb), key=lambda k: bones[k]["name"].lower()):
        b.put("B", i)
    b.pad(4)

    # анимации
    b.pad(16)
    ad0 = b.tell()
    hset("numlocalanim", len(sequences))
    hset("localanimindex", ad0)
    b.b += b"\0" * (100 * len(sequences))
    for k, s in enumerate(sequences):
        ad = ad0 + 100 * k
        b.pad(16)
        data_at = b.tell()
        b.b += _encode_anim(bones, s["frames"], scales)
        b.put_at(ad, "i", -ad)
        b.strings.append((ad + 4, ad, "@" + s["name"]))
        b.put_at(ad + 8, "f", float(s["fps"]))
        b.put_at(ad + 12, "i", 1 if s.get("loop") else 0)
        b.put_at(ad + 16, "i", len(s["frames"]))
        b.put_at(ad + 56, "i", data_at - ad)
    b.pad(4)

    # последовательности
    sd0 = b.tell()
    hset("numlocalseq", len(sequences))
    hset("localseqindex", sd0)
    b.b += b"\0" * (212 * len(sequences))
    for k, s in enumerate(sequences):
        sd = sd0 + 212 * k
        b.pad(4)
        wl = b.tell()
        for _ in range(nb):
            b.put("f", 1.0)
        ai = b.tell()
        b.put("h", k)
        b.pad(4)
        kv = b.tell()
        seq = bytearray(212)
        struct.pack_into("<i", seq, 0, -sd)
        struct.pack_into("<iii", seq, 12, 1 if s.get("loop") else 0, -1, 0)
        struct.pack_into("<ii", seq, 24, 0, wl - sd)
        struct.pack_into("<3f3f", seq, 32, -40, -40, -40, 40, 40, 40)
        struct.pack_into("<ii", seq, 56, 1, ai - sd)
        struct.pack_into("<2i2i", seq, 68, 1, 1, -1, -1)
        struct.pack_into("<2f", seq, 104, 0.1, 0.1)
        struct.pack_into("<iii", seq, 148, 0, wl - sd, wl - sd)
        struct.pack_into("<iii", seq, 164, 0, ai - sd, kv - sd)
        b.b[sd:sd + 212] = seq
        b.strings.append((sd + 4, sd, s["name"]))
        b.strings.append((sd + 8, sd, ""))

    # bodypart / model / meshes
    bp = b.tell()
    hset("numbodyparts", 1)
    hset("bodypartindex", bp)
    hset("localnodeindex", bp)
    hset("localnodenameindex", bp)
    b.str_ref(bp, "body")
    b.put("iii", 1, 1, 16)
    mdl = b.tell()
    b.b += (name + ".smd").encode()[:63].ljust(64, b"\0")
    b.put("i", 0)
    b.put("f", 40.0)
    b.put("ii", len(mesh_list), 148)
    total_verts = sum(len(v) for _, v, _ in mesh_list)
    b.put("iii", total_verts, 0, 0)
    b.put("ii", 0, 0)
    eyeball_pos = b.tell()
    b.put("ii", 0, 0)
    b.put("2i", 0, 0)
    b.put("8i", *([0] * 8))
    voff = 0
    for i, (_, verts, _) in enumerate(mesh_list):
        me = b.tell()
        b.put("iii", i, mdl - me, len(verts))
        b.put("i", voff)
        b.put("iiiii", 0, 0, 0, 0, i)
        b.put("3f", 0, 0, 0)
        b.put("i", 0)
        b.put("8i", *([len(verts)] * 8))
        b.put("8i", *([0] * 8))
        voff += len(verts)
    b.put_at(eyeball_pos + 4, "i", b.tell() - mdl)
    for f in ("flexdescindex", "flexcontrollerindex", "flexruleindex", "ikchainindex", "mouthindex",
              "localposeparamindex", "localikautoplaylockindex"):
        hset(f, b.tell())
    b.put_at(388, "i", b.tell())

    tex = b.tell()
    hset("numtextures", len(mesh_list))
    hset("textureindex", tex)
    hset("includemodelindex", tex)
    hset("animblockindex", tex)
    for mat, _, _ in mesh_list:
        t = b.tell()
        b.str_ref(t, mat)
        b.put("5i", 0, 0, 0, 0, 0)
        b.put("10i", *([0] * 10))
    cd = b.tell()
    hset("numcdtextures", 1)
    hset("cdtextureindex", cd)
    b.str_ref(0, cdmaterials.replace("/", "\\").rstrip("\\") + "\\")
    sk = b.tell()
    hset("numskinref", len(mesh_list))
    hset("numskinfamilies", 1)
    hset("skinindex", sk)
    for i in range(len(mesh_list)):
        b.put("h", i)
    b.pad(4)

    st = b.tell()
    hset("keyvalueindex", st)
    hset("szanimblocknameindex", st)
    b.put_at(hdr2 + 4, "i", st)
    pool = {"": st}
    b.b += b"\0"
    for _, _, text in b.strings:
        if text not in pool:
            pool[text] = b.tell()
            b.b += text.encode() + b"\0"
    for pos, base, text in b.strings:
        b.put_at(pos, "i", pool[text] - base)
    hset("surfacepropindex", pool[surfaceprop])
    b.pad(4)
    b.put_at(76, "i", len(b.b))

    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, name)
    with open(base + ".mdl", "wb") as f:
        f.write(bytes(b.b))
    # VVD
    allv = [v for _, vs, _ in mesh_list for v in vs]
    n = len(allv)
    vvd = bytearray(struct.pack("<4si i i 8i i i i i", b"IDSV", 4, checksum, 1, *([n] * 8), 0, 64, 64, 64 + n * 48))
    for p, nrm, uv, _, bone in allv:
        vvd += struct.pack("<3f3BB3f3f2f", 1.0, 0.0, 0.0, bone, 0, 0, 1, *p, *nrm, *uv)
    for _, _, _, t, _ in allv:
        vvd += struct.pack("<4f", *t)
    with open(base + ".vvd", "wb") as f:
        f.write(bytes(vvd))
    # VTX: на меш — strip group и strip со своим набором «аппаратных» костей
    for ext, mbs in ((".dx90.vtx", 53), (".dx80.vtx", 16), (".sw.vtx", 53)):
        with open(base + ext, "wb") as f:
            f.write(_vtx(mesh_list, checksum, mbs))
    with open(base + ".phy", "wb") as f:
        f.write(mdlc._write_phy(name, mn, mx, 1.0, surfaceprop, checksum))
    return mn, mx


def _vtx(mesh_list, checksum, mbs):
    n = len(mesh_list)
    out = bytearray(struct.pack("<iiHHiiiiii", 7, 24, mbs, 9, 3, checksum, 1, 0, 1, 36))
    out += struct.pack("<ii", 1, 8)
    out += struct.pack("<ii", 1, 8)
    out += struct.pack("<iif", n, 12, 0.0)
    mesh0 = len(out)
    sg0 = mesh0 + 9 * n
    strip0 = sg0 + 25 * n
    vert0 = strip0 + 27 * n
    total_v = sum(len(v) for _, v, _ in mesh_list)
    idx0 = vert0 + 9 * total_v
    total_i = sum(len(i) for _, _, i in mesh_list)
    bsc0 = idx0 + 2 * total_i
    hw_sets = [sorted(set(v[4] for v in verts)) for _, verts, _ in mesh_list]
    mrl = bsc0 + 8 * sum(len(s) for s in hw_sets)
    out += b"\0" * (mrl + 8 - len(out))
    vpos, ipos, bpos = vert0, idx0, bsc0
    for k, (_, verts, index) in enumerate(mesh_list):
        me, sg, sp = mesh0 + 9 * k, sg0 + 25 * k, strip0 + 27 * k
        hw = hw_sets[k]
        struct.pack_into("<iiB", out, me, 1, sg - me, 0)
        struct.pack_into("<iiiiiiB", out, sg, len(verts), vpos - sg, len(index), ipos - sg, 1, sp - sg, 2)
        struct.pack_into("<iiiihBii", out, sp, len(index), 0, len(verts), 0, len(hw), 1, len(hw), bpos - sp)
        for i, v in enumerate(verts):
            struct.pack_into("<3BBH3b", out, vpos + 9 * i, 0, 1, 2, 1, i, hw.index(v[4]), 0, 0)
        struct.pack_into(f"<{len(index)}H", out, ipos, *index)
        for h, bone in enumerate(hw):
            struct.pack_into("<ii", out, bpos + 8 * h, h, bone)
        vpos += 9 * len(verts)
        ipos += 2 * len(index)
        bpos += 8 * len(hw)
    struct.pack_into("<i", out, 24, mrl)
    struct.pack_into("<ii", out, mrl, 0, 0)
    return bytes(out)
