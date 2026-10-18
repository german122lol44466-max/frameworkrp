--[[
	Интро «Белая тишина»: проигрывается при входе на сервер.

	ws_intro          — показать ещё раз
	ws_intro_mode     — 0 никогда, 1 только в первый раз, 2 при каждом входе (по умолчанию)
	ws_volume         — громкость звуков режима
	[ПРОБЕЛ] — пропустить.
]]

local I = WS.Intro
local UI = WS.UI
local E = WS.Ease
local FX = I.FX

local mode = CreateClientConVar("ws_intro_mode", "2", true, false, "Интро: 0 — никогда, 1 — только в первый раз, 2 — при каждом входе", 0, 2)

local M = {}           -- материалы
local panel            -- полноэкранная панель (ловит клавиатуру, чтобы игрок не двигался)
local startTime, lastT
local skipAt
local cueDone, sounds = {}, {}
local outroAt          -- после конца — плавный выход из черноты в игру

local function mat(name, flags)
	return UI.Mat(I.Path .. name, flags)
end

local function loadMaterials()
	M.arcticBg = mat("arctic_bg.jpg")
	M.arcticBlur = mat("arctic_bg_blur.jpg")
	M.squad = mat("arctic_squad.png")
	M.eyes = mat("arctic_eyes.png")
	M.fore = mat("arctic_fore.png")
	M.dead = mat("dead.jpg")
	M.deadBlur = mat("dead_blur.jpg")
	M.cabin = mat("heli_cabin.png")
	M.outside = mat("heli_outside.jpg", "smooth noclamp")
	M.bannerBg = mat("banner_bg.jpg")
	M.logo = mat("scp_logo.png")
	FX.Init()
end

-- ---------------------------------------------------------------- камера и слои

--[[
	Камера: zoom (1 — кадр ровно накрывает экран), fx/fy — точка исходника в центре экрана (0..1), sx/sy — тряска.
	Слои с parallax > 1 ближе к зрителю: сильнее увеличиваются и сдвигаются при движении камеры.
	Сдвиг, не дающий кадру уйти за край, считается по фону и применяется ко всем слоям — иначе они разъедутся.
]]
local function frame(cam)
	local w, h = ScrW(), ScrH()
	local base = math.max(w / I.ImageW, h / I.ImageH)
	local s = base * cam.zoom
	local dw, dh = I.ImageW * s, I.ImageH * s
	local x = w / 2 - cam.fx * dw
	local y = h / 2 - cam.fy * dh
	cam.cx = math.Clamp(x, w - dw, 0) - x
	cam.cy = math.Clamp(y, h - dh, 0) - y
	cam.base = base
	return cam
end

local function layerRect(cam, p)
	local w, h = ScrW(), ScrH()
	local s = cam.base * (1 + (cam.zoom - 1) * p)
	local fx = 0.5 + (cam.fx - 0.5) * p
	local fy = 0.5 + (cam.fy - 0.5) * p
	local dw, dh = I.ImageW * s, I.ImageH * s
	return w / 2 - fx * dw + cam.cx + (cam.sx or 0), h / 2 - fy * dh + cam.cy + (cam.sy or 0), dw, dh
end

local function drawLayer(m, cam, p, a)
	if a <= 0 then return end
	local x, y, dw, dh = layerRect(cam, p or 1)
	surface.SetMaterial(m)
	surface.SetDrawColor(255, 255, 255, 255 * a)
	surface.DrawTexturedRect(x, y, dw, dh)
end

-- Точка исходника -> экран (для слоя с parallax p)
local function toScreen(cam, px, py, p)
	local x, y, dw, dh = layerRect(cam, p or 1)
	return x + px / I.ImageW * dw, y + py / I.ImageH * dh, dw / I.ImageW
end

-- ---------------------------------------------------------------- кадры

local Shot = {}

function Shot.arctic(t, k, dt)
	local cam = frame({ zoom = Lerp(E.InOutSine(k), 1.05, 1.14), fx = Lerp(E.InOutSine(k), 0.53, 0.58), fy = 0.555 })
	-- проявление: из размытого и пересвеченного в резкий кадр
	local sharp = E.Smooth(t / 3.2)
	drawLayer(M.arcticBlur, cam, 1, 1)
	drawLayer(M.arcticBg, cam, 1, sharp)
	FX.Fog(t, 0.22, 40)
	drawLayer(M.squad, cam, 1.02, E.Smooth((t - 0.4) / 2.6))
	FX.Fog(t + 30, 0.18, 70)
	drawLayer(M.fore, cam, 1.3, 1)
	FX.Snow(t, dt, "blizzard", 1, 1)
	surface.SetDrawColor(220, 230, 240, 120 * (1 - E.OutCubic(t / 2.2)))   -- белая вспышка проявления
	surface.DrawRect(0, 0, ScrW(), ScrH())
