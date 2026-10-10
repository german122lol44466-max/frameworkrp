--[[
	3D-панели: картинка из интернета на стене (идея — 3dpanel из Helix).
	Хранятся в data/nyrp/panels/<карта>.json; клиент скачивает картинку (PNG/JPG) через http.Fetch,
	кэширует в data/nyrp/panels/ и рисует её в мире (cl_panels.lua). Отключить у себя — nyrp_panels 0.

	Команды (админ):
	  /paneladd <url картинки> [ширина] [высота]  — панель там, куда смотрите (размеры в юнитах, по умолчанию 64×64)
	  /panelremove [радиус]                       — удалить панели рядом с точкой взгляда (по умолчанию 100)
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

W.Panels = W.Panels or { list = {} }
local P = W.Panels

local MAX_PANELS = 100
local OP_FULL, OP_ADD, OP_REMOVE = 0, 1, 2

local function path() return "nyrp/panels/" .. game.GetMap() .. ".json" end
local function vt(v) return { math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2) } end
local function at(a) return { math.Round(a.p, 2), math.Round(a.y, 2), math.Round(a.r, 2) } end
local function tv(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end
local function ta(t) return Angle(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

function P.Load()
	P.list = {}
	local raw = file.Read(path(), "DATA")
	if not raw then return end
	local ok, data = pcall(util.JSONToTable, raw)
	if ok and istable(data) then P.list = data end
end

function P.Save()
	file.CreateDir("nyrp")
	file.CreateDir("nyrp/panels")
	file.Write(path(), util.TableToJSON(P.list, true))
end

local function writeEntry(d)
	net.WriteString(d.id)
	net.WriteVector(tv(d.pos))
	net.WriteAngle(ta(d.ang))
	net.WriteString(d.url)
	net.WriteUInt(math.Clamp(math.floor(tonumber(d.w) or 64), 4, 1024), 11)
	net.WriteUInt(math.Clamp(math.floor(tonumber(d.h) or 64), 4, 1024), 11)
end

function P.SendAll(ply)
	net.Start("nyrp.world.panel")
	net.WriteUInt(OP_FULL, 2)
	net.WriteUInt(#P.list, 8)
	for _, d in ipairs(P.list) do writeEntry(d) end
	if ply then net.Send(ply) else net.Broadcast() end
end

net.Receive("nyrp.world.panel", function(_, ply)
	if (ply.nyrpPanelSync or 0) > CurTime() then return end
	ply.nyrpPanelSync = CurTime() + 10
	P.SendAll(ply)
end)

local function validURL(url)
	if not isstring(url) or #url > 500 then return false end
	if not string.match(url, "^https?://[%w%-%.]+%.%a+[/%?]?") then return false end
	return not string.find(url, "[%s\"'<>]")
end

local function trace(ply)
	return util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 1200, filter = ply })
end

local function register()
	if not (NYRP.Chat and NYRP.Chat.AddCommand) then return false end

	NYRP.Chat.AddCommand("/paneladd", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local url, w, h = string.match(raw, "^%S+%s+(%S+)%s*(%d*)%s*(%d*)")
		if not url or not validURL(url) then
			NYRP.Notify(ply, "/paneladd <ссылка на картинку png/jpg> [ширина] [высота]", "warning", 8)
			return
		end
		w = math.Clamp(tonumber(w) or 64, 4, 1024)
		h = math.Clamp(tonumber(h) or w, 4, 1024)
		if #P.list >= MAX_PANELS then NYRP.Notify(ply, "На карте уже " .. MAX_PANELS .. " панелей — удалите лишние", "error") return end
		local tr = trace(ply)
		if not tr.Hit then NYRP.Notify(ply, "Посмотрите на стену", "warning") return end
		local d = {
			id = string.format("%x%04x", os.time(), math.random(0, 0xffff)),
			pos = vt(tr.HitPos + tr.HitNormal * 0.8), ang = at(W.SurfaceAngle(tr.HitNormal, ply)), url = url, w = w, h = h,
		}
		P.list[#P.list + 1] = d
		P.Save()
		net.Start("nyrp.world.panel")
		net.WriteUInt(OP_ADD, 2)
		writeEntry(d)
		net.Broadcast()
		NYRP.Notify(ply, "Панель добавлена (" .. w .. "×" .. h .. ")", "success")
		ply:EmitSound("buttons/button14.wav", 50)
	end)

	NYRP.Chat.AddCommand("/panelremove", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local radius = math.Clamp(tonumber(string.match(raw, "^%S+%s+(%d+)")) or 100, 8, 2000)
		local pos = trace(ply).HitPos
		local removed = {}
		for i = #P.list, 1, -1 do
			if tv(P.list[i].pos):Distance(pos) <= radius then
				removed[#removed + 1] = P.list[i].id
				table.remove(P.list, i)
			end
		end
		if #removed == 0 then NYRP.Notify(ply, "Рядом (радиус " .. radius .. ") панелей нет", "warning") return end
		P.Save()
		net.Start("nyrp.world.panel")
		net.WriteUInt(OP_REMOVE, 2)
		net.WriteUInt(#removed, 8)
		for _, id in ipairs(removed) do net.WriteString(id) end
		net.Broadcast()
		NYRP.Notify(ply, "Удалено панелей: " .. #removed, "success")
	end)
	return true
end
if not register() then hook.Add("Initialize", "nyrp.panel.cmd", function(...) register(...) end) end

P.Load()
