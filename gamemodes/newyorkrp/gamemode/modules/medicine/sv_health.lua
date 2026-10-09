--[[
	Лечение по частям тела (меню состояния, J): предмет из сумки перетаскивают на часть тела.
	Успех и скорость зависят от навыка «Медицина»; неудача тратит предмет, но тоже немного учит.
]]

local Cond = NYRP.Cond
local Inv = NYRP.Inv
local Items = NYRP.Items

local PART_NAME = { head = "голову", body = "корпус", arm = "руку", leg = "ногу" }
local XP = { head = 25, body = 18, leg = 12, arm = 10 }

local function hurt(ply, part)
	if part == "head" then return Cond.Until(ply, "wound_head") > 0 or Cond.Until(ply, "concussion") > 0 end
	if part == "body" then return Cond.Until(ply, "wound_body") > 0 or ply:GetNW2Bool("nyrp.bleeding") or ply:Health() < ply:GetMaxHealth() end
	if part == "arm" then return Cond.Until(ply, "wound_arm") > 0 end
	if part == "leg" then return Cond.Until(ply, "wound_leg") > 0 or Cond.Until(ply, "fracture") > 0 or Cond.Until(ply, "bruise") > 0 end
end

local function clamp(ply, key, secs)
	local left = Cond.Until(ply, key)
	if left > secs then ply:SetNW2Float("nyrp." .. key .. "Until", CurTime() + secs) end
end

local function apply(ply, id, part)
	if part == "head" then
		ply:SetNW2Float("nyrp.concussionUntil", 0)
		if id ~= "painkillers" then ply:SetNW2Float("nyrp.wound_headUntil", 0) end
	elseif part == "body" then
		ply:SetNW2Bool("nyrp.bleeding", false)
		if id == "bandage" then clamp(ply, "wound_body", 60) else ply:SetNW2Float("nyrp.wound_bodyUntil", 0) end
	elseif part == "arm" then
		ply:SetNW2Float("nyrp.wound_armUntil", 0)
	elseif part == "leg" then
		ply:SetNW2Float("nyrp.wound_legUntil", 0)
		ply:SetNW2Float("nyrp.bruiseUntil", 0)
		if id == "splint" then clamp(ply, "fracture", 15) elseif id == "medkit" then clamp(ply, "fracture", 40) end
	end
	ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + (id == "medkit" and 15 or 5)))
end

-- потратить один предмет (с учётом «использований»)
local function consume(ply, slot)
	local inv = Inv.Get(ply)
	local it = inv.slots[slot]
	if not it then return end
	local def = Items.Get(it.id)
	if def and def.uses and def.uses > 1 then
		it.data = it.data or {}
		it.data.uses = (it.data.uses or def.uses) - 1
		if it.data.uses > 0 then Inv.Sync(ply) return end
	end
	Inv.Take(ply, slot, 1)
end

net.Receive("nyrp.health.treat", function(_, ply)
	if (ply.nyrpTreatNext or 0) > CurTime() or not NYRP.HasCharacter(ply) or not ply:Alive() or Cond.KO(ply) then return end
	ply.nyrpTreatNext = CurTime() + 0.5
	local slot, part = net.ReadUInt(8), net.ReadString()
	if not PART_NAME[part] then return end
	local it = Inv.Get(ply).slots[slot]
	local def = it and Items.Get(it.id)
	if not def or not def.treats then return end
	if not def.treats[part] then NYRP.Notify(ply, def.name .. " не поможет: это не для " .. (part == "head" and "головы" or part == "body" and "корпуса" or part == "arm" and "руки" or "ноги"), "warning") return end
	local lvl = NYRP.Skills.Level(ply, "medicine")
	local need = (part == "head" and def.treatSkillHead) or def.treatSkill or 0
	if lvl < need then NYRP.Notify(ply, "Не хватает навыка «Медицина»: нужен уровень " .. need .. " (у вас " .. lvl .. ")", "error", 5) return end
	if not hurt(ply, part) then NYRP.Notify(ply, "С этим всё в порядке", "info") return end
	local t = (def.treatTime or 5) * (1 - math.min(lvl, 10) * 0.04) * (lvl >= 5 and 0.7 or 1)
	local id = it.id
	local near = {}
	for _, p in ipairs(player.GetAll()) do if p:GetPos():DistToSqr(ply:GetPos()) < 400 * 400 then near[#near + 1] = p end end
	NYRP.Chat.Send(near, NYRP.Chat.Types.ME, ply, "обрабатывает себе " .. PART_NAME[part])
	NYRP.Action(ply, "Лечу " .. PART_NAME[part] .. "...", t, function()
		local cur = Inv.Get(ply).slots[slot]
		if not cur or cur.id ~= id then return end
		local chance = math.Clamp(0.62 + lvl * 0.05 - (def.difficulty or 0) + (lvl >= 10 and 0.2 or 0), 0.15, 0.98)
		if id == "painkillers" then chance = 1 end
		consume(ply, slot)
		if math.random() < chance then
			apply(ply, id, part)
			ply:EmitSound("items/medshot4.wav", 55)
			NYRP.Notify(ply, "Готово: рана обработана", "success", 4)
			NYRP.Skills.AddXP(ply, "medicine", XP[part])
		else
			ply:EmitSound("nyrp/fx/pain" .. math.random(1, 4) .. ".wav", 60)
			NYRP.Notify(ply, "Не получилось — руки не слушаются. Опыт придёт с практикой.", "warning", 5)
			NYRP.Skills.AddXP(ply, "medicine", XP[part] * 0.4)
		end
	end, "medkit")
end)
