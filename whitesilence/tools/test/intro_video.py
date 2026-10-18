"""Видеопревью интро (mp4 со звуком) без Garry's Mod.

    python3 tools/test/intro_video.py [out.mp4] [ширина]        (по умолчанию /tmp/ws_intro.mp4, 960)

Картинка — тот же Lua-код режима, отрисованный в Pillow (intro_frames.Canvas), 30 к/с.
Звук — сведение по меткам I.Cues из cl_config.lua с теми же нарастаниями, затуханиями и петлями.
Нужен ffmpeg.
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_frames as fr  # noqa: E402
import intro_sim as sim  # noqa: E402

SR = 44100
FPS = 30


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)


def smooth(k):
    k = np.clip(k, 0, 1)
    return k * k * (3 - 2 * k)


def mix_audio(lua, length):
    """Повторяет логику cl_audio + runCues: громкость ведётся плавно (smoothstep), петли крутятся."""
    cues = [dict(c.items()) for c in lua.eval("WS.Intro.Cues").values()]
    path = lua.eval("WS.Intro.Path")
    n = int(length * SR) + SR * 3
    out = np.zeros((n, 2), np.float32)
    voices = {}
    for i, c in enumerate(sorted(cues, key=lambda c: c["at"])):
        if c.get("play"):
            voices[c.get("id") or ("cue%d" % i)] = {
                "data": load(os.path.join(sim.CONTENT, "sound", path, c["play"] + ".ogg")),
                "start": c["at"], "loop": bool(c.get("loop")),
                "env": [(c["at"], 0.0 if c.get("fade") else c.get("vol", 1), c.get("vol", 1), c.get("fade") or 0.001)],
                "stop": None,
            }
        elif c.get("fade") and c["fade"] in voices:
            voices[c["fade"]]["env"].append((c["at"], None, c.get("vol", 0), c.get("time", 1)))
        elif c.get("stop") and c["stop"] in voices:
            voices[c["stop"]]["env"].append((c["at"], None, 0.0, c.get("time", 1)))
            voices[c["stop"]]["stop"] = c["at"] + c.get("time", 1)
    for v in voices.values():
        s0 = int(v["start"] * SR)
        end = int((v["stop"] or length + 2) * SR) if v["loop"] else s0 + len(v["data"])
        end = min(end, n)
        ln = end - s0
        if ln <= 0:
            continue
        d = v["data"]
        if v["loop"]:
            d = np.tile(d, (ln // len(d) + 1, 1))
        d = d[:ln]
        # огибающая громкости
        tt = v["start"] + np.arange(ln) / SR
        g = np.zeros(ln, np.float32)
        cur = 0.0
        for at, frm, to, dur in v["env"]:
            frm = cur if frm is None else frm
            k = smooth((tt - at) / dur)
            mask = tt >= at
            g[mask] = (frm + (to - frm) * k)[mask]
            cur = to
        out[s0:end] += d * g[:, None] * 0.8
    peak = np.abs(out).max()
    if peak > 0.98:
        out *= 0.98 / peak
    return out[: int(length * SR)]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ws_intro.mp4"
    W = int(sys.argv[2]) if len(sys.argv) > 2 else 960
    H = W * 9 // 16
    lua = sim.realm(False)
    g = lua.globals()
    g.SCRW, g.SCRH = W, H
    cv = fr.Canvas(W, H)
    fr.bind(lua, cv)
    lua.execute("hook.Remove('WSIntroFinished', 'ws.menu') hook.Remove('InitPostEntity', 'ws.menu')")
    lua.execute("hook.Run('InitPostEntity')")
    sim.run_timers(lua)
    lua.execute("INTRO = PANELS[#PANELS]")
    length = float(lua.eval("WS.Intro.Length"))

    wav = out + ".wav.f32"
    audio = mix_audio(lua, length)
    audio.astype(np.float32).tofile(wav)

    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y",
                            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
                            "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", wav,
                            "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
                            "-c:a", "aac", "-b:a", "160k", "-shortest", out], stdin=subprocess.PIPE)
    frames = 0
    while not lua.eval("INTRO.__removed"):
        g.NOW = g.NOW + 1 / FPS
        cv.img[:] = 0
        lua.eval("INTRO.Paint(INTRO, SCRW, SCRH)")
        lua.execute("hook.Run('Think')")
        enc.stdin.write(np.clip(cv.img, 0, 255).astype(np.uint8).tobytes())
        frames += 1
        if frames % 150 == 0:
            print("  %.0f с" % (frames / FPS), flush=True)
    enc.stdin.close()
    enc.wait()
    os.remove(wav)
    print(out, "%.1f с" % (frames / FPS))


if __name__ == "__main__":
    main()
