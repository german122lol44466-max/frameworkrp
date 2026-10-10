--[[
	Постоянные пропы карты (идея — persistence из Helix).
	Сохраняются в data/nyrp/persist/<карта>.json: модель, позиция, углы, материал, цвет, skin, бодигруппы, заморожен ли.
	Восстанавливаются при старте сервера и после очистки карты. Игроки их не трогают; админ может двигать
	физганом — новое положение сохраняется само (после отпускания / заморозки / работы тулганом).

	Команды (админ):
	  /persist    — сделать постоянным проп, на который смотрите (повторно — пересохранить)
	  /unpersist  — убрать из сохранения (проп остаётся до очистки карты)
	У админа с физганом постоянные пропы подсвечиваются (cl_persist.lua).
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

W.Persist = W.Persist or { list = {}, ents = {} }
local P = W.Persist

local allowed = { prop_physics = true, prop_physics_multiplayer = true, prop_dynamic = true, prop_ragdoll = false }

local function path() return "nyrp/persist/" .. game.GetMap() .. ".json" end
local function vt(v) return { math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2) } end
local function at(a) return { math.Round(a.p, 2), math.Round(a.y, 2), math.Round(a.r, 2) } end
local function tv(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end
local function ta(t) return Angle(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

function P.Load()
	P.list = {}
	local raw = file.Read(path(), "DATA")
	if raw then
		local ok, data = pcall(util.JSONToTable, raw)
		if ok and istable(data) then P.list = data end
	end
end

function P.Save()
	file.CreateDir("nyrp")
	file.CreateDir("nyrp/persist")
	file.Write(path(), util.TableToJSON(P.list, true))
end

-- Отложенное сохранение (пачка изменений подряд — одна запись на диск).
function P.SaveSoon()
	timer.Create("nyrp.persist.save", 1, 1, P.Save)
end

local function newID()
	return string.format("%x%04x", os.time(), math.random(0, 0xffff))
end

-- Снимок пропа.
local function snapshot(ent)
	local phys = ent:GetPhysicsObject()
	local col = ent:GetColor()
	local bg = {}
	for _, b in ipairs(ent:GetBodyGroups() or {}) do
		local v = ent:GetBodygroup(b.id)
		if v and v > 0 then bg[tostring(b.id)] = v end
	end
	return {
		class = ent:GetClass(), model = ent:GetModel(), pos = vt(ent:GetPos()), ang = at(ent:GetAngles()),
		mat = ent:GetMaterial() ~= "" and ent:GetMaterial() or nil, skin = ent:GetSkin() > 0 and ent:GetSkin() or nil,
		col = { col.r, col.g, col.b, col.a }, render = ent:GetRenderMode() ~= RENDERMODE_NORMAL and ent:GetRenderMode() or nil,
		frozen = not IsValid(phys) or not phys:IsMotionEnabled(), bg = next(bg) and bg or nil,
		scale = (ent:GetModelScale() or 1) ~= 1 and ent:GetModelScale() or nil,
	}
end

local function find(id)
	for i, d in ipairs(P.list) do
		if d.id == id then return i, d end
	end
end

local function mark(ent, id)
	ent.nyrpPersistID = id
	ent:SetNW2Bool("nyrp.persist", true)
	P.ents[id] = ent
	if W.ClearOwner then W.ClearOwner(ent) end
end

local function spawnOne(d)
	if not isstring(d.model) or not util.IsValidModel(d.model) then return end
	local ent = ents.Create(allowed[d.class or ""] and d.class or "prop_physics")
	if not IsValid(ent) then return end
	ent:SetModel(d.model)
	ent:SetPos(tv(d.pos or {}))
	ent:SetAngles(ta(d.ang or {}))
	ent:Spawn()
	ent:Activate()
	if d.mat then ent:SetMaterial(d.mat) end
	if d.skin then ent:SetSkin(d.skin) end
	if d.render then ent:SetRenderMode(d.render) end
	if istable(d.col) then ent:SetColor(Color(d.col[1] or 255, d.col[2] or 255, d.col[3] or 255, d.col[4] or 255)) end
	if d.scale then ent:SetModelScale(d.scale, 0) end
	for id, v in pairs(d.bg or {}) do ent:SetBodygroup(tonumber(id) or 0, v) end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then
		if d.frozen ~= false then phys:EnableMotion(false) else phys:Wake() end
	end
	mark(ent, d.id)
	return ent
end

function P.SpawnAll()
	for id, ent in pairs(P.ents) do
		if IsValid(ent) then ent:Remove() end
		P.ents[id] = nil
	end
	local n = 0
	for _, d in ipairs(P.list) do
		if not d.id then d.id = newID() end
		if spawnOne(d) then n = n + 1 end
	end
	if n > 0 then NYRP.Print("Постоянные пропы: восстановлено " .. n) end
end

-- Обновить запись по текущему состоянию пропа.
function P.Update(ent)
	if not IsValid(ent) or not ent.nyrpPersistID then return end
	local i = find(ent.nyrpPersistID)
	if not i then return end
	local d = snapshot(ent)
	d.id = ent.nyrpPersistID
	P.list[i] = d
	P.SaveSoon()
end

function P.Add(ent)
	if ent.nyrpPersistID and find(ent.nyrpPersistID) then P.Update(ent) return false end
	local d = snapshot(ent)
	d.id = newID()
	P.list[#P.list + 1] = d
	mark(ent, d.id)
	P.SaveSoon()
	return true
end

function P.Remove(ent)
	local id = ent.nyrpPersistID
	if not id then return false end
	local i = find(id)
	if i then table.remove(P.list, i) end
	P.ents[id] = nil
	ent.nyrpPersistID = nil
	ent:SetNW2Bool("nyrp.persist", false)
	P.SaveSoon()
	return true
end

local function aimed(ply)
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 1500, filter = ply })
	local ent = tr.Entity
	if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then return nil end
	return ent
end

local function register()
	if not (NYRP.Chat and NYRP.Chat.AddCommand) then return false end
	NYRP.Chat.AddCommand("/persist", function(ply)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local ent = aimed(ply)
		if not ent then NYRP.Notify(ply, "Посмотрите на проп", "warning") return end
		if not allowed[ent:GetClass()] then NYRP.Notify(ply, "Постоянными можно делать только пропы (prop_physics)", "error") return end
		local fresh = P.Add(ent)
		NYRP.Notify(ply, fresh and "Проп сохранён для карты" or "Положение постоянного пропа пересохранено", "success")
		ply:EmitSound("buttons/button14.wav", 50)
	end)
	NYRP.Chat.AddCommand("/unpersist", function(ply)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local ent = aimed(ply)
		if not ent or not ent.nyrpPersistID then NYRP.Notify(ply, "Посмотрите на постоянный проп", "warning") return end
		P.Remove(ent)
		W.SetOwner(ent, ply, "prop")
		NYRP.Notify(ply, "Проп больше не сохраняется (теперь он ваш)", "success")
		ply:EmitSound("buttons/button16.wav", 50)
	end)
	return true
end
if not register() then hook.Add("Initialize", "nyrp.persist.cmd", function(...) register(...) end) end

-- Админ подвинул / заморозил / поработал тулганом — пересохраняем.
hook.Add("PhysgunDrop", "nyrp.persist", function(ply, ent)
	if IsValid(ent) and ent.nyrpPersistID and ply:IsAdmin() then
		timer.Simple(0.3, function() P.Update(ent) end)
	end
end)
hook.Add("OnPhysgunFreeze", "nyrp.persist", function(_, _, ent, ply)
	if IsValid(ent) and ent.nyrpPersistID and IsValid(ply) and ply:IsAdmin() then
		timer.Simple(0.1, function() P.Update(ent) end)
	end
end)
hook.Add("CanTool", "nyrp.persist.upd", function(ply, tr)
	local ent = tr and tr.Entity
	if IsValid(ent) and ent.nyrpPersistID and ply:IsAdmin() then
		timer.Simple(0.3, function() P.Update(ent) end)
	end
end)

P.Load()
hook.Add("InitPostEntity", "nyrp.persist", function() timer.Simple(1, P.SpawnAll) end)
hook.Add("PostCleanupMap", "nyrp.persist", function() timer.Simple(0.2, P.SpawnAll) end)
hook.Add("ShutDown", "nyrp.persist", function()
	for _, ent in pairs(P.ents) do
		if IsValid(ent) then
			local i = find(ent.nyrpPersistID)
			if i then
				local d = snapshot(ent)
				d.id = ent.nyrpPersistID
				P.list[i] = d
			end
		end
	end
	P.Save()
end)
