--[[
	scp_edit — редактор точек сюжета (суперадмин, хост или одиночная игра).

	Включает полёт и показывает все точки: сюжетные (высадка, цели, предметы, чекпоинты) и точки появления
	групп врагов. Изменения действуют сразу; «Сохранить» пишет файл data/whitesilence/points/<карта>.json.
	Враги редактора не видят.
]]

local S = WS.Story
local P = S.P
local L = WS.Lobby

util.AddNetworkString("ws.edit.state")
util.AddNetworkString("ws.edit.op")

P.Unsaved = false

local function canEdit(ply)
	return IsValid(ply) and (ply:IsSuperAdmin() or game.SinglePlayer() or ply:IsListenServerHost())
end

local function editors()
	local out = {}
	for _, p in ipairs(player.GetAll()) do if p.wsEditing then out[#out + 1] = p end end
	return out
end

local function sendData(to)
	net.Start("ws.edit.state")
	net.WriteBool(true)
	net.WriteBool(P.Unsaved)
	net.WriteUInt(S.State.running and S.State.ch or 0, 6)
	net.WriteUInt(S.State.step, 6)
	for _, def in ipairs(S.Points) do
		local pos, yaw, r = P.Get(def.id)
		net.WriteVector(pos)
		net.WriteFloat(yaw)
		net.WriteUInt(math.Clamp(math.floor(r or 0), 0, 4095), 12)
		net.WriteBool(P.IsSet(def.id))
	end
	for _, g in ipairs(S.Groups) do
		local spots = P.GroupSpots(g.id)
		net.WriteUInt(#spots, 8)
		for _, sp in ipairs(spots) do
			net.WriteVector(sp.pos)
			net.WriteFloat(sp.yaw)
		end
	end
	net.Send(to)
end

local function refresh()
	local list = editors()
	if #list > 0 then sendData(list) end
	S.Dirty()
end

local function setEditing(ply, on)
	ply.wsEditing = on
	if on then
		ply:Freeze(false)
		ply:SetMoveType(MOVETYPE_NOCLIP)
		ply:GodEnable()
		sendData(ply)
		ply:ChatPrint("[scp_edit] Удерживайте C — панель редактора. Повторный scp_edit — выход.")
	else
		net.Start("ws.edit.state")
		net.WriteBool(false)
		net.Send(ply)
		ply:SetMoveType(MOVETYPE_WALK)
		if L.InGame(ply) then ply:GodDisable() else L.ApplyMenuState(ply) end
	end
end

concommand.Add("scp_edit", function(ply)
	if not canEdit(ply) then
		if IsValid(ply) then ply:ChatPrint("scp_edit доступен только суперадмину.") end
		return
	end
	setEditing(ply, not ply.wsEditing)
end)

-- в меню редактор не сбрасывается заморозкой
hook.Add("PlayerSpawn", "ws.edit", function(ply)
	if ply.wsEditing then timer.Simple(0.1, function() if IsValid(ply) and ply.wsEditing then setEditing(ply, true) end end) end
end)

local function readVec()
	local v = net.ReadVector()
	if v.x ~= v.x or math.abs(v.x) > 65536 or math.abs(v.y) > 65536 or math.abs(v.z) > 65536 then return nil end
	return v
end

local OPS = {}

OPS.set = function(ply)
	local id, pos, yaw = net.ReadString(), readVec(), net.ReadFloat()
	local def = S.PointById[id]
	if not def or not pos then return end
	local old = P.Data.points[id]
	P.Data.points[id] = { pos = pos, yaw = math.NormalizeAngle(yaw), r = old and old.r or def.r }
	return true
end

OPS.radius = function(ply)
	local id, r = net.ReadString(), net.ReadUInt(12)
	local def = S.PointById[id]
	if not def then return end
	local pos, yaw = P.Get(id)
	P.Data.points[id] = { pos = pos, yaw = yaw, r = math.Clamp(r, 50, 3000) }
	return true
end

OPS.reset = function(ply)
	local id = net.ReadString()
	P.Data.points[id] = nil
	P.Auto[id] = nil
	return true
end

OPS.gadd = function(ply)
	local gid, pos, yaw = net.ReadString(), readVec(), net.ReadFloat()
	if not S.GroupById[gid] or not pos then return end
	P.Data.groups[gid] = P.Data.groups[gid] or {}
	if #P.Data.groups[gid] >= 64 then return end
	table.insert(P.Data.groups[gid], { pos = pos, yaw = math.NormalizeAngle(yaw) })
	return true
end

OPS.gdel = function(ply)
	local gid, idx = net.ReadString(), net.ReadUInt(8)
	local list = P.Data.groups[gid]
	if not list or not list[idx] then return end
	table.remove(list, idx)
	return true
end

OPS.gclear = function(ply)
	local gid = net.ReadString()
	if not S.GroupById[gid] then return end
	P.Data.groups[gid] = {}
	return true
end

OPS.save = function(ply)
	P.Save()
	P.Unsaved = false
	ply:ChatPrint("[scp_edit] Сохранено: data/whitesilence/points/" .. game.GetMap() .. ".json")
	refresh()
end

OPS.reload = function(ply)
	P.Load()
	P.Unsaved = false
	refresh()
end

OPS.auto = function(ply)
	local n = P.FillAuto()
	ply:ChatPrint("[scp_edit] Подобрано автоматически: " .. n .. ". Проверьте и сохраните.")
	return true
end

OPS.story = function(ply)
	local ch = net.ReadUInt(6)
	if ch == 0 then S.Stop(false) refresh() return end
	S.Stop(true)
	if ch == 1 then S.Stats = { t0 = CurTime(), kills = 0, deaths = 0 } end
	S.StartChapter(ch)
	refresh()
end

OPS.test = function(ply)
	local gid = net.ReadString()
	if not S.GroupById[gid] then return end
	S.Spawn(gid, 3, "guard", nil, "test")
end

OPS.clear = function(ply)
	S.ClearEnemies()
	for _, e in ipairs(ents.FindByClass("ws_enemy")) do e:Remove() end
end

OPS.tp = function(ply)
	local pos = readVec()
	if pos then ply:SetPos(pos + Vector(0, 0, 8)) end
end

OPS.fly = function(ply)
	ply:SetMoveType(ply:GetMoveType() == MOVETYPE_NOCLIP and MOVETYPE_WALK or MOVETYPE_NOCLIP)
end

net.Receive("ws.edit.op", function(_, ply)
	if not ply.wsEditing or not canEdit(ply) then return end
	if (ply.wsEditNext or 0) > CurTime() then return end
	ply.wsEditNext = CurTime() + 0.05
	local op = OPS[net.ReadString()]
	if not op then return end
	if op(ply) then
		P.Unsaved = true
		refresh()
	end
end)
