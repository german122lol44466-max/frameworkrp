local CB = NYRP.Combat
local Cond = NYRP.Cond
local Items = NYRP.Items

local function setUntil(ply, key, secs)
	local cur = ply:GetNW2Float("nyrp." .. key .. "Until", 0)
	ply:SetNW2Float("nyrp." .. key .. "Until", math.max(cur, CurTime() + secs))
end

-- защита надетых вещей по зоне: { body = 0..0.9, head = 0..0.9 }
local function protection(ply)
	local out = { body = 0, head = 0 }
	local inv = NYRP.Inv.Get(ply)
	for _, it in pairs(inv.equip or {}) do
		local def = Items.Get(it.id)
		if def and def.protect and def.protectZone then
			out[def.protectZone] = math.max(out[def.protectZone] or 0, def.protect)
		end
	end
	return out
end
CB.Protection = protection

local PART = {
	[HITGROUP_HEAD] = "head", [HITGROUP_CHEST] = "body", [HITGROUP_STOMACH] = "body",
	[HITGROUP_LEFTARM] = "arm", [HITGROUP_RIGHTARM] = "arm", [HITGROUP_LEFTLEG] = "leg", [HITGROUP_RIGHTLEG] = "leg",
}

function GM:ScalePlayerDamage(ply, hitgroup, dmg)
	local part = PART[hitgroup]
	if not part then return end
	local bullet = dmg:IsBulletDamage()
	local prot = protection(ply)
	local mult = 1
	if part == "head" then
		-- без каски: два попадания из пистолета (≈ 2 × 55) — смерть
		if prot.head > 0 then
			mult = 2.2 * (1 - prot.head)
			ply:EmitSound("physics/metal/metal_solid_impact_bullet" .. math.random(1, 4) .. ".wav", 70)
		else
			mult = 3.2
		end
	elseif part == "body" then
		mult = 1 - prot.body
		if prot.body > 0 and bullet then ply:EmitSound("physics/flesh/flesh_impact_bullet" .. math.random(1, 5) .. ".wav", 60, 80) end
	elseif part == "arm" then
		mult = 0.55
	elseif part == "leg" then
		mult = 0.6
	end
	if bullet and part == "head" and prot.head == 0 then
		-- пистолет 9 мм (~8–12 урона в HL2) — подтягиваем до ~55, чтобы два попадания убивали
		dmg:SetDamage(math.max(dmg:GetDamage() * mult, 55))
	else
		dmg:SetDamage(dmg:GetDamage() * mult)
	end
	-- урон HL2 мал для RP: пули по телу ощутимее
	if bullet and part ~= "head" then dmg:ScaleDamage(1.6) end
	if not bullet and dmg:GetDamage() < 5 then return end

	-- ранение
	local chance = (part == "body" and (1 - prot.body * 1.1)) or (part == "head" and (1 - prot.head)) or 0.85
	if math.random() < chance then
		setUntil(ply, "wound_" .. part, CB.WoundTime[part])
		if part == "body" then ply:SetNW2Bool("nyrp.bleeding", true) end
		if part == "head" then setUntil(ply, "concussion", 40) end
		if part == "leg" and math.random() < 0.35 and ply:OnGround() and Cond.Fall then
			timer.Simple(0, function() if IsValid(ply) and ply:Alive() then Cond.Fall(ply, false, 3) end end)
		end
		if part == "arm" and math.random() < 0.15 then
			-- выронить оружие из простреленной руки
			local w = ply:GetActiveWeapon()
			if IsValid(w) and w:GetClass() ~= "nyrp_hands" then ply:SelectWeapon("nyrp_hands") end
		end
	end
end

-- кровотечение: −1 HP раз в 4 с (не ниже 5 — дальше потеря сознания от болевого шока)
timer.Create("nyrp.combat.bleed", 4, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:GetNW2Bool("nyrp.bleeding") then
			if not CB.Wound(ply, "body") then
				ply:SetNW2Bool("nyrp.bleeding", false)
			elseif ply:Health() > 5 then
				ply:SetHealth(ply:Health() - 1)
			elseif Cond.KnockOut and not Cond.KO(ply) then
				Cond.KnockOut(ply, true)
			end
		end
	end
end)

