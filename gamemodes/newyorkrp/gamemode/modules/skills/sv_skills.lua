local SK = NYRP.Skills

local function today() return NYRP.Phone and NYRP.Phone.DayIndex() or math.floor(os.time() / 86400) end

local function sync(ply)
	local c = ply.nyrpChar
	if not c then return end
	for _, s in ipairs(NYRP.Config.Skills) do ply:SetNW2Int("nyrp.skill." .. s.id, c.skills and c.skills[s.id] or 0) end
end
SK.Sync = sync
hook.Add("NYRP.CharacterLoaded", "nyrp.skills", function(...) sync(...) end)

-- SK.AddXP(ply, "combat", 5, "попадание") — опыт с учётом «практики дня», озарения и интеллекта
function SK.AddXP(ply, id, amount, why)
	local c = ply.nyrpChar
	if not c or not amount or amount <= 0 then return end
	c.skills = c.skills or {}
	c.flags = c.flags or {}
	local level = c.skills[id] or 0
	if level >= NYRP.Config.SkillCap then return end
	local xp = c.flags.skillXP or {}
	c.flags.skillXP = xp
	local day = c.flags.skillDay or {}
	c.flags.skillDay = day
	if day.d ~= today() then day.d = today() day.got = {} end
	day.got = day.got or {}
	local got = day.got[id] or 0
	local mult = 1 + (c.skills.intellect or 0) * 0.03
	if got >= SK.DailyFull then mult = mult * 0.5 end
	local chance = SK.InsightChance * ((c.skills.intellect or 0) >= 6 and 1.5 or 1)
	local insight = math.random() < chance
	if insight then mult = mult * 2 end
	local gain = amount * mult
	day.got[id] = got + gain
	xp[id] = (xp[id] or 0) + gain
	if insight then
		net.Start("nyrp.skills.fx") net.WriteString(id) net.WriteBool(false) net.Send(ply)
	end
	while xp[id] >= SK.Need(level) and level < NYRP.Config.SkillCap do
		xp[id] = xp[id] - SK.Need(level)
		level = level + 1
		c.skills[id] = level
		sync(ply)
		if NYRP.ApplyMovement then NYRP.ApplyMovement(ply) end
		net.Start("nyrp.skills.fx") net.WriteString(id) net.WriteBool(true) net.Send(ply)
	end
	ply.nyrpSkillSaveAt = ply.nyrpSkillSaveAt or (CurTime() + 30)
end

-- сохраняем не чаще раза в 30 с
timer.Create("nyrp.skills.save", 10, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply.nyrpSkillSaveAt and CurTime() >= ply.nyrpSkillSaveAt then
			ply.nyrpSkillSaveAt = nil
			if NYRP.Chars.Save then NYRP.Chars.Save(ply) end
		end
	end
end)

net.Receive("nyrp.skills", function(_, ply)
	if (ply.nyrpSkillsNext or 0) > CurTime() or not ply.nyrpChar then return end
	ply.nyrpSkillsNext = CurTime() + 0.5
	local c = ply.nyrpChar
	local day = c.flags and c.flags.skillDay or {}
	net.Start("nyrp.skills")
	net.WriteTable(c.skills or {})
	net.WriteTable(c.flags and c.flags.skillXP or {})
	net.WriteTable(day.d == today() and day.got or {})
	net.Send(ply)
end)

-- --------------------------------------------------------------- источники опыта --
-- выносливость: бег (каждые 10 с), уставший — вдвое
timer.Create("nyrp.skills.run", 10, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply.nyrpChar and ply:KeyDown(IN_SPEED) and ply:GetVelocity():Length2D() > ply:GetWalkSpeed() + 10 then
			local tired = NYRP.Cond and NYRP.Cond.Stamina(ply) < 30
			SK.AddXP(ply, "stamina", tired and 8 or 4)
		end
		-- сила: держит предмет руками
		if ply:Alive() and ply.nyrpChar then
			local w = ply:GetActiveWeapon()
			if IsValid(w) and w:GetClass() == "nyrp_hands" and (w.IsGrabbing and w:IsGrabbing() or ply:GetNW2Bool("nyrp.dragging")) then
				SK.AddXP(ply, "strength", 3)
			end
		end
	end
end)

-- ловкость: прыжки и мягкие приземления
hook.Add("KeyPress", "nyrp.skills.jump", function(ply, key)
	if key ~= IN_JUMP or not ply:OnGround() or (ply.nyrpJumpXP or 0) > CurTime() then return end
	ply.nyrpJumpXP = CurTime() + 2
	SK.AddXP(ply, "agility", 1)
end)
hook.Add("OnPlayerHitGround", "nyrp.skills.land", function(ply, water, floater, speed)
	if speed > 350 and speed < 620 and not water then SK.AddXP(ply, "agility", math.floor((speed - 300) / 40)) end
end)

-- стрельба и сила: попадания
hook.Add("EntityTakeDamage", "nyrp.skills.hit", function(target, dmg)
	local att = dmg:GetAttacker()
	if not IsValid(att) or not att:IsPlayer() or att == target then return end
	if (att.nyrpHitXP or 0) > CurTime() then return end
	att.nyrpHitXP = CurTime() + 0.25
	local living = target:IsPlayer() or target:IsNPC() or target:IsNextBot() or target:GetClass() == "nyrp_npc"
	if dmg:IsBulletDamage() then
		SK.AddXP(att, "combat", living and 4 or 1)
	elseif dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_SLASH) then
		SK.AddXP(att, "strength", living and 4 or 1)
	end
end)

-- сила удара
hook.Add("EntityTakeDamage", "nyrp.skills.strength", function(target, dmg)
	local att = dmg:GetAttacker()
	if not IsValid(att) or not att:IsPlayer() then return end
	if dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_SLASH) then
		local l = SK.Level(att, "strength")
		dmg:ScaleDamage(l >= 6 and 1.25 or l >= 2 and 1.1 or 1)
	end
end)

-- интеллект: новые места города
hook.Add("NYRP.ZoneDiscovered", "nyrp.skills", function(ply) SK.AddXP(ply, "intellect", 15) end)
