--[[
	Нормальная ходьба, бег и прыжки:
	- шаг 110, бег 225, медленный шаг 70 (Config.Movement);
	- бег спиной/боком медленнее;
	- после приземления короткое замедление и пауза перед следующим прыжком (без распрыжки).
	Всё считается в SetupMove — одинаково на клиенте и сервере, поэтому предсказание не дёргается.
]]

local M = NYRP.Config.Movement

if SERVER then
	-- Вызывается при спавне персонажа (и при смене навыков/одежды).
	function NYRP.ApplyMovement(ply)
		local skills = ply.nyrpChar and ply.nyrpChar.skills or {}
		local runBonus = 1 + (skills.stamina or 0) * 0.02 + (ply.nyrpSpeedBonus or 0)
		ply:SetWalkSpeed(M.Walk)
		ply:SetRunSpeed(M.Run * runBonus)
		ply:SetSlowWalkSpeed(M.SlowWalk)
		ply:SetCrouchedWalkSpeed(M.CrouchFactor)
		ply:SetJumpPower(M.Jump * (1 + (skills.agility or 0) * 0.03))
		ply:SetDuckSpeed(0.35)
		ply:SetUnDuckSpeed(0.35)
		ply:SetLadderClimbSpeed(120)
	end
end

hook.Add("OnPlayerHitGround", "nyrp.movement", function(ply, inWater, onFloater, speed)
	ply.nyrpLanded = CurTime()
	ply.nyrpLandSpeed = speed
end)

hook.Add("SetupMove", "nyrp.movement", function(ply, mv, cmd)
	if ply:GetMoveType() ~= MOVETYPE_WALK then return end

	local max = mv:GetMaxClientSpeed()
	local Cond = NYRP.Cond

	-- выдохся / перелом — бежать нельзя; травмы замедляют
	if Cond and Cond.SpeedFactor then
		if mv:KeyDown(IN_SPEED) and not Cond.CanSprint(ply) then
			max = math.min(max, ply:GetWalkSpeed())
		end
		max = max * Cond.SpeedFactor(ply)
		if Cond.KO(ply) then max = 0 end
	end

	-- бег спиной и боком
	if mv:KeyDown(IN_SPEED) and mv:GetForwardSpeed() <= 0 then
		max = math.min(max, ply:GetRunSpeed() * M.BackwardFactor)
	end

	-- приземление
	local since = CurTime() - (ply.nyrpLanded or 0)
	if since < 0.4 then
		local hard = math.Clamp(((ply.nyrpLandSpeed or 0) - 200) / 400, 0, 1)
		local factor = Lerp(since / 0.4, Lerp(hard, M.LandSlowdown + 0.2, M.LandSlowdown), 1)
		max = max * factor
	end
	if since < M.JumpCooldown and ply:OnGround() then
		mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
	end

	mv:SetMaxClientSpeed(max)
	mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(), max))
end)
