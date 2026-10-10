--[[
	Сервер: выносливость, промокание, урон от падения, потеря сознания и помощь другим игрокам.
]]

local Cond = NYRP.Cond
local S = NYRP.Config.Stamina
local F = NYRP.Config.Fall
local U = NYRP.Config.Unconscious
local cleanupKO -- ниже
local bodyOk -- ниже

local function setUntil(ply, key, secs)
	local cur = ply:GetNW2Float("nyrp." .. key .. "Until", 0)
	ply:SetNW2Float("nyrp." .. key .. "Until", math.max(cur, CurTime() + secs))
end

local function resetCondition(ply)
	ply:SetNW2Float("nyrp.stamina", 100)
	ply:SetNW2Bool("nyrp.exhausted", false)
	for _, k in ipairs({ "wet", "bruise", "fracture", "concussion" }) do ply:SetNW2Float("nyrp." .. k .. "Until", 0) end
end

-- ------------------------------------------------------------ выносливость --
local TICK = 0.1
timer.Create("nyrp.condition", TICK, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and NYRP.HasCharacter(ply) and not Cond.KO(ply) then
			local st = Cond.Stamina(ply)
			local speed = ply:GetVelocity():Length2D()
			local running = ply:KeyDown(IN_SPEED) and speed > ply:GetWalkSpeed() + 15 and ply:GetMoveType() == MOVETYPE_WALK
			-- жажда бьёт по выносливости (здоровье не отнимает)
			local thirst = ply:GetNW2Float("nyrp.thirst", 100)
			local tDrain, tRegen, cap = 1, 1, 100
			if thirst <= 0 then tDrain, tRegen, cap = 1.8, 0.35, 40
			elseif thirst < 25 then tDrain, tRegen = 1.4, 0.6 end
			if running then
				local skill = ply.nyrpChar and ply.nyrpChar.skills and ply.nyrpChar.skills.stamina or 0
				local drain = 100 / (S.Seconds * (1 + skill * S.PerSkill))
				if ply:Health() < 50 then drain = drain * S.InjuredDrain end
				st = st - drain * tDrain * TICK
			elseif speed < 8 then
				st = st + S.RegenStand * tRegen * TICK
			else
				st = st + S.RegenWalk * tRegen * TICK
			end
			st = math.Clamp(st, 0, cap)
			ply:SetNW2Float("nyrp.stamina", st)
			-- пытается бежать, когда сил нет: может споткнуться и упасть
			local tryRun = ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) and speed > 40 and ply:OnGround()
			if tryRun and (st <= 1 or Cond.Exhausted(ply)) then
				ply.nyrpTryRun = (ply.nyrpTryRun or 0) + TICK
				if ply.nyrpTryRun > 1.5 and math.random() < 0.035 then
					ply.nyrpTryRun = 0
					Cond.Fall(ply, false, 2.5)
					NYRP.Notify(ply, "Вы споткнулись от усталости", "warning", 3)
				end
			else
				ply.nyrpTryRun = 0
			end
			if st <= 0 and not Cond.Exhausted(ply) then
				ply:SetNW2Bool("nyrp.exhausted", true)
			elseif st >= S.Recover and Cond.Exhausted(ply) then
				ply:SetNW2Bool("nyrp.exhausted", false)
			end
			-- в воде — промокаем
			local wl = ply:WaterLevel()
			if wl >= 1 then setUntil(ply, "wet", 45 * wl) end
		end
	end
end)

hook.Add("KeyPress", "nyrp.condition.jump", function(ply, key)
	if key == IN_JUMP and ply:OnGround() and ply:Alive() then
		ply:SetNW2Float("nyrp.stamina", math.max(0, Cond.Stamina(ply) - S.Jump))
	end
end)

hook.Add("NYRP.PlayerSpawned", "nyrp.condition", function(...) resetCondition(...) end)
hook.Add("PlayerSpawn", "nyrp.condition", function(ply)
	if ply.nyrpKO then cleanupKO(ply) end
	resetCondition(ply)
end)

