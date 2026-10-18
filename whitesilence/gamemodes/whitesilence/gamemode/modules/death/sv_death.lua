--[[
	Смерть на сервере: причина уходит погибшему, сам он не возрождается — после экрана смерти возвращается в меню
	(отряд сохраняется, можно снова выдвинуться).
]]

util.AddNetworkString("ws.death")
util.AddNetworkString("ws.death.return")

local MIN_TIME = 5

local function cause(victim, inflictor, attacker)
	if attacker == victim then return "Самоубийство" end
	if IsValid(attacker) and attacker:IsPlayer() then
		local wep = IsValid(inflictor) and inflictor ~= attacker and inflictor or attacker:GetActiveWeapon()
		local wname = IsValid(wep) and (wep.PrintName or wep:GetClass()) or nil
		return "Убит: " .. WS.Lobby.Name(attacker) .. (wname and (" · " .. wname) or "")
	end
	if IsValid(attacker) and (attacker:IsNPC() or attacker:IsNextBot()) then
		return "Убит: " .. (attacker.PrintName or language.GetPhrase(attacker:GetClass()))
	end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, DMG_FALL) ~= 0 then return "Падение с высоты" end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, bit.bor(DMG_BURN, DMG_SLOWBURN)) ~= 0 then return "Огонь" end
	if victim.wsLastDmg and bit.band(victim.wsLastDmg, DMG_BLAST) ~= 0 then return "Взрыв" end
	return "Неизвестно"
end

hook.Add("EntityTakeDamage", "ws.death", function(ent, dmg)
	if ent:IsPlayer() then ent.wsLastDmg = dmg:GetDamageType() end
end)

hook.Add("PlayerDeath", "ws.death", function(victim, inflictor, attacker)
	victim.wsDeathT = CurTime()
	net.Start("ws.death")
	net.WriteString(cause(victim, inflictor, attacker))
	net.Send(victim)
end)

-- без стандартного писка смерти и без возрождения по клику
hook.Add("PlayerDeathSound", "ws.death", function() return true end)
hook.Add("PlayerDeathThink", "ws.death", function(ply)
	if WS.Lobby.InGame(ply) then return false end
end)

net.Receive("ws.death.return", function(_, ply)
	if ply:Alive() or not WS.Lobby.InGame(ply) then return end
	if CurTime() - (ply.wsDeathT or 0) < MIN_TIME then return end
	ply:SetNW2Bool("ws_ingame", false)
	ply:Spawn()
end)
