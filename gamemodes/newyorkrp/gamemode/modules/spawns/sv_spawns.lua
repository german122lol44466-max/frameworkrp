--[[
	Точки появления по ролям (идея — spawns / spawnsaver из Helix, sh_spawn_save из parallax).
	Хранятся в data/nyrp/spawns/<карта>.json: { ["*"] = общие, [id роли] = точки роли }.

	При возрождении персонаж появляется на свободной точке своей роли, если их нет — на общей,
	если и общих нет — как раньше (стандартный спавн карты). В КПЗ сажает модуль полиции — его не трогаем.

	Позиция персонажа: при каждом сохранении персонажа (выход, смена персонажа, автосохранение) запоминается
	c.flags.lastPos / lastAng / lastMap. На первом спавне после загрузки персонаж появляется там же,
	если карта та же и место свободно (TraceHull), иначе — обычный спавн.

	Команды (админ):
	  /spawnadd [роль|all]  — точка под вашими ногами (по умолчанию — общая)
	  /spawnremove [радиус] — удалить точки рядом с вами (по умолчанию 120)
	  /spawns               — показать / скрыть маркеры точек
]]

NYRP.Spawns = NYRP.Spawns or {}
local S = NYRP.Spawns

S.Data = S.Data or {}

local ALL = "*"
local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)

