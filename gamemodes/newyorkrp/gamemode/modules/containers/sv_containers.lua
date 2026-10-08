--[[
	Контейнеры на сервере: открытие с задержкой, перенос предметов, сохранение на диск.
]]

local C = NYRP.Containers
local Items = NYRP.Items
local Inv = NYRP.Inv
local DIR = "nyrp/containers"

local function size(ent)
	local def = C.TypeOf(ent)
	return def.cols * def.rows
end

local function valid(ent) return IsValid(ent) and ent:GetClass() == "nyrp_container" end

local function inReach(ply, ent)
	return valid(ent) and ply:Alive() and ent:NearestPoint(ply:EyePos()):Distance(ply:EyePos()) <= 130
end

-- ------------------------------------------------------------ сохранение --
local function savePath() return DIR .. "/" .. game.GetMap() .. ".json" end

function C.SaveAll()
	local list = {}
	for _, ent in ipairs(ents.FindByClass("nyrp_container")) do
		local slots = {}
		for i, it in pairs(ent.Slots or {}) do slots[tostring(i)] = it end
		list[#list + 1] = { type = ent:GetNW2String("nyrp.ctype", "crate"), pos = ent:GetPos(), ang = ent:GetAngles(), slots = slots }
	end
	file.CreateDir(DIR)
	file.Write(savePath(), util.TableToJSON(list, true))
end

local saveQueued = false
local function queueSave()
	if saveQueued then return end
	saveQueued = true
	timer.Simple(2, function() saveQueued = false C.SaveAll() end)
end

function C.Spawn(ctype, pos, ang, slots)
	if not C.Types[ctype] then ctype = "crate" end
	local ent = ents.Create("nyrp_container")
	ent:SetNW2String("nyrp.ctype", ctype)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent.Slots = {}
	for k, it in pairs(slots or {}) do
		local i = tonumber(k)
		if i and type(it) == "table" and Items.Get(it.id) then
			ent.Slots[i] = { id = it.id, n = math.max(1, math.floor(tonumber(it.n) or 1)), data = type(it.data) == "table" and it.data or {} }
		end
	end
	ent:Spawn()
	-- поставить на пол
	local mn = ent:OBBMins()
	ent:SetPos(pos - Vector(0, 0, mn.z))
	queueSave()
	return ent
end

local function loadAll()
	local raw = file.Read(savePath(), "DATA")
	local list = raw and util.JSONToTable(raw)
	if not list then return end
	for _, c in ipairs(list) do
		if c.pos and c.ang then C.Spawn(c.type, c.pos, c.ang, c.slots) end
	end
	saveQueued = false
	timer.Remove("nyrp.containers.save")
end
hook.Add("InitPostEntity", "nyrp.containers", function() timer.Simple(1, loadAll) end)
hook.Add("PostCleanupMap", "nyrp.containers", function() timer.Simple(0, loadAll) end)

-- ------------------------------------------------------------- открытие --
local function sendContents(ent, recipients)
	net.Start("nyrp.cont.sync")
	net.WriteEntity(ent)
	net.WriteTable(ent.Slots or {})
	net.Send(recipients)
end

local function viewers(ent)
	local out = {}
	for ply in pairs(ent.Viewers or {}) do
		if IsValid(ply) and ply.nyrpContainer == ent and inReach(ply, ent) then out[#out + 1] = ply
		else ent.Viewers[ply] = nil end
	end
	return out
end

function C.BeginOpen(ply, ent)
	if not NYRP.HasCharacter(ply) or not inReach(ply, ent) or ply.nyrpContOpening then return end
	if NYRP.Cond and NYRP.Cond.KO(ply) then return end
	ply.nyrpContOpening = { ent = ent, fin = CurTime() + C.OpenTime }
	net.Start("nyrp.cont.progress")
	net.WriteEntity(ent)
	net.WriteFloat(C.OpenTime)
	net.Send(ply)
	ent:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 60)
end

local function cancelOpen(ply)
	ply.nyrpContOpening = nil
	net.Start("nyrp.cont.progress")
	net.WriteEntity(NULL)
	net.WriteFloat(0)
	net.Send(ply)
end

local function finishOpen(ply, ent)
	ply.nyrpContOpening = nil
	ply.nyrpContainer = ent
	ent.Viewers = ent.Viewers or {}
	ent.Viewers[ply] = true
	local def = C.TypeOf(ent)
	net.Start("nyrp.cont.open")
	net.WriteEntity(ent)
	net.WriteString(def.name)
	net.WriteUInt(def.cols, 8)
	net.WriteUInt(def.rows, 8)
	net.WriteTable(ent.Slots or {})
	net.Send(ply)
	ent:EmitSound("items/ammocrate_open.wav", 60, 110)
end

hook.Add("Think", "nyrp.containers", function()
	for _, ply in ipairs(player.GetAll()) do
		local o = ply.nyrpContOpening
		if o then
			-- отошёл, отвернулся, умер — отмена
			local tr = ply:GetEyeTrace()
			if not inReach(ply, o.ent) or (tr.Entity ~= o.ent and tr.HitPos:Distance(o.ent:NearestPoint(tr.HitPos)) > 20) then
				cancelOpen(ply)
			elseif CurTime() >= o.fin then
				finishOpen(ply, o.ent)
			end
		end
		local c = ply.nyrpContainer
		if c and not inReach(ply, c) then
			ply.nyrpContainer = nil
			net.Start("nyrp.cont.close") net.Send(ply)
		end
	end
end)

net.Receive("nyrp.cont.close", function(_, ply)
	local c = ply.nyrpContainer
	ply.nyrpContainer = nil
	if valid(c) then
		if c.Viewers then c.Viewers[ply] = nil end
		c:EmitSound("items/ammocrate_close.wav", 55, 115)
	end
end)

-- --------------------------------------------------------- перенос вещей --
local function stackOrSwap(A, B, setA, setB)
	local def = Items.Get(A.id)
	if B and B.id == A.id and def.stack > 1 and B.n < def.stack then
		local put = math.min(def.stack - B.n, A.n)
		B.n = B.n + put
		A.n = A.n - put
		if A.n <= 0 then setA(nil) end
	else
		setA(B)
		setB(A)
	end
end

-- Вызывается из nyrp.inv.move, если одна из сторон — "cont".
function C.Move(ply, fk, fkey, tk, tkey)
	local ent = ply.nyrpContainer
	if not inReach(ply, ent) then return end
	local inv = Inv.Get(ply)
	local csize, isize = size(ent), Inv.Size(ply)
	local a, b = tonumber(fkey), tonumber(tkey)
	local function slotsOf(kind) return kind == "cont" and ent.Slots or inv.slots end
	local function limitOf(kind) return kind == "cont" and csize or isize end
	if (fk ~= "cont" and fk ~= "inv") or (tk ~= "cont" and tk ~= "inv") then return end
	local from, to = slotsOf(fk), slotsOf(tk)
	if not a or not from[a] or a < 1 or a > limitOf(fk) then return end
	-- в «любую» свободную ячейку
	if not b then
		for i = 1, limitOf(tk) do if not to[i] then b = i break end end
		if not b then NYRP.Notify(ply, tk == "cont" and "Контейнер полон" or "В сумке нет места", "error") return end
	end
	if b < 1 or b > limitOf(tk) or (fk == tk and a == b) then return end
	if fk == "inv" and tk == "cont" and from[a].id == "idcard" and from[a].data.char == (ply.nyrpChar and ply.nyrpChar.id) then
		-- своё удостоверение можно положить, но предупредим
		NYRP.Notify(ply, "Вы положили своё удостоверение в контейнер", "warning")
	end
	stackOrSwap(from[a], to[b], function(v) from[a] = v end, function(v) to[b] = v end)
	Inv.Sync(ply)
	sendContents(ent, viewers(ent))
	ent:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 50, math.random(95, 110))
	queueSave()