-- Аптечка фиксирует перелом и снимает ушиб.
hook.Add("NYRP.ItemUsed", "nyrp.condition", function(ply, id)
	if id ~= "medkit" then return end
	ply:SetNW2Float("nyrp.bruiseUntil", 0)
	local fr = Cond.Until(ply, "fracture")
	if fr > 0 then ply:SetNW2Float("nyrp.fractureUntil", CurTime() + math.min(fr, 30)) end
end)

-- -------------------------------------------------------- урон от падения --
function GM:GetFallDamage(ply, speed)
	local dmg = Cond.FallDamage(speed)
	if ply:Crouching() then dmg = dmg * 0.9 end
	dmg = math.Round(dmg * math.Rand(0.92, 1.08))
	if dmg <= 0 then return 0 end

	ply:EmitSound("nyrp/fx/land_hard.wav", 72, math.random(95, 105))
	if dmg < ply:Health() then
		ply:EmitSound("nyrp/fx/pain" .. math.random(1, 4) .. ".wav", 70, math.random(95, 108))
		setUntil(ply, "bruise", 40 + dmg * 2)
		if dmg >= F.Fracture then setUntil(ply, "fracture", 240) end
		ply:ViewPunch(Angle(math.min(dmg, 30) * 0.6, math.Rand(-4, 4), math.Rand(-6, 6)))
		if speed >= F.KnockOut then
			local hpAfter = ply:Health() - dmg
			timer.Simple(0, function()
				if IsValid(ply) and ply:Alive() then Cond.KnockOut(ply, hpAfter <= F.CriticalHP) end
			end)
		end
	end
	return dmg
end

-- ---------------------------------------------------------- без сознания --
local function ragdollCenter(rag)
	local bone = rag:LookupBone("ValveBiped.Bip01_Pelvis")
	local pos = bone and rag:GetBonePosition(bone)
	return pos or rag:GetPos()
end

-- Серверный рэгдолл по позе игрока (для потери сознания и трупа — его можно тащить руками).
function Cond.MakeRagdoll(ply)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag:SetModel(ply:GetModel())
	rag:SetSkin(ply:GetSkin())
	for i = 0, ply:GetNumBodyGroups() - 1 do rag:SetBodygroup(i, ply:GetBodygroup(i)) end
	rag:SetColor(ply:GetColor())
	rag:SetPos(ply:GetPos())
	rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	rag:Spawn()
	rag:Activate()
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	-- поза тела в момент падения + его скорость (на сервере у игрока нет SetupBones —
	-- берём позицию кости по имени, если она есть)
	local vel = ply:GetVelocity()
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			local bone = ply:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)) or "")
			local pos, ang
			if bone then pos, ang = ply:GetBonePosition(bone) end
			if pos and ang then
				phys:SetPos(pos)
				phys:SetAngles(ang)
			end
			phys:SetVelocity(vel * 0.5)
		end
	end
	return rag
end

function Cond.KnockOut(ply, critical)
	if Cond.KO(ply) or not ply:Alive() then return end
	if NYRP.CancelAction then NYRP.CancelAction(ply) end
	local rag = Cond.MakeRagdoll(ply)
	if not IsValid(rag) then return end

	rag.nyrpOwner = ply
	rag:SetNW2Entity("nyrp.koOwner", ply)
	rag:SetNW2Bool("nyrp.koCritical", critical)
	ply.nyrpKO = { rag = rag }

	ply:SetNW2Entity("nyrp.koRag", rag)
	ply:SetNW2Bool("nyrp.ko", true)
	ply:SetNW2Bool("nyrp.koCritical", critical)
	ply:SetNW2Float("nyrp.koStart", CurTime())
	ply:SetNW2Float("nyrp.koUntil", CurTime() + (critical and U.CriticalTime or U.WakeTime))

	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:DrawShadow(false)
	ply:Freeze(true)
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) then wep:SetNoDraw(true) end
	rag:EmitSound("nyrp/fx/body_fall.wav", 70)
