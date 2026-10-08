"""Чтение моделей Source MDL v48/49: скелет, анимации (с декодированием), сетка (VVD/VTX).

Используется для импорта c_arms в Blender и для проверки собственных анимированных моделей.
"""
import math
import struct


def _s(d, o):
    return d[o:d.index(b"\0", o)].decode("latin-1")


def quat_from_euler(x, y, z):
    """RadianEuler -> Quaternion (как AngleQuaternion(RadianEuler) в Source)."""
    sr, cr = math.sin(x * 0.5), math.cos(x * 0.5)
    sp, cp = math.sin(y * 0.5), math.cos(y * 0.5)
    sy, cy = math.sin(z * 0.5), math.cos(z * 0.5)
    srXcp, crXsp = sr * cp, cr * sp
    qx = srXcp * cy - crXsp * sy
    qy = crXsp * cy + srXcp * sy
    crXcp, srXsp = cr * cp, sr * sp
    qz = crXcp * sy - srXsp * cy
    qw = crXcp * cy + srXsp * sy
    return (qx, qy, qz, qw)


def _anim_value(d, base, frame, scale):
    """ExtractAnimValue: RLE-поток mstudioanimvalue_t."""
    k = frame
    o = base
    while True:
        valid, total = d[o], d[o + 1]
        if total == 0:
            return 0.0
        if total <= k:
            k -= total
            o += 2 * (valid + 1)
            continue
        if valid > k:
            v = struct.unpack_from("<h", d, o + 2 * (k + 1))[0]
        else:
            v = struct.unpack_from("<h", d, o + 2 * valid)[0]
        return v * scale


def _q48(d, o):
    a, b, c = struct.unpack_from("<HHH", d, o)
    x = (a - 32768) * (1 / 32768.0)
    y = (b - 32768) * (1 / 32768.0)
    z = ((c & 0x7FFF) - 16384) * (1 / 16384.0)
    w = math.sqrt(max(0.0, 1 - x * x - y * y - z * z))
    if c & 0x8000:
        w = -w
    return (x, y, z, w)


def _q64(d, o):
    q = struct.unpack_from("<Q", d, o)[0]
    x = ((q & 0x1FFFFF) - 1048576) * (1 / 1048576.5)
    y = (((q >> 21) & 0x1FFFFF) - 1048576) * (1 / 1048576.5)
    z = (((q >> 42) & 0x1FFFFF) - 1048576) * (1 / 1048576.5)
    w = math.sqrt(max(0.0, 1 - x * x - y * y - z * z))
    if q >> 63:
        w = -w
    return (x, y, z, w)


def _f16(h):
    import numpy as np
    return float(np.frombuffer(struct.pack("<H", h), dtype=np.float16)[0])


