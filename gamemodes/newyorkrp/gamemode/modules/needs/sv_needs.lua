--[[
	Голод и жажда: медленно падают; на нуле персонаж теряет здоровье.
]]

local cfg = NYRP.Config.Needs
local TICK = 10

timer.Create("nyrp.needs", TICK, 0, function()
	local hungerStep = 100 / (cfg.HungerMinutes * 60 / TICK)
	local thirstStep = 100 / (cfg.ThirstMinutes * 60 / TICK)
	for _, ply in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(ply) and ply:Alive() then
			local hunger = math.max(ply:GetNW2Float("nyrp.hunger", 100) - hungerStep, 0)
			local thirst = math.max(ply:GetNW2Float("nyrp.thirst", 100) - thirstStep, 0)
			ply:SetNW2Float("nyrp.hunger", hunger)
			ply:SetNW2Float("nyrp.thirst", thirst)
			if hunger <= 0 or thirst <= 0 then
				local dmg = DamageInfo()
				dmg:SetDamage(cfg.StarveDamage)
				dmg:SetDamageType(DMG_GENERIC)
				dmg:SetAttacker(game.GetWorld())
				ply:TakeDamageInfo(dmg)
				if (ply.nyrpStarveNotify or 0) < CurTime() then
					ply.nyrpStarveNotify = CurTime() + 60
					NYRP.Notify(ply, hunger <= 0 and "Вы умираете от голода — поешьте" or "Вас мучает жажда — попейте", "error", 6)
				end
			elseif (hunger < 20 or thirst < 20) and (ply.nyrpNeedsWarn or 0) < CurTime() then
				ply.nyrpNeedsWarn = CurTime() + 180
				NYRP.Notify(ply, hunger < 20 and "Вы проголодались" or "Хочется пить", "warning")
			end
		end
	end
end)

-- После смерти не возрождаемся голодными до нуля.
hook.Add("NYRP.PlayerSpawned", "nyrp.needs", function(ply)
	ply:SetNW2Float("nyrp.hunger", math.max(ply:GetNW2Float("nyrp.hunger", 100), 30))
	ply:SetNW2Float("nyrp.thirst", math.max(ply:GetNW2Float("nyrp.thirst", 100), 30))
end)
