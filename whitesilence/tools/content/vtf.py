"""Запись текстур Source (VTF 7.2, несжатый BGRA8888 с мип-уровнями) и материалов VMT.

    from vtf import save_vtf, save_vmt
    save_vtf(pil_image, "content/materials/whitesilence/fx/outline_fill.vtf")
    save_vmt("content/materials/whitesilence/fx/outline.vmt", "UnlitGeneric", {"$basetexture": "whitesilence/fx/outline_fill"})

Размер стороны — степень двойки. Мип-уровни хранятся от меньшего к большему (как требует формат).
"""
import struct

from PIL import Image

IMAGE_FORMAT_BGRA8888 = 12
FLAG_TRILINEAR = 0x0002
FLAG_CLAMPS = 0x0004
FLAG_CLAMPT = 0x0008
FLAG_NOMIP = 0x0100
FLAG_NOLOD = 0x0200
FLAG_EIGHTBITALPHA = 0x2000


def _pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def save_vtf(img, path, clamp=False, mips=True, srgb_alpha=True, fmt="bgra"):
    """fmt: "bgra" — без сжатия (своя запись), "dxt1" / "dxt5" — сжатие через srctools (pip install srctools)."""
    img = img.convert("RGBA")
    if fmt in ("dxt1", "dxt5"):
        from srctools.vtf import VTF, ImageFormats, VTFFlags
        w, h = img.size
        assert _pow2(w) and _pow2(h), "сторона VTF должна быть степенью двойки: %dx%d" % (w, h)
        v = VTF(w, h, fmt=ImageFormats.DXT1 if fmt == "dxt1" else ImageFormats.DXT5,
                flags=VTFFlags.TRILINEAR | (VTFFlags.EIGHTBITALPHA if fmt == "dxt5" else VTFFlags(0)) | (VTFFlags.CLAMP_S | VTFFlags.CLAMP_T if clamp else VTFFlags(0)))
        v.get().copy_from(img.tobytes(), ImageFormats.RGBA8888)
        v.compute_mipmaps()
        with open(path, "wb") as f:
            v.save(f)
        return
    w, h = img.size
    assert _pow2(w) and _pow2(h), "сторона VTF должна быть степенью двойки: %dx%d" % (w, h)
    levels = [img]
    if mips:
        while levels[-1].size != (1, 1):
            lw, lh = levels[-1].size
            levels.append(levels[-1].resize((max(1, lw // 2), max(1, lh // 2)), Image.LANCZOS))
    flags = FLAG_EIGHTBITALPHA | FLAG_TRILINEAR | (FLAG_CLAMPS | FLAG_CLAMPT if clamp else 0) | (0 if mips else FLAG_NOMIP | FLAG_NOLOD)
    # средний цвет — «отражательная способность» (используется движком для освещения)
    avg = img.resize((1, 1), Image.LANCZOS).getpixel((0, 0))
    refl = [c / 255.0 for c in avg[:3]]
    hdr = struct.pack("<4s2II HH I HH 4x 3f 4x f I B I BB H",
                      b"VTF\0", 7, 2, 80, w, h, flags, 1, 0, refl[0], refl[1], refl[2], 1.0,
                      IMAGE_FORMAT_BGRA8888, len(levels), 0xFFFFFFFF, 0, 0, 1)
    hdr = hdr + b"\0" * (80 - len(hdr))
    data = bytearray()
    for lvl in reversed(levels):
        r, g, b, a = lvl.split()
        data += Image.merge("RGBA", (b, g, r, a)).tobytes()
    with open(path, "wb") as f:
        f.write(hdr)
        f.write(data)


def save_vmt(path, shader, params):
    lines = ['"%s"' % shader, "{"]
    for k, v in params.items():
        lines.append('\t"%s" "%s"' % (k, v))
    lines.append("}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def read_vtf_header(path):
    b = open(path, "rb").read(80)
    sig, v0, v1, hs, w, h, flags, frames, first = struct.unpack_from("<4s2II HH I HH", b, 0)
    fmt, = struct.unpack_from("<I", b, 52)
    mips = b[56]
    return dict(sig=sig, version=(v0, v1), header=hs, w=w, h=h, flags=flags, frames=frames, format=fmt, mips=mips)