end

-- Упасть: voluntary — сам лёг (C-меню → «Упасть»), встать — Пробел; иначе споткнулся (без сознания не теряет).
function Cond.Fall(ply, voluntary, duration)
	if Cond.KO(ply) or not ply:Alive() then return end
	Cond.KnockOut(ply, false)
	if not Cond.KO(ply) then return end
	ply.nyrpKO.soft = true
	ply:SetNW2Bool("nyrp.koSoft", true)
	ply:SetNW2Bool("nyrp.koVoluntary", voluntary and true or false)
	ply:SetNW2Float("nyrp.koUntil", CurTime() + (duration or (voluntary and 600 or 2.5)))
end

hook.Add("KeyPress", "nyrp.condition.getup", function(ply, key)
	if key ~= IN_JUMP or not ply.nyrpKO or not ply.nyrpKO.soft or not ply:GetNW2Bool("nyrp.koVoluntary") then return end
	if CurTime() - ply:GetNW2Float("nyrp.koStart", 0) < 1.5 then return end
	Cond.WakeUp(ply)
end)

function cleanupKO(ply)
	local ko = ply.nyrpKO
	ply.nyrpKO = nil
	if ko and IsValid(ko.rag) then ko.rag:Remove() end
	ply:SetNW2Bool("nyrp.ko", false)
	ply:SetNW2Bool("nyrp.koCritical", false)
	ply:SetNW2Bool("nyrp.koSoft", false)
	ply:SetNW2Bool("nyrp.koVoluntary", false)
	ply:SetNW2Entity("nyrp.koRag", NULL)
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:DrawShadow(true)
	ply:Freeze(false)
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) then wep:SetNoDraw(false) end
end

