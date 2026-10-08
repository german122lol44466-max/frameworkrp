--[[
	Голод и жажда: медленно падают.
	- голод на нуле — персонаж теряет здоровье;
	- жажда здоровье не отнимает, но бьёт по выносливости (modules/condition): быстрее выдыхаешься,
	  медленнее отдыхаешь, а на нуле выносливость не поднимается выше трети;
	- время от времени персонаж сам «показывает» это действием (/me): урчит живот, облизывает губы...
]]

local cfg = NYRP.Config.Needs
local TICK = 10

-- Эмоуты: { порог, { варианты } } — от самого сильного к слабому.
local EMOTES = {
	hunger = {
		{ 0, { "держится за живот — его скручивает от голода", "пошатывается, в глазах темнеет от голода", "громко урчит живот, лицо бледное" } },
		{ 20, { "урчит живот", "морщится и трогает живот", "сглатывает, вспомнив о еде" } },
	},
	thirst = {
		{ 0, { "тяжело дышит, губы потрескались от жажды", "кашляет пересохшим горлом", "проводит языком по сухим губам, взгляд мутный" } },
		{ 20, { "облизывает пересохшие губы", "сглатывает — во рту пересохло", "откашливается, горло першит" } },
	},
}

local function emote(ply, kind, value)
	for _, row in ipairs(EMOTES[kind]) do
		if value <= row[1] then
			local text = table.Random(row[2])
			local recipients = {}
			local range = NYRP.Chat.Range(NYRP.Chat.Types.ME)
			for _, p in ipairs(player.GetAll()) do
				if p:GetPos():DistToSqr(ply:GetPos()) <= range * range then recipients[#recipients + 1] = p end
			end
			NYRP.Chat.Send(recipients, NYRP.Chat.Types.ME, ply, text)
			return true
		end
	end
end

timer.Create("nyrp.needs", TICK, 0, function()
	local hungerStep = 100 / (cfg.HungerMinutes * 60 / TICK)
	local thirstStep = 100 / (cfg.ThirstMinutes * 60 / TICK)
	for _, ply in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(ply) and ply:Alive() and not (NYRP.Cond and NYRP.Cond.KO(ply)) then
			local hunger = math.max(ply:GetNW2Float("nyrp.hunger", 100) - hungerStep, 0)
			local thirst = math.max(ply:GetNW2Float("nyrp.thirst", 100) - thirstStep, 0)
			ply:SetNW2Float("nyrp.hunger", hunger)
			ply:SetNW2Float("nyrp.thirst", thirst)
			if hunger <= 0 then
				local dmg = DamageInfo()
				dmg:SetDamage(cfg.StarveDamage)
				dmg:SetDamageType(DMG_GENERIC)
				dmg:SetAttacker(game.GetWorld())
				ply:TakeDamageInfo(dmg)
				if (ply.nyrpStarveNotify or 0) < CurTime() then
					ply.nyrpStarveNotify = CurTime() + 60
					NYRP.Notify(ply, "Вы умираете от голода — поешьте", "error", 6)
				end
			end
			if thirst <= 0 and (ply.nyrpThirstNotify or 0) < CurTime() then
				ply.nyrpThirstNotify = CurTime() + 90
				NYRP.Notify(ply, "Вас мучает жажда — силы на исходе, попейте", "error", 6)
			end
			if (hunger < 20 or thirst < 20) and (ply.nyrpNeedsWarn or 0) < CurTime() then
				ply.nyrpNeedsWarn = CurTime() + 180
				NYRP.Notify(ply, hunger < 20 and "Вы проголодались" or "Хочется пить", "warning")
			end
			-- эмоуты: раз в 1.5–3 минуты, чаще при нуле
			if (ply.nyrpNeedEmote or 0) < CurTime() and (hunger < 20 or thirst < 20) then
				local kind = (hunger <= thirst) and "hunger" or "thirst"
				local val = kind == "hunger" and hunger or thirst
				if emote(ply, kind, val) then
					ply.nyrpNeedEmote = CurTime() + (val <= 0 and math.random(60, 100) or math.random(100, 180))
				end
			end
		end
	end
end)

-- После смерти не возрождаемся голодными до нуля.
hook.Add("NYRP.PlayerSpawned", "nyrp.needs", function(ply)
	ply:SetNW2Float("nyrp.hunger", math.max(ply:GetNW2Float("nyrp.hunger", 100), 30))
	ply:SetNW2Float("nyrp.thirst", math.max(ply:GetNW2Float("nyrp.thirst", 100), 30))
	ply.nyrpNeedEmote = CurTime() + 60
end)
