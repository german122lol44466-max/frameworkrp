"""Стенд загрузки режима без Garry's Mod.

Запускает настоящий порядок подключения (init.lua / cl_init.lua -> shared.lua -> core -> modules -> entities)
в Lua 5.4 (lupa). API GMod заменён заглушками, но таблица NYRP настоящая — поэтому ловятся ошибки
вида «attempt to index nil» при загрузке и в вызовах хуков.

python3 tools/test/load_test.py [--hooks]
"""
import os
import re
import sys

import lupa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GMROOT = os.path.join(ROOT, "gamemodes")

PRELUDE = r'''
local STUB
local stubmt = {}
stubmt.__index = function(t, k) return STUB end
stubmt.__newindex = function() end
stubmt.__call = function() return STUB end
stubmt.__add = function() return 0 end stubmt.__sub = stubmt.__add stubmt.__mul = stubmt.__add
stubmt.__div = stubmt.__add stubmt.__unm = function() return 0 end stubmt.__mod = stubmt.__add
stubmt.__concat = function() return "" end stubmt.__len = function() return 0 end
stubmt.__lt = function() return false end stubmt.__le = function() return false end
stubmt.__tostring = function() return "stub" end
STUB = setmetatable({}, stubmt)
_STUB = STUB

-- неизвестные глобальные (API GMod) -> заглушка
local REAL_NIL = { NYRP = true, ENT = true, SWEP = true }
setmetatable(_G, { __index = function(_, k) if REAL_NIL[k] then return nil end return STUB end })

function string.StartWith(s, p) return string.sub(s, 1, #p) == p end
function string.GetFileFromFilename(p) return string.match(p, "([^/]+)$") or p end
function string.Trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function string.rep2() end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.GetKeys(t) local o = {} for k in pairs(t) do o[#o + 1] = k end return o end
function table.Copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
function table.Merge(a, b) for k, v in pairs(b) do a[k] = v end return a end
function table.KeyFromValue(t, v) for k, x in pairs(t) do if x == v then return k end end end
function table.Random(t) return t[1] end
function math.Clamp(v, a, b) return math.min(math.max(v, a), b) end
function math.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
function math.Rand(a, b) return a end
function Lerp(t, a, b) return a + (b - a) * t end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return v ~= nil and v ~= false end
unpack = table.unpack
-- циклы по заглушке — пустые (иначе ipairs(_STUB) бесконечен: _STUB[i] всегда «есть»)
local _ipairs, _pairs, _next = ipairs, pairs, next
function ipairs(t) if t == STUB or type(t) ~= "table" then return function() end, t, 0 end return _ipairs(t) end
function pairs(t) if t == STUB or type(t) ~= "table" then return function() end, t, nil end return _pairs(t) end
function next(t, k) if t == STUB or type(t) ~= "table" then return nil end return _next(t, k) end
TIMERS = {}
timer = setmetatable({
	Create = function(id, delay, reps, fn) if type(fn) == "function" then TIMERS[#TIMERS + 1] = { "timer " .. tostring(id), fn } end end,
	Simple = function(delay, fn) if type(fn) == "function" then TIMERS[#TIMERS + 1] = { "timer.Simple", fn } end end,
}, { __index = function() return STUB end })

HOOKS = {}
hook = {
	Add = function(name, id, fn) HOOKS[#HOOKS + 1] = { name, id, fn } end,
	Remove = function() end,
	Run = function() end,
	Call = function() end,
}
NETS = {}
net = setmetatable({ Receive = function(name, fn) NETS[name] = fn end }, { __index = function() return STUB end })
CONCMDS = {}
concommand = { Add = function(n, fn) CONCMDS[n] = fn end }
vgui = setmetatable({ Register = function(name, t) REGISTERED = REGISTERED or {} REGISTERED[name] = t end },
	{ __index = function() return STUB end })
'''


