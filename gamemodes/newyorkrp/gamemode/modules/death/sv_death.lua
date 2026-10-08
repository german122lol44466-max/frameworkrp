--[[
	Смерть: возрождение только после таймера и по кнопке в меню смерти.
]]

hook.Add("PlayerDeath", "nyrp.death", function(ply)
	ply:SetNW2Float("nyrp.deathTime", CurTime())
	ply.nyrpWantRespawn = false
	ply:EmitSound("nyrp/fx/death.wav", 70)
end)

function GM:PlayerDeathThink(ply)
	if not NYRP.HasCharacter(ply) then return end
	if ply.nyrpWantRespawn and CurTime() >= ply:GetNW2Float("nyrp.deathTime") + NYRP.Config.RespawnTime then
		ply.nyrpWantRespawn = false
		ply:Spawn()
	end
	return false
end

net.Receive("nyrp.death.respawn", function(_, ply)
	if not ply:Alive() then ply.nyrpWantRespawn = true end
end)

-- Тело падает мягче: игрок «доносит» скорость до рэгдолла (клиент делает остальное).
function GM:DoPlayerDeath(ply, attacker, dmg)
	ply:CreateRagdoll()
	ply:AddDeaths(1)
	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply then attacker:AddFrags(1) end
end
