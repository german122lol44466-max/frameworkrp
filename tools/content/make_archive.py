"""Упаковка контента в архивы (dist/).

  dist/newyorkrp_content.zip     — аддон с контентом (materials, models, sound, resource + addon.json):
                                   распаковать в garrysmod/addons/ или залить в Workshop.
  dist/newyorkrp_models_src.zip  — исходники моделей: .blend, SMD, QC, скрипты.

Запуск: python3 tools/content/make_archive.py
"""
import json
import os
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONTENT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content")
DIST = os.path.join(ROOT, "dist")


def add_dir(z, src, arc_prefix):
    for base, _, files in os.walk(src):
        for f in sorted(files):
            if f.endswith((".log", ".pyc")):
                continue
            full = os.path.join(base, f)
            z.write(full, os.path.join(arc_prefix, os.path.relpath(full, src)))


def main():
    os.makedirs(DIST, exist_ok=True)
    path = os.path.join(DIST, "newyorkrp_content.zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        add_dir(z, CONTENT, "newyorkrp_content")
        z.writestr("newyorkrp_content/addon.json", json.dumps({
            "title": "New-York Roleplay — Content",
            "type": "servercontent",
            "tags": ["roleplay", "realism"],
            "ignore": ["*.psd", "*.log"],
        }, ensure_ascii=False, indent=2))
    print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")

    path = os.path.join(DIST, "newyorkrp_models_src.zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        models = os.path.join(ROOT, "tools", "models")
        for f in ("bags.blend", "clothes.blend", "build_bags.py", "build_clothes.py", "mdlc.py", "mdl_check.py"):
            z.write(os.path.join(models, f), os.path.join("newyorkrp_models_src", f))
        add_dir(z, os.path.join(models, "src"), "newyorkrp_models_src/src")
        z.write(os.path.join(ROOT, "tools", "compile_models.bat"), "newyorkrp_models_src/compile_models.bat")
    print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