end

function Shot.closeup(t, k, dt, abs)
	local cam = frame({ zoom = Lerp(E.InOutSine(k), 1.62, 1.74), fx = Lerp(k, 0.585, 0.592), fy = Lerp(k, 0.565, 0.555) })
	drawLayer(M.arcticBg, cam, 1, 1)
	FX.Fog(abs, 0.2, 40)
	drawLayer(M.squad, cam, 1, 1)
	-- бледный отблеск в очках: появляется медленно, дрожит в такт сердцу
	local beat = 0.75 + 0.25 * math.abs(math.sin(abs * 3.6))
	local eyes = E.Smooth((t - 1.8) / 2.6) * beat
	if eyes > 0 then
		UI.Additive(true)
		drawLayer(M.eyes, cam, 1, eyes)
		UI.Additive(false)
	end
	FX.Fog(abs + 30, 0.2, 70)
	drawLayer(M.fore, cam, 1.3, 1)
	FX.Snow(abs, dt, "blizzard", 0.9, 1)
	-- холоднее и темнее, чем в первом кадре
	surface.SetDrawColor(8, 14, 26, 70 + 40 * k)
	surface.DrawRect(0, 0, ScrW(), ScrH())
end

local function radioOn(abs)
	for _, r in ipairs(I.RadioTx) do
		if abs >= r[1] and abs <= r[2] then return true end
	end
	return false
end

function Shot.dead(t, k, dt, abs)
	local cam = frame({ zoom = Lerp(E.OutCubic(k), 1.13, 1.03), fx = Lerp(k, 0.53, 0.5), fy = Lerp(k, 0.5, 0.52) })
	drawLayer(M.deadBlur, cam, 1, 1)
	drawLayer(M.dead, cam, 1, E.Smooth(t / 2.4))
	-- лампочка рации: мигает, во время передачи горит
	local on = radioOn(abs) and (0.85 + 0.15 * math.sin(abs * 40)) or ((math.floor(abs * 1.3) % 2 == 0) and 0.5 or 0)
	if on > 0 then
		local x, y, s = toScreen(cam, I.RadioLed[1], I.RadioLed[2])
		FX.Glow(x, y, 46 * s, Color(255, 40, 30), 0.55 * on)
		FX.Glow(x, y, 12 * s, Color(255, 140, 120), 0.9 * on)
	end
	FX.Fog(abs, 0.12, 25)
	FX.Snow(abs, dt, "calm", 0.6, 1)
end

function Shot.heli(t, k, dt, abs)
	-- вибрация корпуса + медленное покачивание
	local sc = ScrH() / 1080
	local cam = frame({
		zoom = 1.07 + 0.01 * math.sin(abs * 0.5),
		fx = 0.5 + 0.004 * math.sin(abs * 0.33),
		fy = 0.5 + 0.006 * math.sin(abs * 0.71),
		sx = (math.sin(abs * 61) * 1.4 + math.sin(abs * 37.3) * 1.0) * sc,
		sy = (math.sin(abs * 53.7) * 1.6 + math.sin(abs * 17.2) * 0.8) * sc,
	})
	-- вид из двери: тундра проплывает внизу
	local d = I.HeliDoor
	local x0, y0 = toScreen(cam, d[1], d[2])
	local x1, y1 = toScreen(cam, d[3], d[4])
	local dw, dh = x1 - x0, y1 - y0
	render.SetScissorRect(x0 - 4, y0 - 4, x1 + 4, y1 + 4, true)
	local oh = dh * 1.25
	local ow = oh * 4
	local u = (abs * 0.028) % 1
	local v = 0.06 + 0.04 * math.sin(abs * 0.4)
	surface.SetMaterial(M.outside)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRectUV(x0 - 4, y0 - 4, dw + 8, dh + 8, u, v, u + dw / ow, v + dh / oh)
	FX.Streaks(dt, x0, y0, dw, dh, 1)
	render.SetScissorRect(0, 0, 0, 0, false)

	drawLayer(M.cabin, cam, 1, 1)
	-- дежурная красная лампа, подрагивает
	local lx, ly, s = toScreen(cam, I.HeliLamp[1], I.HeliLamp[2])
	local flick = 0.8 + 0.1 * math.sin(abs * 9) + (math.random() < 0.03 and -0.3 or 0)
	FX.Glow(lx, ly, 520 * s, Color(255, 30, 20), 0.22 * flick)
	FX.Glow(lx, ly, 70 * s, Color(255, 120, 100), 0.7 * flick)
	-- холодный свет из двери
	FX.Glow((x0 + x1) / 2, (y0 + y1) / 2, dw * 0.9, Color(150, 180, 220), 0.08)
end

