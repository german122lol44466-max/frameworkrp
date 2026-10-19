"""Синтаксис всех .lua режима (компиляция без запуска).

    python3 tools/test/lua_syntax.py
"""
import os
import sys

import lupa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
lua = lupa.LuaRuntime()
check = lua.eval("function(src, name) local f, err = load(src, name) return err end")
bad = 0
n = 0
for base, _, files in os.walk(os.path.join(ROOT, "gamemodes")):
    for f in files:
        if f.endswith(".lua"):
            p = os.path.join(base, f)
            src = open(p, encoding="utf-8").read()
            # GMod-синтаксис, которого нет в Lua 5.x: != и ! (в коде режима не используем), // комментарии — тоже
            err = check(src, "@" + os.path.relpath(p, ROOT))
            n += 1
            if err:
                bad += 1
                print("ОШИБКА:", err)
print("файлов: %d, с ошибками: %d" % (n, bad))
sys.exit(1 if bad else 0)
