--[[
	Сервер: выносливость, промокание, урон от падения, потеря сознания и помощь другим игрокам.
]]

local Cond = NYRP.Cond
local S = NYRP.Config.Stamina
local F = NYRP.Config.Fall
local U = NYRP.Config.Unconscious
local cleanupKO -- ниже

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
			if running then
				local skill = ply.nyrpChar and ply.nyrpChar.skills and ply.nyrpChar.skills.stamina or 0
				local drain = 100 / (S.Seconds * (1 + skill * S.PerSkill))
				if ply:Health() < 50 then drain = drain * S.InjuredDrain end
				st = st - drain * TICK
			elseif speed < 8 then
				st = st + S.RegenStand * TICK
			else
				st = st + S.RegenWalk * TICK
			end
			st = math.Clamp(st, 0, 100)
			ply:SetNW2Float("nyrp.stamina", st)
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

hook.Add("NYRP.PlayerSpawned", "nyrp.condition", resetCondition)
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

function Cond.KnockOut(ply, critical)
	if Cond.KO(ply) or not ply:Alive() then return end
	if NYRP.CancelAction then NYRP.CancelAction(ply) end

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

function cleanupKO(ply)
	local ko = ply.nyrpKO
	ply.nyrpKO = nil
	if ko and IsValid(ko.rag) then ko.rag:Remove() end
	ply:SetNW2Bool("nyrp.ko", false)
	ply:SetNW2Bool("nyrp.koCritical", false)
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
	local rag = ply.nyrpKO and ply.nyrpKO.rag
	local pos = IsValid(rag) and standPos(ply, ragdollCenter(rag) - Vector(0, 0, 30)) or ply:GetPos()
	cleanupKO(ply)
	ply:SetPos(pos)
	if hp then ply:SetHealth(math.max(ply:Health(), hp)) end
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
		if help then
			local tr = ply:GetEyeTrace()
			if not IsValid(help) or not ply:KeyDown(IN_USE) or tr.Entity ~= help or tr.HitPos:Distance(ply:EyePos()) > 110 then
				ply.nyrpHelping = nil
				if NYRP.CancelAction then NYRP.CancelAction(ply) end
			end
		end
	end
end)

hook.Add("KeyPress", "nyrp.condition.help", function(ply, key)
	if key ~= IN_USE or not ply:Alive() or Cond.KO(ply) then return end
	local tr = ply:GetEyeTrace()
	local rag = tr.Entity
	if not IsValid(rag) or not IsValid(rag.nyrpOwner) or tr.HitPos:Distance(ply:EyePos()) > 110 then return end
	local owner = rag.nyrpOwner
	if not Cond.KO(owner) then return end
	ply.nyrpHelping = rag
	NYRP.Action(ply, "Оказываю помощь...", U.HelpTime, function()
		ply.nyrpHelping = nil
		if IsValid(owner) and Cond.KO(owner) and owner.nyrpKO and owner.nyrpKO.rag == rag then
			Cond.WakeUp(owner, U.HelpHP)
			NYRP.Notify(owner, "Вам помогли прийти в себя", "success")
			NYRP.Notify(ply, "Вы помогли человеку прийти в себя", "success")
		end
	end, "medkit")
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
