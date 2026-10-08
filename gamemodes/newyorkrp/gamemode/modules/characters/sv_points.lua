--[[
	Точки камер для интро, главного меню, выбора и создания персонажа.
	Сохраняются в data/nyrp/points/<карта>.json — переживают перезапуски сервера.

	Команды (только суперадмин, из консоли в игре):
	  nyrp_point intro add|clear      — точка пролёта интро (камера = ваш взгляд)
	  nyrp_point menu set|clear       — камера главного меню
	  nyrp_point chars set|clear      — камера выбора персонажей
	  nyrp_point spot add|clear       — место, где стоит персонаж (ваши ноги и поворот)
	  nyrp_point create add|clear     — точки пролёта к созданию персонажа
	  nyrp_points                     — что уже задано
	  nyrp_chareditor                 — редактор расстановки моделей (клиент)
]]

NYRP.Points = NYRP.Points or {}
local P = NYRP.Points

local function path()
	return "nyrp/points/" .. game.GetMap() .. ".json"
end

local function vecT(v) return { v.x, v.y, v.z } end
local function angT(a) return { a.p, a.y, a.r } end

function P.Load()
	P.Data = { intro = {}, menu = nil, chars = nil, spots = {}, create = {} }
	local raw = file.Read(path(), "DATA")
	if raw then
		local ok, data = pcall(util.JSONToTable, raw)
		if ok and data then table.Merge(P.Data, data) end
	end
end

function P.Save()
	file.CreateDir("nyrp")
	file.CreateDir("nyrp/points")
	file.Write(path(), util.TableToJSON(P.Data, true))
end

-- Персонажи через меню доступны, только если поставлены камеры меню и выбора и хотя бы одно место.
function P.Configured()
	return P.Data.menu ~= nil and P.Data.chars ~= nil and #P.Data.spots > 0
end

function P.Send(ply)
	net.Start("nyrp.points")
	net.WriteTable(P.Data)
	net.WriteBool(P.Configured())
	if ply then net.Send(ply) else net.Broadcast() end
end

local function cam(ply)
	return { pos = vecT(ply:EyePos()), ang = angT(ply:EyeAngles()) }
end

concommand.Add("nyrp_point", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if not IsValid(ply) then print("Команда выполняется из игры") return end
	local kind, action = args[1], args[2] or "add"
	local msg
	if kind == "intro" or kind == "create" then
		if action == "clear" then P.Data[kind] = {} msg = "очищено"
		else table.insert(P.Data[kind], cam(ply)) msg = "точка #" .. #P.Data[kind] end
	elseif kind == "menu" or kind == "chars" then
		if action == "clear" then P.Data[kind] = nil msg = "очищено"
		else P.Data[kind] = cam(ply) msg = "камера сохранена" end
	elseif kind == "spot" then
		if action == "clear" then P.Data.spots = {} msg = "очищено"
		else
			table.insert(P.Data.spots, { pos = vecT(ply:GetPos()), ang = { 0, ply:EyeAngles().y, 0 } })
			msg = "место #" .. #P.Data.spots
		end
	else
		NYRP.Notify(ply, "Использование: nyrp_point intro|menu|chars|spot|create add|set|clear", "warning", 8)
		return
	end
	P.Save()
	P.Send()
	NYRP.Notify(ply, "Точки «" .. kind .. "»: " .. msg, "success")
end)

concommand.Add("nyrp_points", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local d = P.Data
	local text = string.format("Интро: %d, меню: %s, выбор: %s, мест: %d, создание: %d. Настроено: %s",
		#d.intro, d.menu and "да" or "нет", d.chars and "да" or "нет", #d.spots, #d.create, P.Configured() and "да" or "нет")
	if IsValid(ply) then NYRP.Notify(ply, text, "info", 10) else print(text) end
end)

-- Сохранение из редактора расстановки.
net.Receive("nyrp.points.save", function(_, ply)
	if not ply:IsSuperAdmin() then return end
	local spots = net.ReadTable()
	local clean = {}
	for i, s in ipairs(spots) do
		if i > 16 then break end
		if istable(s.pos) and istable(s.ang) then
			clean[#clean + 1] = { pos = { tonumber(s.pos[1]) or 0, tonumber(s.pos[2]) or 0, tonumber(s.pos[3]) or 0 },
				ang = { 0, tonumber(s.ang[2]) or 0, 0 } }
		end
	end
	P.Data.spots = clean
	P.Save()
	P.Send()
	NYRP.Notify(ply, "Расстановка персонажей сохранена (" .. #clean .. ")", "success")
end)

-- Камера в меню должна видеть сущности рядом с точками.
hook.Add("SetupPlayerVisibility", "nyrp.points", function(ply)
	if NYRP.HasCharacter(ply) then return end
	for _, key in ipairs({ "menu", "chars" }) do
		local c = P.Data[key]
		if c then AddOriginToPVS(Vector(c.pos[1], c.pos[2], c.pos[3])) end
	end
	for _, c in ipairs(P.Data.intro) do AddOriginToPVS(Vector(c.pos[1], c.pos[2], c.pos[3])) end
end)

P.Load()
