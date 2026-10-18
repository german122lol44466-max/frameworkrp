--[[
	Приборы зрения: ПНВ (клавиша фонарика, по умолчанию F) и тепловизор (N).

	ПНВ: картинка в зелёных тонах, зерно, «труба» окуляра, лёгкое свечение; вокруг игрока — локальный зелёный свет
	(динамический, виден только ему). Тепловизор: мир — тёмно-серый, люди и NPC — белые («белое — горячее»).
	Общая батарея: NVGBattery секунд работы, заряжается, пока прибор выключен. На нуле прибор гаснет.
]]

local V = {}
WS.Vision = V
local C = WS.Config
local UI = WS.UI

V.Mode = nil          -- nil | "nvg" | "thermal"
V.Battery = C.NVGBattery
local switchT = 0     -- момент переключения (короткая вспышка при включении)

local function canUse()
	local ply = LocalPlayer()
	return IsValid(ply) and ply:Alive() and WS.Lobby.InGame(ply)
end

local white = Material("models/debug/debugwhite")

local function setThermalNPCs(on)
	for _, e in ipairs(ents.GetAll()) do
		if e:IsNPC() or e:IsNextBot() then
			e.RenderOverride = on and function(self)
				render.SuppressEngineLighting(true)
				render.MaterialOverride(white)
				render.SetColorModulation(1, 0.97, 0.9)
				self:DrawModel()
				render.SetColorModulation(1, 1, 1)
				render.MaterialOverride()
				render.SuppressEngineLighting(false)
			end or nil
		end
	end
end

function V.Set(mode)
	if mode == V.Mode then mode = nil end
	if mode and not canUse() then return end
	if mode and V.Battery < 3 then
		WS.Audio.Play("whitesilence/game/battery_low.ogg", { volume = 0.6 })
		return
	end
	local old = V.Mode
	V.Mode = mode
	switchT = RealTime()
	if old == "thermal" or mode == "thermal" then setThermalNPCs(mode == "thermal") end
	if mode == "nvg" then
		WS.Audio.Play("whitesilence/game/nvg_on.ogg", { volume = 0.55 })
	elseif mode == "thermal" then
		WS.Audio.Play("whitesilence/game/thermal_on.ogg", { volume = 0.55 })
	elseif old then
		WS.Audio.Play("whitesilence/game/nvg_off.ogg", { volume = 0.5 })
	end
end

-- F (фонарик) → ПНВ
hook.Add("PlayerBindPress", "ws.vision", function(ply, bind, pressed)
	if pressed and string.find(bind, "impulse 100", 1, true) then
		V.Set("nvg")
		return true
	end
end)

-- N → тепловизор (опрос клавиши: у N нет стандартной привязки)
local nDown = false
hook.Add("Think", "ws.vision", function()
	local down = input.IsKeyDown(KEY_N) and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible()
		and not (WS.Chat and WS.Chat.IsOpen and WS.Chat.IsOpen())
	if down and not nDown then V.Set("thermal") end
	nDown = down

	local dt = FrameTime()
	if V.Mode then
		V.Battery = math.max(0, V.Battery - dt)
		if V.Battery <= 0 then
			V.Set(nil)
			WS.Audio.Play("whitesilence/game/battery_low.ogg", { volume = 0.6 })
		elseif not canUse() then
			V.Set(nil)
		end
	else
		V.Battery = math.min(C.NVGBattery, V.Battery + dt * C.NVGRecharge)
	end

	-- локальный зелёный свет ПНВ: подсвечивает всё в нескольких метрах вокруг
	if V.Mode == "nvg" then
		local ply = LocalPlayer()
		local d = DynamicLight(ply:EntIndex() + 4096)
		if d then
			d.pos = ply:EyePos() + ply:EyeAngles():Forward() * 24
			d.r, d.g, d.b = 70, 255, 90
			d.brightness = 1.2
			d.size = 650
			d.decay = 2000
			d.dietime = CurTime() + 0.15
			d.style = 0
		end
	end
end)

-- тепловизор: игроки «горят» белым
hook.Add("PrePlayerDraw", "ws.vision", function(ply)
	if V.Mode ~= "thermal" then return end
	render.SuppressEngineLighting(true)
	render.MaterialOverride(white)
	render.SetColorModulation(1, 0.97, 0.9)
end)

hook.Add("PostPlayerDraw", "ws.vision", function(ply)
	if V.Mode ~= "thermal" then return end
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride()
	render.SuppressEngineLighting(false)
end)

hook.Add("OnEntityCreated", "ws.vision", function(e)
	if V.Mode == "thermal" then timer.Simple(0, function() if IsValid(e) then setThermalNPCs(true) end end) end
end)

local nvgCM = {
	["$pp_colour_addr"] = -0.04, ["$pp_colour_addg"] = 0.10, ["$pp_colour_addb"] = -0.04,
	["$pp_colour_brightness"] = 0.04, ["$pp_colour_contrast"] = 1.55, ["$pp_colour_colour"] = 0,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0.6, ["$pp_colour_mulb"] = 0,
}
local thermalCM = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.01,
	["$pp_colour_brightness"] = -0.16, ["$pp_colour_contrast"] = 1.35, ["$pp_colour_colour"] = 0,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "ws.vision", function()
	if not V.Mode then return end
	local k = math.Clamp((RealTime() - switchT) / 0.35, 0, 1)   -- прибор «прогревается»
	if V.Mode == "nvg" then
		nvgCM["$pp_colour_brightness"] = 0.04 + (1 - k) * 0.4
		DrawColorModify(nvgCM)
		DrawBloom(0.55, 1.6, 6, 6, 1, 1, 0.3, 1, 0.4)
	else
		thermalCM["$pp_colour_brightness"] = -0.16 + (1 - k) * 0.5
		DrawColorModify(thermalCM)
		DrawSharpen(0.6, 0.6)
	end
end)

-- поверх: зерно, «труба» окуляра, полосы — в HUDPaint, чтобы рисовалось над миром, но под интерфейсом
hook.Add("HUDPaint", "ws.vision", function()
	if not V.Mode then return end
	local w, h = ScrW(), ScrH()
	local FX = WS.Intro.FX
	FX.Ensure()
	FX.Grain(V.Mode == "nvg" and 3.2 or 2.2)
	if V.Mode == "nvg" then
		surface.SetDrawColor(20, 255, 60, 10)
		surface.DrawRect(0, 0, w, h)
		-- строчки развёртки
		local off = (RealTime() * 40) % 4
		surface.SetDrawColor(0, 0, 0, 22)
		for y = off, h, 4 do surface.DrawRect(0, y, w, 1) end
	end
	FX.Vignette(1)
	FX.Vignette(V.Mode == "nvg" and 0.9 or 0.5)
end)