function Shot.banner(t, k, dt, abs)
	local w, h = ScrW(), ScrH()
	surface.SetMaterial(M.bannerBg)
	surface.SetDrawColor(255, 255, 255, 255)
	local base = math.max(w / I.ImageW, h / I.ImageH)
	surface.DrawTexturedRect(w / 2 - I.ImageW * base / 2, h / 2 - I.ImageH * base / 2, I.ImageW * base, I.ImageH * base)
	-- знак: «включается» с парой вспышек, как старая лампа, и медленно садится на место
	local a = E.Smooth(t / 0.9)
	if t < 0.9 then a = a * ((math.floor(t * 18) % 3 == 0) and 0.3 or 1) end
	local size = h * 0.30 * Lerp(E.OutExpo(t / 3), 1.08, 1)
	local cx, cy = w / 2, h * 0.43
	FX.Glow(cx, cy, size * 1.2, Color(120, 150, 190), 0.12 * a * (0.8 + 0.2 * math.sin(abs * 2)))
	surface.SetMaterial(M.logo)
	surface.SetDrawColor(255, 255, 255, 255 * a)
	surface.DrawTexturedRect(cx - size / 2, cy - size / 2, size, size)
	-- красная черта между знаком и надписью
	local lw = w * 0.16 * E.OutCubic((t - 0.8) / 1.6)
	local c = WS.Config.Color.accent
	surface.SetDrawColor(c.r, c.g, c.b, 220 * a)
	surface.DrawRect(cx - lw / 2, h * 0.635, lw, math.max(2, h / 540))
end

-- ---------------------------------------------------------------- титры

local styles = {
	caps = function() return WS.Font("titlelight", 30), WS.Font("titlelight", 30, 6), 30 * ScrH() / 1080 * 0.35, 14, WS.Config.Color.frost end,
	story = function() return WS.Font("storyi", 50), WS.Font("storyi", 50, 8), 0, 34, WS.Config.Color.text end,
	line = function() return WS.Font("story", 36), WS.Font("story", 36, 6), 0, 40, Color(205, 212, 222) end,
	brand = function() return WS.Font("title", 66), WS.Font("title", 66, 10), 66 * ScrH() / 1080 * 0.3, 16, WS.Config.Color.text end,
	motto = function() return WS.Font("titlelight", 26), nil, 26 * ScrH() / 1080 * 0.45, 22, WS.Config.Color.dim end,
}

local function drawTexts(t)
	local w, h = ScrW(), ScrH()
	for _, tx in ipairs(I.Texts) do
		if t >= tx.at and t <= tx.to + 1.2 then
			local font, glow, spacing, cps, col = styles[tx.style]()
			local a = 1 - E.Smooth((t - tx.to) / 1.1)
			if tx.shade then
				-- мягкая тёмная подложка под титрами на светлом снегу
				FX.Shade(w / 2, h * (tx.y + 0.05), w * 0.9, h * 0.34, 0.75 * a)
			end
			UI.Reveal(tx.text, {
				font = font, glow = glow, spacing = spacing, cps = cps, fade = 0.7,
				x = w / 2, y = h * tx.y, maxW = w * 0.62, t = t - tx.at, alpha = a, color = col,
			})
		end
	end
end