local function heal(ply)
	for _, part in ipairs({ "leg", "arm", "body", "head" }) do ply:SetNW2Float("nyrp.wound_" .. part .. "Until", 0) end
	ply:SetNW2Bool("nyrp.bleeding", false)
end
CB.Heal = heal

hook.Add("NYRP.ItemUsed", "nyrp.combat", function(ply, id) if id == "medkit" then heal(ply) end end)
hook.Add("PlayerSpawn", "nyrp.combat", function(...) heal(...) end)

-- броня: максимум брони и «тяжёлая» отметка
hook.Add("NYRP.EquipmentApplied", "nyrp.combat", function(ply, inv)
	local heavy = false
	local wear = {}
	for _, it in pairs(inv.equip or {}) do
		local def = Items.Get(it.id)
		if def and def.heavy then heavy = true end
		if def and def.wear then wear[#wear + 1] = def.id end
	end
	ply:SetNW2Bool("nyrp.heavyArmor", heavy)
	ply:SetNW2String("nyrp.wear", table.concat(wear, ","))
	-- навык стрельбы виден клиенту (разброс предсказывается)
	local sk = ply.nyrpChar and ply.nyrpChar.skills and ply.nyrpChar.skills.combat or 0
	ply:SetNW2Int("nyrp.skillCombat", sk)
end)

-- бодигруппы одежды/брони: ITEM.Bodygroups = { ["имя группы"] = номер }
hook.Add("NYRP.EquipmentApplied", "nyrp.bodygroups", function(ply, inv)
	local want = {}
	for _, it in pairs(inv.equip or {}) do
		local def = Items.Get(it.id)
		for name, v in pairs(def and def.bodygroups or {}) do want[name] = v end
	end
	for name in pairs(ply.nyrpBodygroups or {}) do
		if want[name] == nil then
			local id = ply:FindBodygroupByName(name)
			if id >= 0 then ply:SetBodygroup(id, 0) end
		end
	end
	for name, v in pairs(want) do
		local id = ply:FindBodygroupByName(name)
		if id >= 0 then ply:SetBodygroup(id, v) end
	end
	ply.nyrpBodygroups = want
end)

-- ---------------------------------------------------------- лут при смерти --
-- половина вещей из сумки выпадает в «выпавшую сумку» рядом с телом
hook.Add("PlayerDeath", "nyrp.combat.loot", function(ply)
	if not NYRP.HasCharacter(ply) or not NYRP.Containers or not NYRP.Containers.Spawn then return end
	local inv = NYRP.Inv.Get(ply)
	local keys = {}
	for k, it in pairs(inv.slots or {}) do
		local def = Items.Get(it.id)
		if def and not def.noDrop and it.id ~= "idcard" then keys[#keys + 1] = k end
	end
	if #keys == 0 then return end
	-- перемешать и взять половину (округление вверх)
	for i = #keys, 2, -1 do
		local j = math.random(i)
		keys[i], keys[j] = keys[j], keys[i]
	end
	local take = math.ceil(#keys / 2)
	local slots = {}
	for i = 1, take do
		local k = keys[i]
		slots[i] = inv.slots[k]
		inv.slots[k] = nil
	end
	NYRP.Inv.Sync(ply)
	local pos = ply:GetPos() + Vector(math.Rand(-20, 20), math.Rand(-20, 20), 10)
	local bag = NYRP.Containers.Spawn("deathbag", pos, Angle(0, math.random(0, 359), 0), slots)
	if IsValid(bag) then
		bag:SetNW2String("nyrp.bagOf", NYRP.CharName(ply))
		timer.Simple(900, function() if IsValid(bag) then bag:Remove() end end)
	end
	if NYRP.Chars.Save then NYRP.Chars.Save(ply) end
end)

-- опустевшая выпавшая сумка исчезает
timer.Create("nyrp.combat.bags", 5, 0, function()
	for _, e in ipairs(ents.FindByClass("nyrp_container")) do
		if e:GetNW2String("nyrp.ctype") == "deathbag" and (CurTime() - (e.nyrpBorn or CurTime())) > 5 and table.Count(e.Slots or {}) == 0 then
			e:Remove()
		end
		e.nyrpBorn = e.nyrpBorn or CurTime()
	end
end)
