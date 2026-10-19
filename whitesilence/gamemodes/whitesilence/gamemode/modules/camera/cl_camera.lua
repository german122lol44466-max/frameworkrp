--[[
	Иммерсивная камера от первого лица (поверх камеры режима и оружия TFA, а не вместо неё):
	  • покачивание головы в такт шагам (ходьба, бег, присед), шаг отдаётся в камеру;
	  • наклон головы при движении вбок и при поворотах;
	  • «присед» камеры при приземлении — сильнее с высоты;
	  • дыхание: лёгкое покачивание на месте, тяжёлое — после бега и на исходе стамины;
	  • толчок взгляда от попаданий;
	  • бег — чуть шире угол обзора.
	ws_camera 0 — выключить (ws_camera_bob — сила покачивания, 0..2).
]]

local CAM = {}
WS.Camera = CAM

local enabled = CreateClientConVar("ws_camera", "1", true, false, "Иммерсивная камера", 0, 1)
local bobScale = CreateClientConVar("ws_camera_bob", "1", true, false, "Сила покачивания камеры", 0, 2)

local cycle = 0              -- фаза шага
local bobAmt = 0             -- 0..1 насколько идёт покачивание
local roll, yawRoll = 0, 0
local land, landVel = 0, 0   -- смещение вниз при приземлении (пружина)
local wasOnGround, fallSpeed = true, 0
local punch = Angle(0, 0, 0)
local punchVel = Angle(0, 0, 0)
local fovAdd = 0
local lastYaw
local breath = 0

local function active(ply)
	if not enabled:GetBool() then return false end
	if not ply:Alive() or not WS.Lobby.InGame(ply) then return false end
	if ply:InVehicle() or ply:GetMoveType() == MOVETYPE_NOCLIP or ply:GetViewEntity() ~= ply then return false end
	if WS.Story and WS.Story.Editor and WS.Story.Editor.on then return false end
	return true
end

-- Толчок при уроне: сторона и сила
function CAM.Punch(p, y, r)
	punchVel = punchVel + Angle(p, y, r)
end

local lastHP
hook.Add("Think", "ws.camera", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local hp = ply:Health()
	if lastHP and hp < lastHP and ply:Alive() then
		local k = math.Clamp((lastHP - hp) / 25, 0.3, 1.6)
		CAM.Punch(math.Rand(-3, -6) * k, math.Rand(-2.5, 2.5) * k, math.Rand(-4, 4) * k)
	end
	lastHP = hp
end)

hook.Add("CalcView", "ws.camera", function(ply, origin, angles, fov, znear, zfar)
	if not active(ply) then return end
	-- сначала обычная камера режима и оружия (TFA прицеливание и т. п.)
	local view = GAMEMODE:CalcView(ply, origin, angles, fov, znear, zfar) or { origin = origin, angles = angles, fov = fov }
	view.origin = view.origin or origin
	view.angles = view.angles or angles
	view.fov = view.fov or fov
	local dt = math.min(FrameTime(), 0.05)
	local vel = ply:GetVelocity()
	local speed = vel:Length2D()
	local onGround = ply:IsOnGround()
	local scale = bobScale:GetFloat()
	local wep = ply:GetActiveWeapon()
	local aiming = IsValid(wep) and wep.GetIronSights and wep:GetIronSights()
	if aiming then scale = scale * 0.25 end

	-- шаг
	local run = speed > WS.Config.WalkSpeed + 25
	local crouch = ply:Crouching()
	local freq = run and 10.5 or (crouch and 5.5 or 7.5)
	local want = onGround and math.Clamp(speed / 150, 0, 1.3) or 0
	bobAmt = WS.Approach(bobAmt, want, 4)
	cycle = cycle + dt * freq * math.Clamp(speed / (run and 220 or 115), 0.4, 1.3)
	local amp = (run and 1.6 or 0.9) * bobAmt * scale
	local right = view.angles:Right()
	local up = view.angles:Up()
	local bobZ = -math.abs(math.sin(cycle)) * amp * 1.4 + amp * 0.7
	local bobX = math.cos(cycle) * amp * 0.9
	view.origin = view.origin + up * bobZ + right * bobX

	-- наклон: вбок при стрейфе и при повороте
	local side = vel:Dot(right) / 220
	local yaw = view.angles.y
	local dyaw = lastYaw and math.AngleDifference(yaw, lastYaw) / math.max(dt, 0.001) or 0
	lastYaw = yaw
	roll = Lerp(math.min(dt * 6, 1), roll, math.Clamp(side * 2.2, -2.5, 2.5) * scale)
	yawRoll = Lerp(math.min(dt * 4, 1), yawRoll, math.Clamp(-dyaw / 400, -1.2, 1.2) * scale)

	-- приземление: пружина
	if not onGround then fallSpeed = math.max(fallSpeed, -vel.z) end
	if onGround and not wasOnGround and fallSpeed > 120 then
		landVel = landVel - math.Clamp((fallSpeed - 100) / 18, 2, 22)
		CAM.Punch(math.Clamp(fallSpeed / 110, 1, 6), 0, math.Rand(-1, 1))
	end
	if onGround then fallSpeed = 0 end
	wasOnGround = onGround
	landVel = landVel + (-land * 120 - landVel * 14) * dt
	land = land + landVel * dt
	view.origin = view.origin + Vector(0, 0, land)

	-- дыхание: сильнее после бега и при низкой стамине
	local st = WS.Move and WS.Move.Stamina and WS.Move.Stamina(ply) or WS.Config.StaminaMax
	local tired = 1 - math.Clamp(st / WS.Config.StaminaMax, 0, 1)
	breath = breath + dt * (1.1 + tired * 1.6)
	local bA = (0.25 + tired * 1.2) * (1 - bobAmt * 0.7) * (aiming and 0.5 or 1)
	local bp, by = math.sin(breath) * bA * 0.6, math.cos(breath * 0.5) * bA * 0.4

	-- толчки от попаданий: пружина
	punchVel = punchVel + Angle(-punch.p * 90, -punch.y * 90, -punch.r * 90) * dt - punchVel * math.min(dt * 12, 1)
	punch = punch + punchVel * dt

	local ang = Angle(view.angles.p + bp + bobZ * 0.25 + punch.p, view.angles.y + by + punch.y,
		view.angles.r + roll + yawRoll + math.sin(cycle * 0.5) * amp * 0.35 + punch.r)
	view.angles = ang

	-- бег — шире обзор
	fovAdd = Lerp(math.min(dt * 5, 1), fovAdd, (run and onGround and not aiming) and 5 or 0)
	view.fov = view.fov + fovAdd
	return view
end)

-- наклон оружия вместе с головой (для не-TFA оружия; применяет cl_hands.lua — один хук на модель оружия)
function CAM.Roll()
	local ply = LocalPlayer()
	if not active(ply) then return 0 end
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep.IsTFAWeapon then return 0 end
	return -roll * 0.6
end
