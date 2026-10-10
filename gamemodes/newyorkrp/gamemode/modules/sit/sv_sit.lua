local S = NYRP.Sit

local function tooClose(pos, self)
	for _, p in ipairs(player.GetAll()) do
		if p ~= self and S.Sitting(p) and p:GetPos():DistToSqr(pos) < 16 * 16 then return true end
	end
end

-- найти место: поверхность, куда смотрит игрок
function S.FindSpot(ply)
	local start = ply:EyePos()
	local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * 110, filter = ply, mask = MASK_SOLID })
	if not tr.Hit or tr.HitNormal.z < 0.7 or tr.HitSky then return nil, "Здесь не сесть" end
	local e = tr.Entity
	if IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsVehicle() or e:IsRagdoll()) then return nil, "Здесь не сесть" end
	local h = tr.HitPos.z - ply:GetPos().z
	if h > 42 or h < -24 then return nil, "Слишком высоко или низко" end
	-- над сиденьем должно быть место для корпуса
	local up = util.TraceLine({ start = tr.HitPos + Vector(0, 0, 2), endpos = tr.HitPos + Vector(0, 0, 40), filter = ply, mask = MASK_SOLID })
	if up.Hit then return nil, "Мало места" end
	if tooClose(tr.HitPos, ply) then return nil, "Занято" end
	local ground = h < 8 and (not IsValid(e) or e:IsWorld())
	local yaw = ground and ply:EyeAngles().y or (ply:EyeAngles().y + 180)
	return tr.HitPos, yaw, ground, e
end

function S.SitDown(ply)
	if S.Sitting(ply) or not ply:Alive() or ply:InVehicle() or not ply:OnGround() then return end
	if NYRP.Cond and NYRP.Cond.KO(ply) then return end
	if NYRP.Factions and NYRP.Factions.Cuffed and NYRP.Factions.Cuffed(ply) and ply.nyrpDraggedBy then return end
	local pos, yaw, ground, ent = S.FindSpot(ply)
	if not pos then NYRP.Notify(ply, yaw, "info", 2) return end
	ply.nyrpSit = { stand = ply:GetPos(), view = ply:GetViewOffset(), ent = IsValid(ent) and not ent:IsWorld() and ent or nil,
		entPos = IsValid(ent) and ent:GetPos() or nil, group = ply:GetCollisionGroup() }
	ply:SetNW2Bool("nyrp.sit", true)
	ply:SetNW2Bool("nyrp.sitGround", ground)
	ply:SetNW2Vector("nyrp.sitPos", pos)
	ply:SetNW2Float("nyrp.sitYaw", yaw)
	ply:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	ply:SetMoveType(MOVETYPE_NONE)
	ply:SetPos(pos)
	ply:SetVelocity(-ply:GetVelocity())
	local v = ply.nyrpSit.view
	ply:SetViewOffset(Vector(0, 0, v.z * (ground and 0.42 or 0.5)))
	ply:SetEyeAngles(Angle(0, yaw, 0))
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 45, 90, 0.5)
end

function S.StandUp(ply, noMove)
	local d = ply.nyrpSit
	if not S.Sitting(ply) and not d then return end
	ply.nyrpSit = nil
	ply:SetNW2Bool("nyrp.sit", false)
	ply:SetNW2Bool("nyrp.sitGround", false)
	ply:SetMoveType(MOVETYPE_WALK)
	if d then
		ply:SetCollisionGroup(d.group or COLLISION_GROUP_PLAYER)
		ply:SetViewOffset(d.view)
		if not noMove and ply:Alive() then
			-- встаём туда, откуда садились (если там свободно), иначе — рядом
			local mins, maxs = ply:GetHull()
			for _, p in ipairs({ d.stand, d.stand + Vector(0, 0, 8), ply:GetPos() + Vector(0, 0, 4) }) do
				local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
				if not tr.Hit then ply:SetPos(p) break end
			end
		end
	end
end

hook.Add("KeyPress", "nyrp.sit", function(ply, key)
	if S.Sitting(ply) then
		if key == IN_JUMP or (key == IN_USE and ply:KeyDown(IN_WALK)) then
			if (ply.nyrpSitAt or 0) < CurTime() then S.StandUp(ply) end
		end
		return
	end
	if key == IN_USE and ply:KeyDown(IN_WALK) then
		ply.nyrpSitAt = CurTime() + 0.6
		S.SitDown(ply)
	end
end)

-- Alt + E не должно поднимать стул и открывать двери
hook.Add("PlayerUse", "nyrp.sit", function(ply) if ply:KeyDown(IN_WALK) or S.Sitting(ply) then return false end end)
hook.Add("PlayerDeath", "nyrp.sit", function(ply) S.StandUp(ply, true) end)
hook.Add("PlayerSpawn", "nyrp.sit", function(ply) S.StandUp(ply, true) end)
hook.Add("PlayerEnteredVehicle", "nyrp.sit", function(ply) S.StandUp(ply, true) end)

-- стул унесли / сломали — встаём
timer.Create("nyrp.sit.check", 0.5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local d = ply.nyrpSit
		if d then
			if (NYRP.Cond and NYRP.Cond.KO(ply)) or not ply:Alive() then
				S.StandUp(ply, true)
			elseif d.ent ~= nil and (not IsValid(d.ent) or d.ent:GetPos():DistToSqr(d.entPos) > 12 * 12) then
				S.StandUp(ply)
			end
		end
	end
end)
