"""Статическая проверка частых ошибок GMod, которые не видны стенду загрузки.

  1. net.Start("имя") без регистрации (core/sh_net.lua или util.AddNetworkString) — в игре ошибка «unpooled message».
  2. Вызов NYRP.X.Y(...) / X.Y(...) через локальный алиас, где функция Y нигде не определена.
  3. Иконки UI.DrawIcon/UI.Icon/"nyrp/status/..." и звуки "nyrp/..." и модели "models/nyrp/..." которых нет в content.
  4. Player:SetRenderAngles() без аргумента.
  5. hook.Add(..., имяФункции) на «событийных» хуках (возврат значения обрывает цепочку).

python3 tools/test/lint.py
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GM = os.path.join(ROOT, "gamemodes", "newyorkrp")
CONTENT = os.path.join(GM, "content")

files = sorted(glob.glob(os.path.join(GM, "**", "*.lua"), recursive=True))
src = {f: open(f, encoding="utf-8").read() for f in files}
problems = []


def rel(f):
    return os.path.relpath(f, GM)


def strip_comments(s):
    s = re.sub(r"--\[(=*)\[.*?\]\1\]", "", s, flags=re.S)
    return re.sub(r"--[^\n]*", "", s)


code = {f: strip_comments(s) for f, s in src.items()}

# ---------------------------------------------------------------- 1. net --
registered = set()
for f, s in code.items():
    registered |= set(re.findall(r'AddNetworkString\(\s*"([^"]+)"', s))
    # регистрация в цикле: for _, n in ipairs({ "a", "b" }) do util.AddNetworkString(n) end
    for m in re.finditer(r'ipairs\(\s*\{([^}]*)\}\s*\)\s*do[^\n]*\n?[^\n]*AddNetworkString\(\s*\w+\s*\)', s, re.S):
        registered |= set(re.findall(r'"([^"]+)"', m.group(1)))
netfile = code[os.path.join(GM, "gamemode", "core", "sh_net.lua")]
registered |= set(re.findall(r'"(nyrp\.[^"]+)"', netfile))
for f, s in code.items():
    for m in re.finditer(r'net\.Start\(\s*"([^"]+)"', s):
        if m.group(1) not in registered:
            line = s[:m.start()].count("\n") + 1
            problems.append(f"{rel(f)}:{line}: net.Start(\"{m.group(1)}\") — имя не зарегистрировано")

# ------------------------------------------------------- 2. функции NYRP --
# определённые: function NYRP.A.B / function A.B (где local A = NYRP.X) / NYRP.A.B = / A.B =
alias_of = {}
for f, s in code.items():
    for m in re.finditer(r'local\s+(\w+)\s*=\s*NYRP\.(\w+)\b(?!\.)', s):
        alias_of[(f, m.group(1))] = m.group(2)
defined = set()
for f, s in code.items():
    for m in re.finditer(r'function\s+NYRP\.(\w+)[.:](\w+)\s*\(', s):
        defined.add((m.group(1), m.group(2)))
    for m in re.finditer(r'NYRP\.(\w+)\.(\w+)\s*=(?!=)', s):
        defined.add((m.group(1), m.group(2)))
    for m in re.finditer(r'function\s+(\w+)[.:](\w+)\s*\(', s):
        ns = alias_of.get((f, m.group(1)))
        if ns:
            defined.add((ns, m.group(2)))
    for m in re.finditer(r'(?<![\w.])(\w+)\.(\w+)\s*=(?!=)', s):
        ns = alias_of.get((f, m.group(1)))
        if ns:
            defined.add((ns, m.group(2)))
    # таблица-конструктор: NYRP.X = { A = function... } — редкость, учтём ключи
    for m in re.finditer(r'NYRP\.(\w+)\s*=\s*NYRP\.\1\s+or\s+\{', s):
        pass
known_ns = {ns for ns, _ in defined}
for f, s in code.items():
    for m in re.finditer(r'NYRP\.(\w+)\.(\w+)\s*\(', s):
        ns, fn = m.group(1), m.group(2)
        if ns in known_ns and (ns, fn) not in defined:
            # вызов под проверкой «if NYRP.X.Y then» — допустим
            pre = s[max(0, m.start() - 160):m.start()]
            if re.search(r'NYRP\.%s\.%s\s*(then|and)' % (ns, fn), pre) or ("NYRP.%s.%s and" % (ns, fn)) in s:
                continue
            line = s[:m.start()].count("\n") + 1
            problems.append(f"{rel(f)}:{line}: NYRP.{ns}.{fn}() — функция нигде не определена")
    for m in re.finditer(r'(?<![\w.:])(\w+)\.(\w+)\s*\(', s):
        ns = alias_of.get((f, m.group(1)))
        if not ns or ns not in known_ns:
            continue
        fn = m.group(2)
        if (ns, fn) not in defined:
            pre = s[max(0, m.start() - 160):m.start()]
            if re.search(r'%s\.%s\s*(then|and)' % (m.group(1), fn), pre) or (f"{m.group(1)}.{fn} and") in s:
                continue
            line = s[:m.start()].count("\n") + 1
            problems.append(f"{rel(f)}:{line}: {m.group(1)}.{fn}() (= NYRP.{ns}.{fn}) — функция нигде не определена")

# ------------------------------------------------------------ 3. контент --
icons = {os.path.splitext(x)[0] for x in os.listdir(os.path.join(CONTENT, "materials", "nyrp", "icons"))}
status = {os.path.splitext(x)[0] for x in os.listdir(os.path.join(CONTENT, "materials", "nyrp", "status"))}
for f, s in code.items():
    for m in re.finditer(r'UI\.(?:DrawIcon|Icon)\(\s*"([\w]+)"', s):
        if m.group(1) not in icons:
            problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: иконка \"{m.group(1)}\" — нет в materials/nyrp/icons")
    for m in re.finditer(r'(?:icon|Icon|NYRPIcon)\s*=\s*"([\w]+)"', s):
        if m.group(1) not in icons and m.group(1) not in status:
            problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: иконка \"{m.group(1)}\" — нет ни в icons, ни в status")
    for m in re.finditer(r'"nyrp/status/([\w]+)\.png"', s):
        if m.group(1) not in status:
            problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: nyrp/status/{m.group(1)}.png — нет файла")
    for m in re.finditer(r'"(nyrp/[\w/]+\.(?:wav|mp3|ogg))"', s):
        if not os.path.isfile(os.path.join(CONTENT, "sound", m.group(1))):
            problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: звук {m.group(1)} — нет файла")
    for m in re.finditer(r'"(models/nyrp/[\w/.]+\.mdl)"', s):
        if not os.path.isfile(os.path.join(CONTENT, m.group(1))):
            problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: модель {m.group(1)} — нет файла")

# ---------------------------------------------------- 4. SetRenderAngles --
for f, s in code.items():
    for m in re.finditer(r'(ply|p|owner|target|LocalPlayer\(\))\s*:\s*SetRenderAngles\(\s*\)', s):
        problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: Player:SetRenderAngles() без аргумента")

# ---------------------------------------------------- 5. хуки-функции --
EVENT = r'(Initialize|InitPostEntity|PostCleanupMap|ShutDown|PlayerSpawn|PlayerInitialSpawn|PlayerDeath|PlayerDisconnected|Think|Tick|HUDPaint|NYRP\.\w+)'
for f, s in code.items():
    for m in re.finditer(r'hook\.Add\(\s*"' + EVENT + r'"\s*,\s*"[^"]+"\s*,\s*([A-Za-z_][\w.:]*)\s*\)', s):
        problems.append(f"{rel(f)}:{s[:m.start()].count(chr(10)) + 1}: hook.Add(\"{m.group(1)}\", ..., {m.group(2)}) — оберните в function() ... end")

for p in problems:
    print(p)
print("итого замечаний:", len(problems))
sys.exit(1 if problems else 0)
