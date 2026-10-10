--[[
	3D-текст на стенах (идея — 3dtext из Helix / parallax).
	Хранится в data/nyrp/texts/<карта>.json, рисуется у всех в мире с затуханием по дистанции (cl_text.lua).

	Команды (админ):
	  /textadd [размер] <текст>  — надпись там, куда смотрите (по нормали поверхности). Размер 0.25–5, по умолчанию 1.
	                               Перенос строки — \n. Цвет — заранее через /textcolor.
	  /textcolor <r g b | #rrggbb | reset> — цвет следующих надписей
	  /textremove [радиус]       — удалить надписи рядом с точкой взгляда (по умолчанию 100)
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

W.Texts = W.Texts or { list = {} }
local T = W.Texts

local MAX_TEXTS, MAX_LEN, MAX_LINES = 300, 300, 8
local OP_FULL, OP_ADD, OP_REMOVE = 0, 1, 2

local function path() return "nyrp/texts/" .. game.GetMap() .. ".json" end
local function vt(v) return { math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2) } end
local function at(a) return { math.Round(a.p, 2), math.Round(a.y, 2), math.Round(a.r, 2) } end
local function tv(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end
local function ta(t) return Angle(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

function T.Load()
	T.list = {}
	local raw = file.Read(path(), "DATA")
	if not raw then return end
	local ok, data = pcall(util.JSONToTable, raw)
	if ok and istable(data) then T.list = data end
end

function T.Save()
	file.CreateDir("nyrp")
	file.CreateDir("nyrp/texts")
	file.Write(path(), util.TableToJSON(T.list, true))
end

local function writeEntry(d)
	net.WriteString(d.id)
	net.WriteVector(tv(d.pos))
	net.WriteAngle(ta(d.ang))
	net.WriteString(d.text or "")
	net.WriteFloat(tonumber(d.scale) or 1)
	local c = d.col or {}
	net.WriteColor(Color(c[1] or 255, c[2] or 255, c[3] or 255), false)
end

function T.SendAll(ply)
	net.Start("nyrp.world.text")
	net.WriteUInt(OP_FULL, 2)
	net.WriteUInt(#T.list, 10)
	for _, d in ipairs(T.list) do writeEntry(d) end
	if ply then net.Send(ply) else net.Broadcast() end
end

-- Клиент просит список после загрузки.
net.Receive("nyrp.world.text", function(_, ply)
	if (ply.nyrpTextSync or 0) > CurTime() then return end
	ply.nyrpTextSync = CurTime() + 10
	T.SendAll(ply)
end)

function T.Add(pos, ang, text, scale, col)
	local d = {
		id = string.format("%x%04x", os.time(), math.random(0, 0xffff)),
		pos = vt(pos), ang = at(ang), text = text, scale = scale, col = { col.r, col.g, col.b },
	}
	T.list[#T.list + 1] = d
	T.Save()
	net.Start("nyrp.world.text")
	net.WriteUInt(OP_ADD, 2)
	writeEntry(d)
	net.Broadcast()
	return d
end

function T.RemoveNear(pos, radius)
	local removed = {}
	for i = #T.list, 1, -1 do
		if tv(T.list[i].pos):Distance(pos) <= radius then
			removed[#removed + 1] = T.list[i].id
			table.remove(T.list, i)
		end
	end
	if #removed == 0 then return 0 end
	T.Save()
	net.Start("nyrp.world.text")
	net.WriteUInt(OP_REMOVE, 2)
	net.WriteUInt(#removed, 10)
	for _, id in ipairs(removed) do net.WriteString(id) end
	net.Broadcast()
	return #removed
end

-- Угол надписи по нормали поверхности (на полу — повернуть к игроку).
function W.SurfaceAngle(normal, ply)
	if math.abs(normal.z) > 0.7 then
		local yaw = ply:EyeAngles().y - 90
		if normal.z > 0 then return Angle(0, yaw, 0) end
		return Angle(0, yaw, 180)
	end
	local ang = normal:Angle()
	ang:RotateAroundAxis(ang:Up(), 90)
	ang:RotateAroundAxis(ang:Forward(), 90)
	return ang
end

local function trace(ply)
	return util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 1200, filter = ply })
end

-- Разбор цвета: "r g b", "#rrggbb".
local function parseColor(s)
	s = string.Trim(s or "")
	local hex = string.match(s, "^#?(%x%x%x%x%x%x)$")
	if hex then
		return Color(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
	end
	local r, g, b = string.match(s, "^(%d+)[%s,]+(%d+)[%s,]+(%d+)$")
	if r then
		return Color(math.Clamp(tonumber(r), 0, 255), math.Clamp(tonumber(g), 0, 255), math.Clamp(tonumber(b), 0, 255))
	end
end
W.ParseColor = parseColor

local function register()
	if not (NYRP.Chat and NYRP.Chat.AddCommand) then return false end

	NYRP.Chat.AddCommand("/textadd", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local rest = string.Trim(string.match(raw, "^%S+%s+(.+)$") or "")
		local scale = 1
		local num, text = string.match(rest, "^(%d+%.?%d*)%s+(.+)$")
		if num and text then scale = math.Clamp(tonumber(num) or 1, 0.25, 5) rest = text end
		rest = string.gsub(rest, "\\n", "\n")
		local lines = {}
		for raw_line in string.gmatch(rest .. "\n", "(.-)\n") do
			if #lines < MAX_LINES then lines[#lines + 1] = string.Trim(raw_line) end
		end
		while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
		local final = table.concat(lines, "\n")
		if final == "" then
			NYRP.Notify(ply, "/textadd [размер] <текст>. Перенос строки — \\n, цвет — /textcolor r g b", "warning", 8)
			return
		end
		if utf8.len(final) and utf8.len(final) > MAX_LEN then
			final = string.sub(final, 1, utf8.offset(final, MAX_LEN + 1) - 1)
		end
		if #T.list >= MAX_TEXTS then NYRP.Notify(ply, "На карте уже " .. MAX_TEXTS .. " надписей — удалите лишние", "error") return end
		local tr = trace(ply)
		if not tr.Hit then NYRP.Notify(ply, "Посмотрите на стену или пол", "warning") return end
		local ang = W.SurfaceAngle(tr.HitNormal, ply)
		T.Add(tr.HitPos + tr.HitNormal * 0.6, ang, final, scale, ply.nyrpTextColor or color_white)
		NYRP.Notify(ply, "Надпись добавлена (" .. #T.list .. " на карте)", "success")
		ply:EmitSound("buttons/button14.wav", 50)
	end)

	NYRP.Chat.AddCommand("/textcolor", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local arg = string.Trim(string.match(raw, "^%S+%s+(.+)$") or "")
		if arg == "reset" or arg == "сброс" then
			ply.nyrpTextColor = nil
			NYRP.Notify(ply, "Цвет надписей: белый", "success")
			return
		end
		local col = parseColor(arg)
		if not col then NYRP.Notify(ply, "/textcolor <r g b> или <#rrggbb> или reset", "warning", 6) return end
		ply.nyrpTextColor = col
		NYRP.Notify(ply, string.format("Цвет следующих надписей: %d %d %d", col.r, col.g, col.b), "success")
	end)

	NYRP.Chat.AddCommand("/textremove", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local radius = math.Clamp(tonumber(string.match(raw, "^%S+%s+(%d+)")) or 100, 8, 2000)
		local tr = trace(ply)
		local n = T.RemoveNear(tr.HitPos, radius)
		if n > 0 then
			NYRP.Notify(ply, "Удалено надписей: " .. n, "success")
		else
			NYRP.Notify(ply, "Рядом (радиус " .. radius .. ") надписей нет", "warning")
		end
	end)
	return true
end
if not register() then hook.Add("Initialize", "nyrp.text.cmd", register) end

T.Load()
