"""Проверка моделей Source MDL v48: разбор mdl/vvd/vtx/phy как это делает движок.

python3 tools/models/mdl_check.py path/to/model.mdl [...]
Печатает сводку и падает с ошибкой, если структуры не сходятся.
"""
import struct
import sys


def S(d, o):
    return d[o:d.index(b"\0", o)].decode()


def check(path):
    base = path[:-4]
    d = open(path, "rb").read()
    assert d[:4] == b"IDST" and struct.unpack_from("<i", d, 4)[0] == 48, "не MDL v48"
    ck = struct.unpack_from("<i", d, 8)[0]
    length = struct.unpack_from("<i", d, 76)[0]
    assert length == len(d), f"length {length} != {len(d)}"
    I = lambda o: struct.unpack_from("<i", d, o)[0]
    nb, bi = I(156), I(160)
    nseq, si = I(188), I(192)
    nt, ti = I(204), I(208)
    ncd, cdi = I(212), I(216)
    nbp, bpi = I(232), I(236)
    out = {"name": d[12:76].split(b"\0")[0].decode(), "bones": [S(d, bi + i * 216 + I(bi + i * 216)) for i in range(nb)],
           "surfaceprop": S(d, I(308)), "textures": [S(d, ti + i * 64 + I(ti + i * 64)) for i in range(nt)],
           "cdmaterials": [S(d, I(cdi + i * 4)) for i in range(ncd)],
           "sequences": [S(d, si + i * 212 + I(si + i * 212 + 4)) for i in range(nseq)]}
    # анимация первой последовательности
    na, ai = I(180), I(184)
    for a in range(na):
        ad = ai + a * 100
        assert I(ad) == -ad, "animdesc baseptr"
        an = ad + I(ad + 56)
        bone, flags, nxt = struct.unpack_from("<BBh", d, an)
        assert bone < nb
    hdr2 = I(400)
    assert S(d, hdr2 + I(hdr2 + 20)) == out["name"], "hdr2 name"
    meshes = []
    for b in range(nbp):
        bp = bpi + b * 16
        nm, base_, mi = struct.unpack_from("<iii", d, bp + 4)
        for m in range(nm):
            mo = bp + mi + m * 148
            nmesh, meshi, nverts, vidx = struct.unpack_from("<iiii", d, mo + 72)
            for k in range(nmesh):
                me = mo + meshi + k * 116
                mat, modelindex, mnv, voff = struct.unpack_from("<iiii", d, me)
                assert me + modelindex == mo, "mesh->model"
                meshes.append((mat, mnv, vidx // 48 + voff))
    # VVD
    v = open(base + ".vvd", "rb").read()
    vid, vver, vck, nlod = struct.unpack_from("<4siii", v, 0)
    assert vid == b"IDSV" and vck == ck, "vvd checksum"
    nverts = struct.unpack_from("<i", v, 16)[0]
    vstart, tstart = struct.unpack_from("<ii", v, 56)
    assert tstart == vstart + nverts * 48 and len(v) == tstart + nverts * 16, "vvd size"
    verts = [struct.unpack_from("<3f3BB3f3f2f", v, vstart + i * 48) for i in range(nverts)]
    assert sum(m[1] for m in meshes) == nverts, "mesh vertex sum"
    # VTX
    tris = []
    for ext in (".dx90.vtx", ".dx80.vtx", ".sw.vtx"):
        x = open(base + ext, "rb").read()
        ver, cache, mbs, mbt, mbv, xck, nl, mrl, nbpx, bpo = struct.unpack_from("<iiHHiiiiii", x, 0)
        assert ver == 7 and xck == ck, ext + " header"
        assert struct.unpack_from("<ii", x, mrl) == (0, 0) and mrl + 8 == len(x)
        cur = []
        nmod, mof = struct.unpack_from("<ii", x, bpo)
        mp = bpo + mof
        nl2, lo = struct.unpack_from("<ii", x, mp)
        lp = mp + lo
        nmx, meo, sw = struct.unpack_from("<iif", x, lp)
        assert nmx == len(meshes), "vtx mesh count"
        for k in range(nmx):
            mh = lp + meo + k * 9
            nsg, sgo, fl = struct.unpack_from("<iiB", x, mh)
            for g in range(nsg):
                sg = mh + sgo + g * 25
                nv, vo, ni, io, ns, so, f = struct.unpack_from("<iiiiiiB", x, sg)
                sv = [struct.unpack_from("<3BBH3b", x, sg + vo + i * 9) for i in range(nv)]
                idx = struct.unpack_from(f"<{ni}H", x, sg + io)
                for s in range(ns):
                    st = struct.unpack_from("<iiiihBii", x, sg + so + s * 27)
                    assert st[5] & 1, "trilist"
                    nbsc = st[6]
                    for c in range(nbsc):  # смена аппаратных костей (у анимированных моделей)
                        hw, bone = struct.unpack_from("<ii", x, sg + so + s * 27 + st[7] + c * 8)
                        assert 0 <= hw < mbs and 0 <= bone < nb, "bone state change"
                    for t in range(st[1], st[1] + st[0], 3):
                        tri = []
                        for j in (0, 2, 1):  # по часовой -> против
                            vv = sv[idx[t + j] + st[3]]
                            assert vv[4] < meshes[k][1], "origMeshVertID"
                            p = verts[meshes[k][2] + vv[4]]
                            tri.append((p[7:10], p[10:13], p[13:15]))
                        cur.append((meshes[k][0], tri))
        tris.append(cur)
    assert tris[0] == tris[1] == tris[2]
    # PHY
    p = open(base + ".phy", "rb").read()
    hs, pid, solids, pck = struct.unpack_from("<iiii", p, 0)
    assert hs == 16 and pck == ck and solids == 1, "phy header"
    size = struct.unpack_from("<i", p, 16)[0]
    assert p[20:24] == b"VPHY"
    assert b"IVPS" in p[20:20 + size]
    assert p[20 + size:].startswith(b"solid {")
    out["triangles"] = len(tris[0])
    out["vertices"] = nverts
    return out, tris[0], verts


if __name__ == "__main__":
    for p in sys.argv[1:]:
        info, _, _ = check(p)
        print("OK", p, info)
