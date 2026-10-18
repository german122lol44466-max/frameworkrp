--[[
	Движение и стамина.

	Скорости (шаг, бег, медленный шаг на Alt, присед, прыжок) — из конфига. Стамина тратится на бег и прыжки,
	восстанавливается после паузы. На нуле бег недоступен, пока стамина не поднимется до StaminaRecover.
	Расчёт идёт в SetupMove на сервере и в предсказании клиента (только первый проход), сервер — главный,
	значение уходит клиентам в NW2 (ws_stamina, ws_exhausted).
]]

local C = WS.Config
WS.Move = WS.Move or {}
local MV = WS.Move

function MV.Stamina(ply)
	if CLIENT and ply == LocalPlayer() and ply.wsStamina then return ply.wsStamina end
	return ply:GetNW2Float("ws_stamina", C.StaminaMax)
end

function MV.Exhausted(ply)
	if CLIENT and ply == LocalPlayer() and ply.wsExhausted ~= nil then return ply.wsExhausted end
	return ply:GetNW2Bool("ws_exhausted", false)
end

hook.Add("SetupMove", "ws.move", function(ply, mv, cmd)
	if not ply:Alive() or not WS.Lobby.InGame(ply) then return end
	if CLIENT and ply ~= LocalPlayer() then return end

	local dt = engine.TickInterval()
	local now = CurTime()
	local mutate = SERVER or IsFirstTimePredicted()
	local st = ply.wsStamina or ply:GetNW2Float("ws_stamina", C.StaminaMax)
	local exhausted = ply.wsExhausted or false
	if CLIENT then
		-- если предсказание разошлось с сервером — подтянуться
		local nw = ply:GetNW2Float("ws_stamina", C.StaminaMax)
		if math.abs(nw - st) > 8 then st = nw exhausted = ply:GetNW2Bool("ws_exhausted", false) end
	end

	local moving = mv:GetForwardSpeed() ~= 0 or mv:GetSideSpeed() ~= 0
	local wantSprint = mv:KeyDown(IN_SPEED) and moving and not ply:Crouching()
	if wantSprint and not exhausted and st > 0 then
		if mutate then
			st = st - C.StaminaSprint * dt
			ply.wsLastDrain = now
			if st <= 0 then st = 0 exhausted = true end
		end
	else
		if wantSprint then
			-- бежать нечем: шагом
			mv:SetMaxClientSpeed(C.WalkSpeed)
			mv:SetMaxSpeed(C.WalkSpeed)
		end
		if mutate and now - (ply.wsLastDrain or 0) > C.StaminaRegenDelay then
			-- стоя восстанавливается быстрее, чем на ходу
			st = math.min(C.StaminaMax, st + C.StaminaRegen * (moving and 0.7 or 1.2) * dt)
		end
		if exhausted and st >= C.StaminaRecover then exhausted = false end
	end

	if mv:KeyPressed(IN_JUMP) and ply:IsOnGround() then
		if st < C.StaminaJump then
			mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))   -- нет сил прыгнуть
		elseif mutate then
			st = st - C.StaminaJump
			ply.wsLastDrain = now
		end
	end

	if not mutate then return end
	ply.wsStamina, ply.wsExhausted = st, exhausted
	if SERVER then
		if math.abs(ply:GetNW2Float("ws_stamina", -1) - st) > 0.5 or st == 0 or st == C.StaminaMax then
			ply:SetNW2Float("ws_stamina", st)
		end
		if ply:GetNW2Bool("ws_exhausted", false) ~= exhausted then ply:SetNW2Bool("ws_exhausted", exhausted) end
	end
end)

if SERVER then
	-- скорости ставятся при каждом появлении в игре
	hook.Add("PlayerSpawn", "ws.move", function(ply)
		timer.Simple(0, function()
			if not IsValid(ply) or not WS.Lobby.InGame(ply) then return end
			ply:SetWalkSpeed(C.WalkSpeed)
			ply:SetRunSpeed(C.RunSpeed)
			ply:SetSlowWalkSpeed(C.SlowWalkSpeed)
			ply:SetCrouchedWalkSpeed(C.CrouchFactor)
			ply:SetJumpPower(C.JumpPower)
			ply.wsStamina, ply.wsExhausted = C.StaminaMax, false
			ply:SetNW2Float("ws_stamina", C.StaminaMax)
			ply:SetNW2Bool("ws_exhausted", false)
		end)
	end)
end

if CLIENT then
	-- тяжёлое дыхание, когда выдохся
	local nextBreath = 0
	hook.Add("Think", "ws.move.breath", function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply:Alive() or not WS.Lobby.InGame(ply) then return end
		local st = MV.Stamina(ply)
		local recent = CurTime() - (ply.wsLastDrain or -100) < 4
		if st < 35 and recent and RealTime() > nextBreath then
			local k = 1 - st / 35
			WS.Audio.Play("whitesilence/game/breath" .. math.random(1, 3) .. ".ogg", { volume = 0.25 + 0.45 * k })
			nextBreath = RealTime() + Lerp(k, 1.3, 0.75)
		end
	end)
end