-- Свободное место рядом с телом, чтобы встать и не застрять.
local function standPos(ply, from)
	local mins, maxs = ply:GetHull()
	for _, off in ipairs({ Vector(0, 0, 4), Vector(20, 0, 4), Vector(-20, 0, 4), Vector(0, 20, 4), Vector(0, -20, 4), Vector(0, 0, 30) }) do
		local p = from + off
		local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
		if not tr.Hit then
			local down = util.TraceHull({ start = p, endpos = p - Vector(0, 0, 60), mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
			return down.HitPos
		end
	end
	return from + Vector(0, 0, 4)
end

function Cond.WakeUp(ply, hp)
	if not Cond.KO(ply) then return end
	local soft = ply.nyrpKO and ply.nyrpKO.soft
	local rag = ply.nyrpKO and ply.nyrpKO.rag
	local pos = IsValid(rag) and standPos(ply, ragdollCenter(rag) - Vector(0, 0, 30)) or ply:GetPos()
	cleanupKO(ply)
	ply:SetPos(pos)
	if hp then ply:SetHealth(math.max(ply:Health(), hp)) end
	if soft then return end   -- просто лежал / споткнулся: без сотрясения
	setUntil(ply, "concussion", 60)
	ply:SetNW2Float("nyrp.stamina", 30)
	local c = ply.nyrpChar
	ply:EmitSound("nyrp/fx/wake.wav", 60, c and c.gender == "female" and 112 or 100, 0.8)
end

hook.Add("Think", "nyrp.condition.ko", function()
	for _, ply in ipairs(player.GetAll()) do
		local ko = ply.nyrpKO
		if ko then
			if not IsValid(ko.rag) or not ply:Alive() then
				cleanupKO(ply)
			else
				-- игрок «лежит» там же, где тело: голос, слух и подсказки работают
				ply:SetPos(ragdollCenter(ko.rag) - Vector(0, 0, 30))
				if CurTime() >= ply:GetNW2Float("nyrp.koUntil", 0) then
					if ply:GetNW2Bool("nyrp.koCritical") then
						cleanupKO(ply)
						ply.nyrpDeathCause = "Не дождались помощи"
						ply:Kill() -- помощь не пришла
					else
						Cond.WakeUp(ply)
					end
				end
			end
		end
		-- помощь: держит E, смотрит на тело
		local help = ply.nyrpHelping
		if help and ply.nyrpAction then
			if not bodyOk(ply, help) then
				ply.nyrpHelping = nil
				if NYRP.CancelAction then NYRP.CancelAction(ply) end
			end
		end
	end
end)

-- ------------------------------------------------- меню тела (E по телу) --
-- Проверить пульс (точность — навык «Медицина»), помочь встать (без сознания),
-- оказать первую помощь (критическое состояние, нужна аптечка или обезболивающее).
local function medSkill(ply)
	return ply.nyrpChar and ply.nyrpChar.skills and ply.nyrpChar.skills.medicine or 0
end

local function meAction(ply, text)
	local T = NYRP.Chat.Types
	local range = NYRP.Chat.Range(T.ME)
	local rec = {}
	for _, p in ipairs(player.GetAll()) do if p:GetPos():DistToSqr(ply:GetPos()) <= range * range then rec[#rec + 1] = p end end
	NYRP.Chat.Send(rec, T.ME, ply, text)
end

local function pulseText(rag, med)
	local owner = rag.nyrpOwner
	local roll = math.random()
	if rag:GetNW2Bool("nyrp.corpse") then
		if med < 2 and roll < 0.25 then return "Пульс не прощупывается... кажется, его нет совсем." end
		return med >= 3 and "Пульса нет, зрачки не реагируют. Человек мёртв." or "Пульса нет. Похоже, человек мёртв."
	end
	if not IsValid(owner) then return "Не получается нащупать пульс." end
	local crit = owner:GetNW2Bool("nyrp.koCritical")
	local hp = owner:Health()
	local out
	if crit then
		if med == 0 and roll < 0.35 then out = "Не могу понять... кажется, пульс есть, но очень слабый."
		elseif med < 3 then out = "Пульс слабый. Ему очень плохо — нужна помощь."
		else out = string.format("Пульс нитевидный, ~%d уд/мин. Тяжёлые травмы — нужна аптечка.", math.random(120, 145)) end
	else
		if med < 3 then out = "Пульс есть. Человек без сознания, но дышит."
		else out = string.format("Пульс ровный, ~%d уд/мин. Скоро придёт в себя.", math.random(64, 84)) end
	end
	if med >= 4 then out = out .. " Состояние: ~" .. math.Clamp(hp + math.random(-8, 8), 1, 100) .. "%." end
	return out
end

local function findMed(ply)
	local inv = NYRP.Inv.Get(ply)
	for slot, it in pairs(inv.slots) do if it.id == "medkit" then return slot, it end end
	for slot, it in pairs(inv.slots) do if it.id == "painkillers" then return slot, it end end
end

function bodyOk(ply, rag)
	return IsValid(rag) and ply:Alive() and not Cond.KO(ply) and rag:NearestPoint(ply:EyePos()):Distance(ply:EyePos()) <= 130
end

net.Receive("nyrp.body.act", function(_, ply)
	if (ply.nyrpBodyNext or 0) > CurTime() then return end
	ply.nyrpBodyNext = CurTime() + 0.5
	local act, rag = net.ReadString(), net.ReadEntity()
	if not bodyOk(ply, rag) or not rag:IsRagdoll() then return end
	local owner = rag.nyrpOwner
	local med = medSkill(ply)
	ply.nyrpHelping = rag
	if act == "pulse" then
		meAction(ply, "наклоняется и нащупывает пульс на шее человека")
		NYRP.Action(ply, "Нащупываю пульс...", math.max(1.5, 3 - med * 0.25), function()
			ply.nyrpHelping = nil
			if IsValid(rag) then NYRP.Notify(ply, pulseText(rag, med), "info", 9) end
		end, "heart")
	elseif act == "lift" then
		if not IsValid(owner) or not Cond.KO(owner) or owner:GetNW2Bool("nyrp.koCritical") then return end
		meAction(ply, "подхватывает человека под руки и помогает подняться")
		NYRP.Action(ply, "Помогаю подняться...", 4, function()
			ply.nyrpHelping = nil
			if IsValid(owner) and Cond.KO(owner) and owner.nyrpKO and owner.nyrpKO.rag == rag then
				Cond.WakeUp(owner)
				NYRP.Notify(owner, "Вам помогли подняться", "success")
				if NYRP.Skills then NYRP.Skills.AddXP(ply, "medicine", 10) end
			end
		end, "user")
	elseif act == "treat" then
		if not IsValid(owner) or not Cond.KO(owner) then return end
		local slot, it = findMed(ply)
		if not slot then NYRP.Notify(ply, "Нужна аптечка или обезболивающее", "warning") return end
		meAction(ply, "достаёт " .. (it.id == "medkit" and "аптечку" or "шприц") .. " и оказывает первую помощь")
		NYRP.Action(ply, "Оказываю первую помощь...", math.max(3, 8 - med * 0.8), function()
			ply.nyrpHelping = nil
			if not (IsValid(owner) and Cond.KO(owner) and owner.nyrpKO and owner.nyrpKO.rag == rag) then return end
			local inv = NYRP.Inv.Get(ply)
			if not inv.slots[slot] or inv.slots[slot].id ~= it.id then return end
			NYRP.Inv.Take(ply, slot, 1)
			local hp = (it.id == "medkit" and 30 or 18) + med * 6
			Cond.WakeUp(owner, hp)
			NYRP.Notify(owner, "Вам оказали первую помощь", "success")
			NYRP.Notify(ply, "Вы оказали первую помощь", "success")
			if NYRP.Skills then NYRP.Skills.AddXP(ply, "medicine", 25) end
		end, "medkit")
	end
end)

-- Удары по телу достаются хозяину.
hook.Add("EntityTakeDamage", "nyrp.condition.ko", function(ent, dmg)
	local owner = ent.nyrpOwner
	if IsValid(owner) and owner.nyrpKO and owner.nyrpKO.rag == ent and dmg:GetDamage() > 1 then
		-- удары самого тела о землю/стены не считаем
		local att = dmg:GetAttacker()
		if dmg:IsDamageType(DMG_CRUSH) and not (IsValid(att) and att:IsPlayer()) then return end
		local d = DamageInfo()
		d:SetDamage(dmg:GetDamage())
		d:SetDamageType(dmg:GetDamageType())
		d:SetAttacker(IsValid(dmg:GetAttacker()) and dmg:GetAttacker() or game.GetWorld())
		d:SetInflictor(IsValid(dmg:GetInflictor()) and dmg:GetInflictor() or game.GetWorld())
		owner:TakeDamageInfo(d)
	end
end)

-- Без сознания нельзя переключать оружие и самоубиться.
hook.Add("PlayerSwitchWeapon", "nyrp.condition.ko", function(ply) if Cond.KO(ply) then return true end end)
hook.Add("CanPlayerSuicide", "nyrp.condition.ko", function(ply) if Cond.KO(ply) then return false end end)

hook.Add("PlayerDeath", "nyrp.condition.ko", function(ply) if ply.nyrpKO then cleanupKO(ply) end end)
hook.Add("PlayerDisconnected", "nyrp.condition.ko", function(ply) if ply.nyrpKO then cleanupKO(ply) end end)
hook.Add("NYRP.CharacterLoaded", "nyrp.condition.ko", function(ply) if ply.nyrpKO then cleanupKO(ply) end end)

-- Админ-команда для проверки: nyrp_knockout [crit]
concommand.Add("nyrp_knockout", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if IsValid(ply) then Cond.KnockOut(ply, args[1] == "crit") end
end)

-- C-меню → «Упасть»: лечь на землю (встать — Пробел)
net.Receive("nyrp.cmenu.fall", function(_, ply)
	if (ply.nyrpFallNext or 0) > CurTime() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	ply.nyrpFallNext = CurTime() + 3
	if ply:InVehicle() or not ply:OnGround() then return end
	Cond.Fall(ply, true)
end)
