"""Иконки состояний (game-icons.net, CC BY 3.0 — авторы: Lorc, Delapouite и др.) -> PNG.

Берутся из npm-пакета @iconify-json/game-icons, все рисуются одинаково: белый силуэт 128x128,
цвет задаётся в игре. python3 tools/content/status_icons.py
"""
import io
import json
import os
import tarfile
import urllib.request

import cairosvg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "materials", "nyrp", "status")

ICONS = {
    "tired": "lungs", "hunger": "meal", "thirst": "water-drop", "wet": "droplets", "fall": "falling",
    "injured": "bleeding-wound", "critical": "heart-beats", "bruise": "broken-bone", "concussion": "knockout",
    "stamina": "run", "unconscious": "knockout", "cold": "thermometer-cold",
    # что в руках у игрока (табличка над головой)
    "w_pistol": "pistol-gun", "w_smg": "mp5", "w_rifle": "ak47", "w_shotgun": "sawed-off-shotgun",
    "w_melee": "bowie-knife", "w_grenade": "grenade", "w_tool": "spyglass",
    "w_hands": "hand", "unknown": "cowled", "known": "person",
    # NPC и задания
    "npc_trader": "shop", "npc_talk": "conversation", "quest": "scroll-quill", "quest_point": "flag-objective",
    # меню памяти (H)
    "mem_brain": "brain", "mem_think": "think", "mem_memories": "spiral-bloom", "mem_people": "shaking-hands",
    "mem_thought": "thought-bubble", "mem_done": "scroll-unfurled", "mem_eye": "semi-closed-eye",
    # курение, ранения по частям тела, броня, боевой навык
    "smoking": "cigarette", "cough": "lungs", "wound_leg": "leg", "wound_arm": "arm-sling", "wound_body": "bleeding-wound",
    "wound_head": "headshot", "bleeding": "bloody-stash", "armor": "kevlar-vest", "heavy": "weight", "combat": "crossed-swords",
    "skills": "upgrade",
    # фракции (значок слева от ника)
    "r_police": "police-badge", "r_medic": "caduceus", "r_fire": "fire-axe", "r_citizen": "person", "r_robber": "robber-mask",
    "siren": "siren", "handcuffs": "handcuffs", "ambulance": "ambulance", "fire": "fire", "extinguisher": "fire-extinguisher", "insight": "light-bulb", "body_front": "body-balance", "bandage": "bandage-roll", "splint": "leg-armor", "syringe": "syringe",
}


def main():
    cached = os.environ.get("NYRP_GI_TGZ")
    if cached and os.path.exists(cached):
        data = open(cached, "rb").read()
    else:
        meta = json.load(urllib.request.urlopen("https://registry.npmjs.org/@iconify-json/game-icons/latest"))
        data = urllib.request.urlopen(meta["dist"]["tarball"]).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        icons = json.load(t.extractfile("package/icons.json"))
    size = icons.get("width", 512)
    os.makedirs(OUT, exist_ok=True)
    for name, gi in ICONS.items():
        body = icons["icons"][gi]["body"].replace('fill="currentColor"', 'fill="#ffffff"')
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" fill="#ffffff">{body}</svg>'
        cairosvg.svg2png(bytestring=svg.encode(), write_to=os.path.join(OUT, name + ".png"), output_width=128, output_height=128)
    with open(os.path.join(OUT, "CREDITS.txt"), "w") as f:
        f.write("Иконки состояний: game-icons.net (CC BY 3.0) — Lorc, Delapouite и другие авторы.\n")
        for name, gi in ICONS.items():
            f.write(f"{name}.png <- {gi}\n")
    print("status icons:", len(ICONS))


if __name__ == "__main__":
    main()