-- [ПРОБЕЛ] — Пропустить (снизу справа)
local function drawSkipHint(t)
	local a = E.Smooth((t - 1.0) / 1.0) * (skipAt and 0 or 1) * (0.75 + 0.25 * math.sin(t * 2.2))
	if a <= 0 then return end
	local w, h = ScrW(), ScrH()
	local sc = h / 1080
	local fk, ft = WS.Font("mono", 15), WS.Font("mono", 17)
	surface.SetFont(ft)
	local tw, th = surface.GetTextSize("— Пропустить")
	surface.SetFont(fk)
	local kw, kh = surface.GetTextSize("ПРОБЕЛ")
	local pad = 10 * sc
	local x = w - 48 * sc - tw - kw - pad * 3
	local y = h - 46 * sc - th
	local bw, bh = kw + pad * 2, kh + pad * 0.9
	local by = y + th / 2 - bh / 2
	draw.RoundedBox(4 * sc, x, by, bw, bh, Color(255, 255, 255, 18 * a))
	surface.SetDrawColor(220, 228, 238, 150 * a)
	surface.DrawOutlinedRect(x, by, bw, bh, math.max(1, math.floor(sc)))
	draw.SimpleText("ПРОБЕЛ", fk, x + bw / 2, by + bh / 2, Color(232, 236, 242, 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("— Пропустить", ft, x + bw + pad, y + th / 2, Color(200, 208, 218, 210 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- ---------------------------------------------------------------- звук

local function runCues(t)
	for i, c in ipairs(I.Cues) do
		if not cueDone[i] and t >= c.at then
			cueDone[i] = true
			if c.play then
				local h = WS.Audio.Play(I.Path .. c.play .. ".ogg", { volume = c.vol or 1, fade = c.fade, loop = c.loop })
				sounds[c.id or ("cue" .. i)] = h
			elseif c.fade and sounds[c.fade] then
				sounds[c.fade]:Fade(c.vol or 0, c.time or 1)
			elseif c.stop and sounds[c.stop] then
				sounds[c.stop]:Stop(c.time or 1)
			end
		end
	end
end

-- ---------------------------------------------------------------- проигрывание

local function finish()
	if IsValid(panel) then panel:Remove() end
	panel = nil
	startTime = nil
	outroAt = RealTime()
	for _, h in pairs(sounds) do h:Stop(1.5) end
	sounds = {}
	net.Start("ws.intro")
	net.WriteBool(false)
	net.SendToServer()
	hook.Run("WSIntroFinished")
end

local function paint(_, w, h)
	local now = RealTime()
	local t = now - startTime
	local dt = math.Clamp(now - (lastT or now), 0, 0.1)
	lastT = now

	if skipAt and now - skipAt > 0.9 then finish() return end
	if t >= I.Length then finish() return end
	runCues(t)

	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, w, h)

	for _, s in ipairs(I.Shots) do
		if t >= s.from and t <= s.to then
			local lt = t - s.from
			Shot[s.id](lt, lt / (s.to - s.from), dt, t)
			-- затемнение на входе и выходе кадра
			local v = E.Window(t, s.from, s.to - s.fadeOut, s.fadeIn, s.fadeOut)
			if v < 1 then
				surface.SetDrawColor(0, 0, 0, 255 * (1 - v))
				surface.DrawRect(0, 0, w, h)
			end
		end
	end

	FX.Vignette(0.85)
	FX.Grain(1)
	drawTexts(t)
	local lb = E.OutCubic(t / 1.6) * (1 - E.Smooth((t - (I.Length - 1.2)) / 1.2))
	FX.Letterbox(lb)
	drawSkipHint(t)

	if skipAt then
		surface.SetDrawColor(0, 0, 0, 255 * E.Smooth((now - skipAt) / 0.8))
		surface.DrawRect(0, 0, w, h)
	end
end

function I.Skip()
	if not startTime or skipAt then return end
	skipAt = RealTime()
	for _, h in pairs(sounds) do h:Stop(0.8) end
	WS.Audio.Play(I.Path .. "skip.ogg", { volume = 0.6 })
end

function I.Start()
	if IsValid(panel) then panel:Remove() end
	WS.Audio.StopAll(0.3)
	loadMaterials()
	startTime = RealTime()
	lastT = nil
	skipAt = nil
	outroAt = nil
	cueDone, sounds = {}, {}

	panel = vgui.Create("EditablePanel")
	panel:SetSize(ScrW(), ScrH())
	panel:SetPos(0, 0)
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(true)
	panel:SetMouseInputEnabled(true)
	panel:SetCursor("blank")
	panel.Paint = paint
	panel.OnKeyCodePressed = function(_, code)
		if code == KEY_SPACE then I.Skip() end
	end

	cookie.Set("ws_intro_seen", "1")
	net.Start("ws.intro")
	net.WriteBool(true)
	net.SendToServer()
end

function I.IsPlaying()
	return startTime ~= nil
end

-- Пока идёт интро — никакого HUD. После — 1.5 с выход из черноты в игру.
hook.Add("HUDShouldDraw", "ws.intro", function()
	if startTime then return false end
end)

hook.Add("OnScreenSizeChanged", "ws.intro", function()
	if IsValid(panel) then panel:SetSize(ScrW(), ScrH()) end
end)

hook.Add("HUDPaint", "ws.intro.outro", function()
	if not outroAt then return end
	local k = (RealTime() - outroAt) / 1.6
	if k >= 1 then outroAt = nil return end
	surface.SetDrawColor(0, 0, 0, 255 * (1 - E.Smooth(k)))
	surface.DrawRect(0, 0, ScrW(), ScrH())
end)

local function shouldPlay()
	local force = GetConVar("ws_intro_force")
	if force and force:GetBool() then return true end
	local m = mode:GetInt()
	if m == 0 then return false end
	if m == 1 then return cookie.GetString("ws_intro_seen", "0") ~= "1" end
	return true
end

hook.Add("InitPostEntity", "ws.intro", function()
	-- небольшая пауза: пусть загрузка карты договорит, а звук успеет подняться
	timer.Simple(0.6, function()
		if shouldPlay() then I.Start() end
	end)
end)

concommand.Add("ws_intro", function() I.Start() end)
concommand.Add("ws_intro_skip", function() I.Skip() end)
