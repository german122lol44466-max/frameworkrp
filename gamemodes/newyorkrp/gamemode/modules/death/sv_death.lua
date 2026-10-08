--[[
	Смерть: причина смерти (для экрана смерти) и автоматическое возрождение через Config.RespawnTime.
]]

local causes = {
	{ DMG_FALL, "Падение с высоты" }, { DMG_BULLET, "Огнестрельное ранение" }, { DMG_BUCKSHOT, "Огнестрельное ранение" },
	{ DMG_SLASH, "Ножевое ранение" }, { DMG_BLAST, "Взрыв" }, { DMG_BURN, "Ожоги" }, { DMG_DROWN, "Утонул" },
	{ DMG_VEHICLE, "Сбит транспортом" }, { DMG_SHOCK, "Удар током" }, { DMG_POISON, "Отравление" },
	{ DMG_CLUB, "Тупая травма" }, { DMG_CRUSH, "Тупая травма" },
}

hook.Add("EntityTakeDamage", "nyrp.death.cause", function(ent, dmg)
	if ent:IsPlayer() then ent.nyrpLastDmg = { type = dmg:GetDamageType(), attacker = dmg:GetAttacker() } end
end)

local function causeOf(ply)
	if ply.nyrpDeathCause then return ply.nyrpDeathCause end
	local d = ply.nyrpLastDmg
	if d then
		for _, c in ipairs(causes) do
			if bit.band(d.type, c[1]) ~= 0 then return c[2] end
		end
	end
	if ply:GetNW2Float("nyrp.hunger", 100) <= 0 or ply:GetNW2Float("nyrp.thirst", 100) <= 0 then return "Истощение" end
	return "Причина неизвестна"
end

hook.Add("PlayerDeath", "nyrp.death", function(ply)
	ply:SetNW2Float("nyrp.deathTime", CurTime())
	ply:SetNW2String("nyrp.deathCause", causeOf(ply))
	ply.nyrpDeathCause, ply.nyrpLastDmg = nil, nil
	ply:EmitSound("nyrp/fx/death.wav", 70)
end)

-- Возрождение — само, по таймеру (кнопки нет).
function GM:PlayerDeathThink(ply)
	if not NYRP.HasCharacter(ply) then return end
	if CurTime() >= ply:GetNW2Float("nyrp.deathTime") + NYRP.Config.RespawnTime then
		ply:Spawn()
	end
	return false
end

-- Труп — серверный рэгдолл: его видят все, его можно тащить руками и осмотреть (пульс).
-- Если человек умер без сознания — тело остаётся тем же.
local corpses = {}
function GM:DoPlayerDeath(ply, attacker, dmg)
	local rag
	if ply.nyrpKO and IsValid(ply.nyrpKO.rag) then
		rag = ply.nyrpKO.rag
		ply.nyrpKO.rag = nil
	else
		rag = NYRP.Cond.MakeRagdoll(ply)
		if IsValid(rag) then
			local force = dmg and dmg:GetDamageForce() or vector_origin
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local p = rag:GetPhysicsObjectNum(i)
				if IsValid(p) then p:ApplyForceCenter(force * 0.04) end
			end
			rag:EmitSound("nyrp/fx/body_fall.wav", 72, math.random(95, 105))
		end
	end
	if IsValid(rag) then
		rag.nyrpOwner = nil
		rag.nyrpCorpseOf = ply
		rag:SetNW2Bool("nyrp.corpse", true)
		rag:SetNW2Bool("nyrp.koCritical", false)
		rag:SetNW2Entity("nyrp.koOwner", NULL)
		rag:SetNW2Entity("nyrp.corpseOwner", ply)
		rag:SetNW2Float("nyrp.corpseTime", CurTime())
		ply:SetNW2Entity("nyrp.deathRag", rag)
		corpses[#corpses + 1] = rag
		-- не больше 12 тел на карте; каждое исчезает через 10 минут
		while #corpses > 12 do
			local old = table.remove(corpses, 1)
			if IsValid(old) then old:Remove() end
		end
		timer.Simple(600, function() if IsValid(rag) then rag:Remove() end end)
	end
	ply:AddDeaths(1)
	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply then attacker:AddFrags(1) end
end
