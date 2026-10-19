--[[
	Смерть на сервере. Погибший не возрождается и не уходит в меню: после нескольких секунд «из глаз тела»
	он наблюдает за живыми товарищами (ПРОБЕЛ — следующий) и возвращается в бой на ближайшем чекпоинте
	(начало главы или шаг с checkpoint = true). Живые его не слышат и не видят его сообщений.
	Если погибли все — глава начинается заново (sv_story.lua), все возвращаются сразу.
	В меню можно выйти из наблюдения (М).
]]

local L = WS.Lobby
local D = WS.Death or {}
WS.Death = D

util.AddNetworkString("ws.death")
util.AddNetworkString("ws.death.return")
util.AddNetworkString("ws.spec.next")

local SPECTATE_AFTER = 5

local function cause(victim, inflictor, attacker)
	if attacker == victim then return "Самоубийство" end
	if IsValid(attacker) and attacker:IsPlayer() then
		local wep = IsValid(inflictor) and inflictor ~= attacker and inflictor or attacker:GetActiveWeapon()
		local wname = IsValid(wep) and (wep.PrintName or wep:GetClass()) or nil
		return "Убит: " .. L.Name(attacker) .. (wname and (" · " .. wname) or "")
	end
	if IsValid(attacker) and (attacker:IsNPC() or attacker:IsNextBot()) then
		return "Убит: " .. (attacker.PrintName or language.GetPhrase(attacker:GetClass()))
	end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, DMG_FALL) ~= 0 then return "Падение с высоты" end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, bit.bor(DMG_BURN, DMG_SLOWBURN)) ~= 0 then return "Огонь" end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, DMG_BLAST) ~= 0 then return "Взрыв" end
	if victim.wsBleedDeath then return "Потеря крови" end
	return "Неизвестно"
end

hook.Add("EntityTakeDamage", "ws.death", function(ent, dmg)
	if ent:IsPlayer() then ent.wsLastDmg = dmg:GetDamageType() end
end)

-- живые бойцы, за которыми можно наблюдать (сначала свой отряд)
local function targets(ply)
	local own, other = {}, {}
	for _, p in ipairs(player.GetAll()) do
		if p ~= ply and p:Alive() and L.InGame(p) then
			if L.Id(p) == L.Id(ply) then own[#own + 1] = p else other[#other + 1] = p end
		end
	end
	for _, p in ipairs(other) do own[#own + 1] = p end
	return own
end

function D.IsSpectating(ply)
	return ply:GetNW2Bool("ws_spectating", false)
end

local function watch(ply, step)
	local list = targets(ply)
	if #list == 0 then return end
	local cur = ply:GetObserverTarget()
	local idx = 0
	for i, p in ipairs(list) do if p == cur then idx = i end end
	idx = (idx + (step or 0) - 1) % #list + 1
	if ply:GetObserverMode() ~= OBS_MODE_CHASE then ply:Spectate(OBS_MODE_CHASE) end
	ply:SpectateEntity(list[idx])
	ply:SetNW2Entity("ws_spec_target", list[idx])
end

local function startSpectate(ply)
	if ply:Alive() or not L.InGame(ply) then return end
	ply:SetNW2Bool("ws_spectating", true)
	watch(ply, 1)
end

hook.Add("PlayerDeath", "ws.death", function(victim, inflictor, attacker)
	victim.wsDeathT = CurTime()
	net.Start("ws.death")
	net.WriteString(cause(victim, inflictor, attacker))
	net.Send(victim)
	if L.InGame(victim) then
		timer.Simple(SPECTATE_AFTER, function() if IsValid(victim) then startSpectate(victim) end end)
	end
	-- тот, за кем наблюдали, погиб — переключить наблюдателей
	for _, p in ipairs(player.GetAll()) do
		if D.IsSpectating(p) and p:GetObserverTarget() == victim then timer.Simple(1.5, function() if IsValid(p) then watch(p, 1) end end) end
	end
end)

hook.Add("PlayerDeathSound", "ws.death", function() return true end)
hook.Add("PlayerDeathThink", "ws.death", function(ply)
	if L.InGame(ply) then return false end
end)

-- Вернуть в бой: всех наблюдателей (или одного)
function D.Revive(ply)
	if not IsValid(ply) or ply:Alive() or not L.InGame(ply) then return end
	ply:SetNW2Bool("ws_spectating", false)
	ply:SetNW2Entity("ws_spec_target", NULL)
	ply:UnSpectate()
	ply:Spawn()
	hook.Run("WSRevived", ply)
end

function D.ReviveAll()
	for _, p in ipairs(player.GetAll()) do
		if L.InGame(p) and not p:Alive() then D.Revive(p) end
	end
end

hook.Add("PlayerSpawn", "ws.death", function(ply)
	if D.IsSpectating(ply) then
		ply:SetNW2Bool("ws_spectating", false)
		ply:UnSpectate()
	end
end)

net.Receive("ws.spec.next", function(_, ply)
	if not D.IsSpectating(ply) then return end
	if (ply.wsSpecNext or 0) > CurTime() then return end
	ply.wsSpecNext = CurTime() + 0.3
	watch(ply, net.ReadBool() and -1 or 1)
end)

-- выйти из наблюдения в меню
net.Receive("ws.death.return", function(_, ply)
	if ply:Alive() or not L.InGame(ply) then return end
	if CurTime() - (ply.wsDeathT or 0) < SPECTATE_AFTER then return end
	ply:SetNW2Bool("ws_spectating", false)
	ply:UnSpectate()
	ply:SetNW2Bool("ws_ingame", false)
	ply:Spawn()
end)

-- раз в секунду: наблюдатель без цели получает новую
timer.Create("ws.spec.watch", 1, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if D.IsSpectating(p) then
			local t = p:GetObserverTarget()
			if not IsValid(t) or not t:Alive() then watch(p, 1) end
		end
	end
end)