class MDL:
    def __init__(self, path):
        self.path = path
        d = self.d = open(path, "rb").read()
        assert d[:4] == b"IDST"
        self.version = struct.unpack_from("<i", d, 4)[0]
        self.checksum = struct.unpack_from("<i", d, 8)[0]
        self.name = d[12:76].split(b"\0")[0].decode()
        I = lambda o: struct.unpack_from("<i", d, o)[0]
        self.flags = I(152)
        nb, bi = I(156), I(160)
        self.bones = []
        for i in range(nb):
            o = bi + i * 216
            b = {
                "name": _s(d, o + I(o)), "parent": I(o + 4),
                "pos": struct.unpack_from("<3f", d, o + 32), "quat": struct.unpack_from("<4f", d, o + 44),
                "rot": struct.unpack_from("<3f", d, o + 60), "posscale": struct.unpack_from("<3f", d, o + 72),
                "rotscale": struct.unpack_from("<3f", d, o + 84), "poseToBone": struct.unpack_from("<12f", d, o + 96),
                "qalign": struct.unpack_from("<4f", d, o + 144), "flags": I(o + 160),
                "proctype": I(o + 164), "procindex": I(o + 168), "physicsbone": I(o + 172),
                "surfaceprop": _s(d, o + I(o + 176)), "contents": I(o + 180),
            }
            self.bones.append(b)
        na, ai = I(180), I(184)
        self.anims = []
        for a in range(na):
            o = ai + a * 100
            self.anims.append({
                "offset": o, "name": _s(d, o + I(o + 4)), "fps": struct.unpack_from("<f", d, o + 8)[0],
                "flags": I(o + 12), "numframes": I(o + 16), "animblock": I(o + 52), "animindex": I(o + 56),
                "sectionindex": I(o + 80), "sectionframes": I(o + 84),
            })
        ns, si = I(188), I(192)
        self.seqs = []
        for s in range(ns):
            o = si + s * 212
            nbl = I(o + 56)
            aii = o + I(o + 60)
            g = struct.unpack_from("<2i", d, o + 68)
            self.seqs.append({"name": _s(d, o + I(o + 4)), "activity": _s(d, o + I(o + 8)), "flags": I(o + 12),
                              "anims": [struct.unpack_from("<h", d, aii + 2 * k)[0] for k in range(g[0] * g[1])]})
        self.textures = [_s(d, I(208) + t * 64 + I(I(208) + t * 64)) for t in range(I(204))]
        self.cdmaterials = [_s(d, I(I(216) + 4 * k)) for k in range(I(212))]
        # модели и меши
        self.meshes = []
        nbp, bpi = I(232), I(236)
        for b in range(nbp):
            bp = bpi + b * 16
            nm, base, mi = struct.unpack_from("<iii", d, bp + 4)
            for m in range(nm):
                mo = bp + mi + m * 148
                nmesh, meshi, nverts, vidx = struct.unpack_from("<iiii", d, mo + 72)
                for k in range(nmesh):
                    me = mo + meshi + k * 116
                    mat, _, mnv, voff = struct.unpack_from("<iiii", d, me)
                    self.meshes.append({"model": m, "material": mat, "numverts": mnv, "first": vidx // 48 + voff})

    # --------------------------------------------------------------- анимации
    def anim_frame(self, anim_index, frame):
        """Локальные (pos, quat) всех костей на кадре (как CalcPose без интерполяции)."""
        d = self.d
        a = self.anims[anim_index]
        out = [(b["pos"], b["quat"]) for b in self.bones]
        if a["animblock"] != 0:
            raise NotImplementedError("animblock")
        base = a["offset"]
        if a["sectionframes"]:
            sec = frame // a["sectionframes"]
            animoff = struct.unpack_from("<ii", d, base + a["sectionindex"] + sec * 8)[1]
            frame -= sec * a["sectionframes"]
        else:
            animoff = a["animindex"]
        o = base + animoff
        while True:
            bone, flags, nxt = struct.unpack_from("<BBh", d, o)
            b = self.bones[bone]
            p = o + 4
            pos, quat = b["pos"], b["quat"]
            if flags & 0x02:  # RAWROT
                quat = _q48(d, p)
                p += 6
            if flags & 0x20:  # RAWROT2
                quat = _q64(d, p)
                p += 8
            if flags & 0x01:  # RAWPOS
                pos = tuple(_f16(h) for h in struct.unpack_from("<3H", d, p))
                p += 6
            if flags & 0x08:  # ANIMROT
                offs = struct.unpack_from("<3h", d, p)
                ang = [(_anim_value(d, p + offs[j], frame, b["rotscale"][j]) if offs[j] else 0.0) for j in range(3)]
                if not flags & 0x10:
                    ang = [ang[j] + b["rot"][j] for j in range(3)]
                quat = quat_from_euler(*ang)
                p += 6
            if flags & 0x04:  # ANIMPOS
                offs = struct.unpack_from("<3h", d, p)
                v = [(_anim_value(d, p + offs[j], frame, b["posscale"][j]) if offs[j] else 0.0) for j in range(3)]
                if not flags & 0x10:
                    v = [v[j] + b["pos"][j] for j in range(3)]
                pos = tuple(v)
            out[bone] = (pos, quat)
            if nxt == 0:
                break
            o += nxt
        return out

    # ------------------------------------------------------------------ сетка
    def load_mesh(self, base):
        """Вершины VVD (pos, normal, uv, [(bone, weight)]) и треугольники по материалам из .dx90.vtx."""
        v = open(base + ".vvd", "rb").read()
        nlod = struct.unpack_from("<i", v, 12)[0]
        nverts = struct.unpack_from("<i", v, 16)[0]
        nfix, fixstart, vstart, tstart = struct.unpack_from("<iiii", v, 48)
        raw = []
        for i in range(nverts):
            w = struct.unpack_from("<3f3BB3f3f2f", v, vstart + i * 48)
            weights = [(w[3 + k], w[k]) for k in range(w[6])]
            raw.append((w[7:10], w[10:13], w[13:15], weights))
        verts = raw
        if nfix:
            verts = []
            for f in range(nfix):
                lod, src, num = struct.unpack_from("<iii", v, fixstart + f * 12)
                if lod >= 0:
                    verts += raw[src:src + num]
        x = open(base + ".dx90.vtx", "rb").read()
        ver, cache, mbs, mbt, mbv, ck, nl, mrl, nbpx, bpo = struct.unpack_from("<iiHHiiiiii", x, 0)
        tris = {}
        mi = 0
        for b in range(nbpx):
            bp = bpo + b * 8
            nmod, mof = struct.unpack_from("<ii", x, bp)
            for m in range(nmod):
                mp = bp + mof + m * 8
                nl2, lo = struct.unpack_from("<ii", x, mp)
                lp = mp + lo
                nmx, meo, sw = struct.unpack_from("<iif", x, lp)
                for k in range(nmx):
                    mesh = self.meshes[mi]
                    mi += 1
                    mh = lp + meo + k * 9
                    nsg, sgo, fl = struct.unpack_from("<iiB", x, mh)
                    for g in range(nsg):
                        sg = mh + sgo + g * 25
                        nv, vo, ni, io, nst, so, f = struct.unpack_from("<iiiiiiB", x, sg)
                        sv = [struct.unpack_from("<3BBH3b", x, sg + vo + i * 9)[4] for i in range(nv)]
                        idx = struct.unpack_from(f"<{ni}H", x, sg + io)
                        for s in range(nst):
                            st = struct.unpack_from("<iiiihBii", x, sg + so + s * 27)
                            for t in range(st[1], st[1] + st[0], 3):
                                tri = [mesh["first"] + sv[idx[t + j] + st[3]] for j in (0, 2, 1)]
                                tris.setdefault(mesh["material"], []).append(tri)
        return verts, tris
