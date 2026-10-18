"""Картины сцен интро нейросетью Stable Diffusion XL 1.0 (на процессоре, ~5 мин на кадр 1344x768).

    pip install torch diffusers transformers accelerate safetensors
    python3 tools/content/gen_paintings.py [сцена ...]        -> tools/content/paintings/<сцена>_<seed>.png

Модель берётся из Docker Hub (ai/stable-diffusion, официальный SDXL base 1.0, лицензия CreativeML Open RAIL++-M):
скрипт сам скачивает слой-архив DDUF (~7 ГБ) и распаковывает его в WS_SDXL_DIR (по умолчанию /tmp/sdxl).
Лучший вариант кадра переименуйте в paintings/<сцена>.png и запустите intro_art.py paintings.

Промпты короткие нарочно: у SDXL окно текста 77 токенов, всё длиннее молча обрезается.
"""
import json
import os
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "paintings")
MODEL = os.environ.get("WS_SDXL_DIR", "/tmp/sdxl")
REPO, TAG = "ai/stable-diffusion", "latest"

STYLE = "concept art digital painting, loose painterly brush strokes, muted desaturated blue-grey palette, cinematic, "
NEG = ("photo, photorealistic, 3d render, text, watermark, logo, signature, cartoon, anime, bright colors, "
       "lowres, blurry, deformed, bad anatomy, extra limbs")
SCENES = {
    "arctic": ("vast arctic ice field in heavy blizzard, squad of six soldiers walking in a line through deep snow in the distance, "
               "ice cliffs, dark water between ice floes, stormy sky", [11, 22, 33]),
    "closeup": ("squad of soldiers in arctic winter gear standing still in a blizzard, balaclavas and goggles hide faces, rifles, "
                "snow on hoods, ominous, uncanny", [41, 52, 63]),
    "dead": ("high angle close-up of a dead soldier's arm with black glove lying in snow, blood soaked into white snow, "
             "walkie-talkie radio half buried in snow nearby", [71, 82, 93]),
    "heli": ("inside a military helicopter in flight, soldiers in white arctic camouflage with helmets and rifles sitting, "
             "open side door, snowy mountains below", [101, 112, 123]),
    "banner_bg": ("dark stormy arctic night, distant remote research facility with small lights in a blizzard, very dark, "
                  "empty dark sky", [131, 142]),
}


def fetch_model():
    if os.path.exists(os.path.join(MODEL, "model_index.json")):
        return
    tok = json.load(urllib.request.urlopen(
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository:%s:pull" % REPO))["token"]
    req = urllib.request.Request("https://registry-1.docker.io/v2/%s/manifests/%s" % (REPO, TAG), headers={
        "Authorization": "Bearer " + tok, "Accept": "application/vnd.oci.image.manifest.v1+json"})
    layer = json.load(urllib.request.urlopen(req))["layers"][0]
    os.makedirs(MODEL, exist_ok=True)
    dduf = os.path.join(MODEL, "model.dduf")
    print("скачиваю SDXL (%.1f ГБ)..." % (layer["size"] / 2 ** 30))
    req = urllib.request.Request("https://registry-1.docker.io/v2/%s/blobs/%s" % (REPO, layer["digest"]),
                                 headers={"Authorization": "Bearer " + tok})
    with urllib.request.urlopen(req) as r, open(dduf, "wb") as f:
        while True:
            chunk = r.read(1 << 22)
            if not chunk:
                break
            f.write(chunk)
    zipfile.ZipFile(dduf).extractall(MODEL)   # DDUF — это zip с обычной папкой diffusers
    os.remove(dduf)


def main():
    import torch
    from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLPipeline
    fetch_model()
    torch.set_num_threads(os.cpu_count() or 4)
    pipe = StableDiffusionXLPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, use_karras_sigmas=True,
                                                             algorithm_type="dpmsolver++")
    os.makedirs(OUT, exist_ok=True)
    for name in sys.argv[1:] or list(SCENES):
        prompt, seeds = SCENES[name]
        for seed in seeds:
            img = pipe(prompt=STYLE + prompt, negative_prompt=NEG, width=1344, height=768, num_inference_steps=26,
                       guidance_scale=6.5, generator=torch.Generator().manual_seed(seed)).images[0]
            path = os.path.join(OUT, "%s_%d.png" % (name, seed))
            img.save(path)
            print(path)


if __name__ == "__main__":
    main()