local function path() return "nyrp/spawns/" .. game.GetMap() .. ".json" end
local function tv(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

function S.Load()
	S.Data = {}
	local raw = file.Read(path(), "DATA")
	if not raw then return end
	local ok, data = pcall(util.JSONToTable, raw)
	if ok and istable(data) then S.Data = data end
end

function S.Save()
	file.CreateDir("nyrp")
	file.CreateDir("nyrp/spawns")
	file.Write(path(), util.TableToJSON(S.Data, true))
end

function S.Count()
	local n = 0
	for _, list in pairs(S.Data) do n = n + #list end
	return n
end

-- Свободно ли место для игрока.
function S.IsFree(pos, ply)
	if not util.IsInWorld(pos + Vector(0, 0, 36)) then return false end
	local tr = util.TraceHull({
		start = pos + Vector(0, 0, 4), endpos = pos + Vector(0, 0, 4),
		mins = HULL_MIN, maxs = HULL_MAX, filter = ply, mask = MASK_PLAYERSOLID,
	})
	return not tr.Hit and not tr.StartSolid
end

local function roleOf(ply)
	local c = ply.nyrpChar
	local role = c and c.flags and c.flags.role
	if not role or role == "" then role = NYRP.Roles and NYRP.Roles.Default or "" end
	return role
end

-- Свободная точка для роли игрока (или общая), nil — точек нет / все заняты.
function S.Pick(ply)
	local list = S.Data[roleOf(ply)]
	if not list or #list == 0 then list = S.Data[ALL] end
	if not list or #list == 0 then return nil end
	local order = {}
	for i = 1, #list do order[i] = i end
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	for _, i in ipairs(order) do
		local p = list[i]
		local pos = tv(p.pos or {})
		if S.IsFree(pos, ply) then return pos, tonumber(p.yaw) or 0 end
	end
end

local function place(ply, pos, yaw)
	ply:SetPos(pos)
	ply:SetEyeAngles(Angle(0, yaw or 0, 0))
	ply:SetVelocity(-ply:GetVelocity())
end

-- ------------------------------------------------------ позиция персонажа --
-- Запоминаем позицию, только если персонаж уже стоит в мире (не сразу после загрузки другого).
function S.Remember(ply)
	local c = IsValid(ply) and ply.nyrpChar
	if not c or ply.nyrpPosChar ~= c.id then return end
	c.flags = c.flags or {}
	local jailed = (tonumber(c.flags.jailUntil) or 0) > os.time()
	if not ply:Alive() or jailed or ply:GetMoveType() == MOVETYPE_NOCLIP then
		c.flags.lastPos, c.flags.lastAng, c.flags.lastMap = nil, nil, nil
		return
	end
	local p = ply:GetPos()
	if IsValid(ply:GetVehicle()) then p = ply:GetVehicle():GetPos() + Vector(0, 0, 40) end
	c.flags.lastPos = { math.Round(p.x, 1), math.Round(p.y, 1), math.Round(p.z, 1) }
	c.flags.lastAng = math.Round(ply:EyeAngles().y, 1)
	c.flags.lastMap = game.GetMap()
end

-- NYRP.Chars.Save вызывается при выходе, смене персонажа, в меню и в автосохранении —
-- оборачиваем, чтобы перед записью в базу положить позицию в c.flags.
local function wrapSave()
	local Chars = NYRP.Chars
	if not Chars or not isfunction(Chars.Save) or Chars.nyrpPosWrapped then return end
	Chars.nyrpPosWrapped = true
	local orig = Chars.Save
	Chars.Save = function(ply, ...)
		if IsValid(ply) then ProtectedCall(function() S.Remember(ply) end) end
		return orig(ply, ...)
	end
end
wrapSave()
hook.Add("Initialize", "nyrp.spawns.save", function(...) wrapSave(...) end)

local function restoreLast(ply, c)
	local f = c.flags or {}
	if f.lastMap ~= game.GetMap() or not istable(f.lastPos) then return false end
	if (tonumber(f.jailUntil) or 0) > os.time() then return false end
	local pos = tv(f.lastPos)
	if not S.IsFree(pos, ply) then return false end
	place(ply, pos, tonumber(f.lastAng) or 0)
	return true
end

-- Персонаж без персонажа (меню) — следующий вход считается «первым спавном».
hook.Add("PlayerSpawn", "nyrp.spawns", function(ply)
	if not ply.nyrpChar then ply.nyrpPosChar = nil end
end)

hook.Add("NYRP.PlayerSpawned", "nyrp.spawns", function(ply)
	local c = ply.nyrpChar
	if not c then return end
	local first = ply.nyrpPosChar ~= c.id
	ply.nyrpPosChar = c.id
	if first and restoreLast(ply, c) then return end
	-- в КПЗ посадит модуль полиции
	if c.flags and (tonumber(c.flags.jailUntil) or 0) > os.time() then return end
	local pos, yaw = S.Pick(ply)
	if pos then place(ply, pos, yaw) end
end)

-- ----------------------------------------------------------- маркеры --
local function sendTo(ply, show)
	net.Start("nyrp.spawns.show")
	net.WriteBool(show)
	if show then
		local flat = {}
		for role, list in pairs(S.Data) do
			for _, p in ipairs(list) do flat[#flat + 1] = { role, tv(p.pos or {}), tonumber(p.yaw) or 0 } end
		end
		net.WriteUInt(math.min(#flat, 1023), 10)
		for i = 1, math.min(#flat, 1023) do
			net.WriteString(flat[i][1])
			net.WriteVector(flat[i][2])
			net.WriteFloat(flat[i][3])
		end
	end
	net.Send(ply)
end

local function refreshViewers()
	for _, p in ipairs(player.GetAll()) do
		if p.nyrpSpawnsShown and p:IsAdmin() then sendTo(p, true) end
	end
end

-- Роль по id или по названию (без регистра).
local function resolveRole(arg)
	arg = string.Trim(arg or "")
	if arg == "" or arg == "all" or arg == "*" or arg == "все" then return ALL end
	local R = NYRP.Roles and NYRP.Roles.List or {}
	if R[arg] then return arg end
	local low = NYRP.World and NYRP.World.Lower and NYRP.World.Lower(arg) or string.lower(arg)
	for id, r in pairs(R) do
		local name = NYRP.World and NYRP.World.Lower and NYRP.World.Lower(r.Name or "") or string.lower(r.Name or "")
		if string.lower(id) == low or name == low then return id end
	end
end

local function roleName(id)
	if id == ALL then return "общая" end
	local r = NYRP.Roles and NYRP.Roles.List[id]
	return r and r.Name or id
end

local function register()
	if not (NYRP.Chat and NYRP.Chat.AddCommand) then return false end

	NYRP.Chat.AddCommand("/spawnadd", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local role = resolveRole(string.match(raw, "^%S+%s+(.+)$"))
		if not role then
			local ids = {}
			for id in pairs(NYRP.Roles and NYRP.Roles.List or {}) do ids[#ids + 1] = id end
			table.sort(ids)
			NYRP.Notify(ply, "Нет такой роли. Роли: all, " .. table.concat(ids, ", "), "error", 8)
			return
		end
		local p = ply:GetPos()
		S.Data[role] = S.Data[role] or {}
		table.insert(S.Data[role], { pos = { math.Round(p.x, 1), math.Round(p.y, 1), math.Round(p.z + 2, 1) }, yaw = math.Round(ply:EyeAngles().y, 1) })
		S.Save()
		NYRP.Notify(ply, "Точка появления (" .. roleName(role) .. ") #" .. #S.Data[role] .. " добавлена", "success")
		ply:EmitSound("buttons/button14.wav", 50)
		refreshViewers()
	end)

	NYRP.Chat.AddCommand("/spawnremove", function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local radius = math.Clamp(tonumber(string.match(raw, "^%S+%s+(%d+)")) or 120, 8, 4000)
		local pos, n = ply:GetPos(), 0
		for role, list in pairs(S.Data) do
			for i = #list, 1, -1 do
				if tv(list[i].pos or {}):Distance(pos) <= radius then
					table.remove(list, i)
					n = n + 1
				end
			end
			if #list == 0 then S.Data[role] = nil end
		end
		if n == 0 then NYRP.Notify(ply, "Рядом (радиус " .. radius .. ") точек нет", "warning") return end
		S.Save()
		NYRP.Notify(ply, "Удалено точек появления: " .. n, "success")
		refreshViewers()
	end)

	NYRP.Chat.AddCommand("/spawns", function(ply)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		ply.nyrpSpawnsShown = not ply.nyrpSpawnsShown
		sendTo(ply, ply.nyrpSpawnsShown)
		if ply.nyrpSpawnsShown then
			NYRP.Notify(ply, "Точек появления: " .. S.Count() .. ". Скрыть — /spawns", "info", 6)
		end
	end)
	return true
end
if not register() then hook.Add("Initialize", "nyrp.spawns.cmd", function(...) register(...) end) end

S.Load()
