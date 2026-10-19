--[[
	Достижения на сервере: счётчики, открытие, сохранение (PData «ws_ach»), звание, прибавка к набору.
]]

local A = WS.Ach
local L = WS.Lobby

for _, n in ipairs({ "ws.ach.state", "ws.ach.unlock", "ws.ach.title", "ws.ach.request" }) do util.AddNetworkString(n) end

local function data(ply)
	if not ply.wsAch then
		local t = util.JSONToTable(ply:GetPData("ws_ach", "") or "") or {}
		ply.wsAch = { got = t.got or {}, stat = t.stat or {} }
	end
	return ply.wsAch
end

local function save(ply)
	if not IsValid(ply) then return end
	ply:SetPData("ws_ach", util.TableToJSON(data(ply)))
end

function A.Send(ply)
	local d = data(ply)
	net.Start("ws.ach.state")
	net.WriteUInt(#A.List, 8)
	for _, a in ipairs(A.List) do
		net.WriteBool(d.got[a.id] ~= nil)
		net.WriteUInt(math.min(a.stat and (d.stat[a.stat] or 0) or 0, 65535), 16)
	end
	net.Send(ply)
end

function A.Has(ply, id) return data(ply).got[id] ~= nil end

function A.Unlock(ply, id)
	if not IsValid(ply) or not A.ById[id] or A.Has(ply, id) then return end
	data(ply).got[id] = os.time()
	save(ply)
	net.Start("ws.ach.unlock")
	net.WriteString(id)
	net.Send(ply)
	A.Send(ply)
	-- отряд узнаёт
	local mates = {}
	for _, p in ipairs(L.Members(L.Id(ply))) do if p ~= ply then mates[#mates + 1] = p end end
	for _, p in ipairs(mates) do p:ChatPrint(L.Name(ply) .. " получает достижение «" .. A.ById[id].name .. "»") end
	hook.Run("WSAchievement", ply, id)
end

function A.Stat(ply, stat, n)
	if not IsValid(ply) then return end
	local d = data(ply)
	d.stat[stat] = (d.stat[stat] or 0) + (n or 1)
	ply.wsAchDirty = true
	for _, a in ipairs(A.List) do
		if a.stat == stat and not d.got[a.id] and d.stat[stat] >= a.goal then A.Unlock(ply, a.id) end
	end
end

-- сохранять счётчики не чаще раза в 20 с
timer.Create("ws.ach.save", 20, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if p.wsAchDirty then p.wsAchDirty = nil save(p) A.Send(p) end
	end
end)

hook.Add("PlayerInitialSpawn", "ws.ach", function(ply)
	timer.Simple(3, function()
		if not IsValid(ply) then return end
		local title = ply:GetPData("ws_title", "")
		if title ~= "" and A.CanTitle(ply, title) then ply:SetNW2String("ws_title", title) end
		A.Send(ply)
	end)
end)

hook.Add("PlayerDisconnected", "ws.ach", function(ply) if ply.wsAchDirty then save(ply) end end)
hook.Add("ShutDown", "ws.ach", function() for _, p in ipairs(player.GetAll()) do save(p) end end)

function A.CanTitle(ply, title)
	for _, a in ipairs(A.List) do
		if a.reward and a.reward.title == title and A.Has(ply, a.id) then return true end
	end
	return false
end

net.Receive("ws.ach.title", function(_, ply)
	local title = net.ReadString()
	if title ~= "" and not A.CanTitle(ply, title) then return end
	ply:SetNW2String("ws_title", title)
	ply:SetPData("ws_title", title)
end)

net.Receive("ws.ach.request", function(_, ply)
	if (ply.wsAchReq or 0) > CurTime() then return end
	ply.wsAchReq = CurTime() + 2
	A.Send(ply)
end)

-- награды: прибавка к набору на выход
hook.Add("WSExtraKit", "ws.ach", function(ply)
	local extra = {}
	for _, a in ipairs(A.List) do
		if A.Has(ply, a.id) and a.reward and a.reward.kit then
			for _, k in ipairs(a.reward.kit) do extra[#extra + 1] = k end
		end
	end
	return extra
end)

-- ---------------------------------------------------------------- события

hook.Add("WSEnemyKilled", "ws.ach", function(enemy, attacker)
	if not IsValid(attacker) or not attacker:IsPlayer() then return end
	A.Unlock(attacker, "first_blood")
	A.Stat(attacker, "kills")
	if enemy.wsHeadHit and CurTime() - enemy.wsHeadHit < 0.3 then A.Stat(attacker, "headshots") end
end)

hook.Add("WSItemUsed", "ws.ach", function(ply, id, who, wasBleeding)
	local d = WS.Inv.Def(id)
	if id == "medkit" and IsValid(who) and who ~= ply then A.Stat(ply, "healed", d.heal or 0) end
	if wasBleeding and who == ply then A.Stat(ply, "bleedstops") end
end)

hook.Add("WSItemPicked", "ws.ach", function(ply) A.Stat(ply, "picked") end)
hook.Add("WSCrateOpened", "ws.ach", function(ply) A.Stat(ply, "crates") end)

local function fighters()
	local out = {}
	for _, p in ipairs(player.GetAll()) do if L.InGame(p) and p:Alive() then out[#out + 1] = p end end
	return out
end

-- урон за главу: «Ни царапины»
hook.Add("EntityTakeDamage", "ws.ach", function(ent, dmg)
	if ent:IsPlayer() and L.InGame(ent) and dmg:GetDamage() > 0 then ent.wsChDamage = (ent.wsChDamage or 0) + dmg:GetDamage() end
end)

local lastCh
hook.Add("WSStoryStep", "ws.ach", function(ch, i, d)
	if i == 1 and ch ~= lastCh then
		-- прошлая глава пройдена: кто был с начала главы и не получил урона
		if lastCh then
			for _, p in ipairs(fighters()) do
				if p.wsChStart == lastCh and (p.wsChDamage or 0) == 0 then A.Unlock(p, "untouched") end
			end
		end
		lastCh = ch
		for _, p in ipairs(fighters()) do p.wsChStart = ch p.wsChDamage = 0 end
		if WS.Story.Chapters[ch] and WS.Story.Chapters[ch].id == "core" then
			for _, p in ipairs(fighters()) do A.Unlock(p, "halfway") end
		end
	end
	if d.type == "hold" and d.point == "relay" then
		for _, p in ipairs(fighters()) do A.Unlock(p, "signal") end
	end
end)

-- чекпоинт, когда весь отряд пал, а ты — нет
hook.Add("WSCheckpoint", "ws.ach", function()
	for _, p in ipairs(fighters()) do
		local mates, dead = 0, 0
		for _, m in ipairs(L.Members(L.Id(p))) do
			if m ~= p and L.InGame(m) then
				mates = mates + 1
				if not m:Alive() then dead = dead + 1 end
			end
		end
		if mates > 0 and dead == mates then A.Unlock(p, "last_one") end
	end
end)

hook.Add("WSStoryFinished", "ws.ach", function(stats)
	for _, p in ipairs(player.GetAll()) do
		if L.InGame(p) then
			A.Unlock(p, "complete")
			if stats.deaths == 0 then A.Unlock(p, "no_losses") end
		end
	end
	lastCh = nil
end)