end

-- ------------------------------------------------------------ админ --
concommand.Add("nyrp_container", function(ply, _, args)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	local ctype = args[1] or "crate"
	if not C.Types[ctype] then
		NYRP.Notify(ply, "Типы: " .. table.concat(table.GetKeys(C.Types), ", "), "warning", 8)
		return
	end
	local tr = ply:GetEyeTrace()
	local ent = C.Spawn(ctype, tr.HitPos + tr.HitNormal * 2, Angle(0, ply:EyeAngles().y + 180, 0))
	undo.Create("Контейнер")
	undo.AddEntity(ent)
	undo.SetPlayer(ply)
	undo.Finish()
	NYRP.Notify(ply, "Контейнер поставлен: " .. C.Types[ctype].name, "success")
end)

concommand.Add("nyrp_container_remove", function(ply)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	local ent = ply:GetEyeTrace().Entity
	if not valid(ent) then return end
	ent:Remove()
	timer.Simple(0, C.SaveAll)
	NYRP.Notify(ply, "Контейнер удалён", "success")
end)

-- Удалили через undo / remover — тоже сохраняем.
hook.Add("EntityRemoved", "nyrp.containers", function(ent)
	if ent:GetClass() == "nyrp_container" and not ent.nyrpShutdown then timer.Simple(0, function() if not saveQueued then queueSave() end end) end
end)
hook.Add("ShutDown", "nyrp.containers", function()
	for _, ent in ipairs(ents.FindByClass("nyrp_container")) do ent.nyrpShutdown = true end
	C.SaveAll()
end)