def run(realm, call_hooks):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    g = lua.globals()
    g.SERVER = realm == "server"
    g.CLIENT = realm == "client"
    errors = []
    stack = []

    def resolve(path):
        cands = []
        if stack:
            cands.append(os.path.join(os.path.dirname(stack[-1]), path))
        cands.append(os.path.join(GMROOT, path))
        for c in cands:
            if os.path.isfile(c):
                return os.path.normpath(c)
        return None

    def include(path):
        full = resolve(path)
        if not full:
            errors.append(f"include: не найден {path}")
            return None
        src = open(full, encoding="utf-8").read()
        stack.append(full)
        try:
            fn = lua.eval("function(src, name) return load(src, '@' .. name) end")(src, os.path.relpath(full, ROOT))
            if fn is None or isinstance(fn, tuple):
                errors.append(f"синтаксис: {full}: {fn[1] if isinstance(fn, tuple) else ''}")
                return None
            return fn()
        except lupa.LuaError as e:
            errors.append(str(e).split("stack traceback")[0].strip())
        finally:
            stack.pop()

    def find(pattern, path):
        base = os.path.join(GMROOT, os.path.dirname(pattern))
        if not os.path.isdir(base):
            return lua.table(), lua.table()
        mask = os.path.basename(pattern).replace("*", ".*")
        files = sorted(f for f in os.listdir(base) if os.path.isfile(os.path.join(base, f)) and re.fullmatch(mask, f))
        dirs = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
        return lua.table(*files), lua.table(*dirs)

    g.include = include
    g.AddCSLuaFile = lambda *a: None
    lua.execute("file = setmetatable({}, {__index = function() return _STUB end})")
    g.file.Find = find
    lua.execute("""
		GM = { FolderName = "newyorkrp", BaseClass = _STUB }
		GAMEMODE = GM
		function DeriveGamemode() end
	""")
    entry = "newyorkrp/gamemode/init.lua" if realm == "server" else "newyorkrp/gamemode/cl_init.lua"
    include(entry)
    # энтити и оружие
    for sub, var in (("entities", "ENT"), ("weapons", "SWEP")):
        d = os.path.join(GMROOT, "newyorkrp", "entities", sub)
        for f in sorted(os.listdir(d)):
            lua.execute(f"{var} = {{ Primary = {{}}, Secondary = {{}} }}")
            include(f"newyorkrp/entities/{sub}/{f}")

    if call_hooks:
        # вызов каждого хука/сетевого обработчика с заглушками: ловит обращения к несуществующим полям NYRP
        caller = lua.eval("""function(list)
			local errs = {}
			-- ограничитель: зациклившийся обработчик прерывается, а не вешает стенд
			local function guarded(fn, ...)
				local n = 0
				debug.sethook(function() n = n + 1 if n > 2000 then error("TIMEOUT: слишком долго (цикл?)") end end, "", 1000)
				local r = table.pack(pcall(fn, ...))
				debug.sethook()
				return table.unpack(r, 1, r.n)
			end
			local function bad(e)
				e = tostring(e)
				return not e:find("stub") and not e:find("TIMEOUT")
			end
			for _, h in ipairs(list) do
				local ok, e = guarded(h[3], _STUB, _STUB, _STUB, _STUB)
				if not ok and bad(e) then errs[#errs + 1] = h[1] .. "/" .. tostring(h[2]) .. ": " .. tostring(e) end
			end
			for name, fn in pairs(NETS) do
				local ok, e = guarded(fn, 0, _STUB)
				if not ok and bad(e) then errs[#errs + 1] = "net " .. name .. ": " .. tostring(e) end
			end
			for name, fn in pairs(CONCMDS) do
				local ok, e = guarded(fn, _STUB, name, {}, "")
				if not ok and bad(e) then errs[#errs + 1] = "concommand " .. name .. ": " .. tostring(e) end
			end
			local i = 1
			while i <= #TIMERS and i <= 3000 do
				local t = TIMERS[i]
				local ok, e = guarded(t[2])
				if not ok and bad(e) then errs[#errs + 1] = t[1] .. ": " .. tostring(e) end
				i = i + 1
			end
			return errs
		end""")
        for e in caller(g.HOOKS).values():
            errors.append("[хук] " + e)

    nyrp = g.NYRP
    summary = {k: (len(list(v.keys())) if lupa.lua_type(v) == "table" else v) for k, v in nyrp.items()} if nyrp else {}
    return errors, summary, len(list(g.HOOKS.keys()))


if __name__ == "__main__":
    hooks = "--hooks" in sys.argv
    bad = 0
    for realm in ("server", "client"):
        errs, summary, nh = run(realm, hooks)
        print(f"== {realm}: хуков {nh}, NYRP: " + ", ".join(f"{k}={v}" for k, v in sorted(summary.items()) if isinstance(v, int) and k[0].isupper()))
        for e in errs:
            print("  ОШИБКА:", e)
        bad += len(errs)
    print("итого ошибок:", bad)
    sys.exit(1 if bad else 0)
