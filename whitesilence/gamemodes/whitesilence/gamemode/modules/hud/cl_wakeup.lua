--[[
	Начало игры — «открываю глаза»: тёмные веки с изогнутым краем, приоткрываются, моргают, открываются;
	картинка сначала размыта и бесцветна, проясняется; слышно дыхание. HUD появляется после.
	Запускается, когда отряд выдвинулся (WSDeployed), и командой ws_wakeup.
]]

local W = {}
WS.Wake = W
local E = WS.Ease

local startT
local LEN = 6.0
local blur = Material("pp/blurscreen")

-- Насколько открыты глаза (0 — закрыты, 1 — открыты) в момент t
local KEYS = { { 0, 0 }, { 1.3, 0 }, { 1.9, 0.28 }, { 2.25, 0.05 }, { 2.6, 0.04 }, { 3.4, 0.55 }, { 3.75, 0.4 }, { 5.0, 1 } }
local function openness(t)
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if t <= b[1] then return Lerp(E.InOutSine((t - a[1]) / (b[1] - a[1])), a[2], b[2]) end
	end
	return 1
end

function W.Start()
	startT = RealTime()
	WS.Audio.Play("whitesilence/game/wake.ogg", { volume = 0.55, fade = 0.5 })
	timer.Simple(5.5, function()
		-- дыхание затихает, когда окончательно проснулся
		for h in pairs(WS.Audio.Active) do if h.path == "whitesilence/game/wake.ogg" then h:Stop(3) end end
	end)
end

function W.Active()
	return startT ~= nil and RealTime() - startT < LEN
end

-- HUD проявляется в последнюю секунду пробуждения
function W.HudAlpha()
	if not startT then return 1 end
	return E.Smooth((RealTime() - startT - (LEN - 1.4)) / 1.2)
end

hook.Add("WSDeployed", "ws.wake", function()
	-- меню гаснет ~1.5 с, затем открываем глаза
	timer.Simple(1.4, W.Start)
end)

local cm = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "ws.wake", function()
	if not W.Active() then return end
	local t = RealTime() - startT
	local k = E.Smooth((t - 2.5) / 3.2)               -- проясняется
	cm["$pp_colour_colour"] = Lerp(k, 0.1, 1)
	cm["$pp_colour_brightness"] = Lerp(k, -0.12, 0)
	cm["$pp_colour_contrast"] = Lerp(k, 0.8, 1)
	DrawColorModify(cm)
end)

-- Веко: от края экрана до изогнутой кромки (у настоящего века щель шире в центре).
-- DrawPoly рисует только выпуклые фигуры, поэтому веко собирается из вертикальных полосок-четырёхугольников.
local N = 24
local function lid(top, open, w, h)
	local half = h / 2
	local function edgeY(x)
		local d = (x - w / 2) / (w / 2)
		local gap = half * open * (1 - 0.55 * d * d * (1 - open ^ 3))   -- полуширина щели; открыв глаза — во весь экран
		return top and (half - gap) or (half + gap)
	end
	for i = 0, N - 1 do
		local x0, x1 = w * i / N, w * (i + 1) / N + 1
		local y0, y1 = edgeY(x0), edgeY(x1)
		if top then
			surface.DrawPoly({ { x = x0, y = -2 }, { x = x1, y = -2 }, { x = x1, y = y1 }, { x = x0, y = y0 } })
		else
			surface.DrawPoly({ { x = x0, y = y0 }, { x = x1, y = y1 }, { x = x1, y = h + 2 }, { x = x0, y = h + 2 } })
		end
	end
end

hook.Add("HUDPaint", "ws.wake", function()
	if not W.Active() then return end
	local w, h = ScrW(), ScrH()
	local t = RealTime() - startT
	local open = openness(t)
	-- размытие, слабеет по мере пробуждения
	local b = (1 - E.Smooth((t - 2.4) / 3.0)) * 6
	if b > 0.05 then
		surface.SetMaterial(blur)
		surface.SetDrawColor(255, 255, 255, 255)
		for i = 1, 3 do
			blur:SetFloat("$blur", b * i / 3)
			blur:Recompute()
			render.UpdateScreenEffectTexture()
			surface.DrawTexturedRect(0, 0, w, h)
		end
	end
	-- веки: несколько слоёв для мягкой кромки
	draw.NoTexture()
	for i, a in ipairs({ 60, 110, 255 }) do
		local o = math.max(0, open - (3 - i) * 0.035)
		surface.SetDrawColor(0, 0, 0, a)
		lid(true, o, w, h)
		lid(false, o, w, h)
	end
	-- в самом начале — полная темнота с лёгким красноватым светом сквозь веки
	local dark = 1 - E.Smooth(t / 1.6)
	surface.SetDrawColor(40, 6, 4, 60 * (1 - open))
	surface.DrawRect(0, 0, w, h)
	if dark > 0 then
		surface.SetDrawColor(0, 0, 0, 255 * dark)
		surface.DrawRect(0, 0, w, h)
	end
end)

concommand.Add("ws_wakeup", function() W.Start() end)
