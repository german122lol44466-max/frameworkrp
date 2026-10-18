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
	for _, sh in ipairs(I.Shots) do
		if sh.image then
			M[sh.image] = mat(sh.image .. ".jpg")
			M[sh.image .. "_blur"] = mat(sh.image .. "_blur.jpg")
		end
	end
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

local function radioOn(abs)
	for _, r in ipairs(I.RadioTx) do
		if abs >= r[1] and abs <= r[2] then return true end
	end
	return false
end

-- Особенности отдельных кадров: before — поверх картины до снега, after — поверх всего.
local Extra = {}

-- Заставка: темнота, холодное свечение в центре, надпись архива Фонда и тонкая черта, расходящаяся в стороны
function Extra.opening(cam, t, k, abs)
	local w, h = ScrW(), ScrH()
	local sc = h / 1080
	local glow = E.Smooth(t / 1.6) * (1 - E.Smooth((t - 2.2) / 0.6))
	FX.Glow(w / 2, h * 0.5, h * 0.9, Color(70, 95, 130), 0.18 * glow)
	for _, tx in ipairs(I.Opening) do
		if t >= tx.at and t <= tx.to + 0.6 then
			local a = 1 - E.Smooth((t - tx.to) / 0.6)
			local kick = tx.style == "kicker"
			UI.Reveal(tx.text, {
				font = kick and WS.Font("sub", 26) or WS.Font("submed", 30),
				spacing = (kick and 7 or 2.5) * sc, cps = kick and 40 or 70, fade = 0.5, rise = 2, shadow = 0.6,
				color = kick and Color(226, 190, 120) or Color(200, 208, 220),
				x = w / 2, y = h * (kick and 0.445 or 0.515), maxW = w * 0.8, t = t - tx.at, alpha = a,
			})
		end
	end
	local lw = w * 0.22 * E.OutCubic((t - 0.6) / 1.2) * (1 - E.Smooth((t - 2.2) / 0.6))
	if lw > 1 then
		local c = WS.Config.Color.accent
		surface.SetDrawColor(c.r, c.g, c.b, 200)
		surface.DrawRect(w / 2 - lw / 2, h * 0.497, lw, math.max(1, math.Round(sc * 1.5)))
	end
end

-- Отблески в очках отряда: разгораются медленно и дрожат в такт сердцу
function Extra.closeup(cam, t, k, abs)
	local beat = 0.75 + 0.25 * math.abs(math.sin(abs * 3.6))
	local a = E.Smooth((t - 1.8) / 2.6) * beat
	if a <= 0 then return end
	for _, e in ipairs(I.Eyes) do
		local x, y, s = toScreen(cam, e[1], e[2])
		FX.Glow(x, y, (e[3] or 26) * s, Color(150, 210, 255), 0.5 * a)
		FX.Glow(x, y, (e[3] or 26) * 0.35 * s, Color(230, 245, 255), 0.95 * a)
	end
end

-- Лампочка рации: мигает, во время передачи горит
function Extra.dead(cam, t, k, abs)
	local on = radioOn(abs) and (0.85 + 0.15 * math.sin(abs * 40)) or ((math.floor(abs * 1.3) % 2 == 0) and 0.5 or 0)
	if on <= 0 or not I.RadioLed then return end
	local x, y, s = toScreen(cam, I.RadioLed[1], I.RadioLed[2])
	FX.Glow(x, y, 46 * s, Color(255, 40, 30), 0.55 * on)
	FX.Glow(x, y, 12 * s, Color(255, 140, 120), 0.9 * on)
end

-- Вертолёт: дежурная лампа, снег летит мимо открытой двери
function Extra.heli(cam, t, k, abs, dt)
	if I.HeliDoor then
		local d = I.HeliDoor
		local x0, y0 = toScreen(cam, d[1], d[2])
		local x1, y1 = toScreen(cam, d[3], d[4])
		render.SetScissorRect(x0, y0, x1, y1, true)
		FX.Streaks(dt, x0, y0, x1 - x0, y1 - y0, 0.8)
		render.SetScissorRect(0, 0, 0, 0, false)
	end
	if I.HeliLamp then
		local lx, ly, s = toScreen(cam, I.HeliLamp[1], I.HeliLamp[2])
		local flick = 0.8 + 0.1 * math.sin(abs * 9) + (math.random() < 0.03 and -0.3 or 0)
		FX.Glow(lx, ly, 420 * s, Color(255, 30, 20), 0.16 * flick)
		FX.Glow(lx, ly, 50 * s, Color(255, 120, 100), 0.5 * flick)
	end
end

-- Знак Фонда: «включается» с парой вспышек, как старая лампа, и медленно садится на место
function Extra.banner_after(cam, t, k, abs)
	local w, h = ScrW(), ScrH()
	local a = E.Smooth(t / 0.9)
	if t < 0.9 then a = a * ((math.floor(t * 18) % 3 == 0) and 0.3 or 1) end
	local size = h * 0.32 * Lerp(E.OutExpo(t / 3), 1.08, 1)
	local cx, cy = w / 2, h * 0.40
	FX.Shade(cx, cy, size * 2.6, size * 2.2, 0.55 * a)
	FX.Glow(cx, cy, size * 1.1, Color(120, 150, 190), 0.12 * a * (0.8 + 0.2 * math.sin(abs * 2)))
	surface.SetMaterial(M.logo)
	surface.SetDrawColor(255, 255, 255, 255 * a)
	surface.DrawTexturedRect(cx - size / 2, cy - size / 2, size, size)
	local lw = w * 0.16 * E.OutCubic((t - 0.8) / 1.6)
	local c = WS.Config.Color.accent
	surface.SetDrawColor(c.r, c.g, c.b, 220 * a)
	surface.DrawRect(cx - lw / 2, h * 0.615, lw, math.max(2, h / 540))
end

local DEFAULT_CAM = { zoom = { 1, 1 }, x = { 0.5, 0.5 }, y = { 0.5, 0.5 } }

local function drawShot(sh, t, k, dt, abs)
	local c = sh.cam or DEFAULT_CAM
	local e = E.InOutSine(k)
	local cam = { zoom = Lerp(e, c.zoom[1], c.zoom[2]), fx = Lerp(e, c.x[1], c.x[2]), fy = Lerp(e, c.y[1], c.y[2]) }
	if sh.shake then
		-- вибрация корпуса + медленное покачивание
		local sc = ScrH() / 1080
		cam.zoom = cam.zoom + 0.01 * math.sin(abs * 0.5)
		cam.fx = cam.fx + 0.004 * math.sin(abs * 0.33)
		cam.fy = cam.fy + 0.006 * math.sin(abs * 0.71)
		cam.sx = (math.sin(abs * 61) * 1.4 + math.sin(abs * 37.3) * 1.0) * sc
		cam.sy = (math.sin(abs * 53.7) * 1.6 + math.sin(abs * 17.2) * 0.8) * sc
	end
	if sh.brush then
		-- пока кадр проявляется мазками, камера чуть «оседает» — медленно отъезжает к своей траектории
		cam.zoom = cam.zoom * (1 + 0.06 * (1 - E.OutCubic(t / (sh.fadeIn + 1.5))))
	end
	frame(cam)
	if sh.image then
		-- проявление: из размытого в резкий кадр
		drawLayer(M[sh.image .. "_blur"], cam, 1, 1)
		drawLayer(M[sh.image], cam, 1, E.Smooth(t / (sh.brush and 0.9 or 2.4)))   -- под мазками резкость быстрее
	end
	if Extra[sh.id] then Extra[sh.id](cam, t, k, abs, dt) end
	if sh.fog then
		FX.Fog(abs, sh.fog, 40)
		FX.Fog(abs + 30, sh.fog * 0.8, 75)
	end
	if sh.snow then FX.Snow(abs, dt, sh.snow, sh.snowDensity or 1, 1, sh.debris) end
	if sh.tint then
		surface.SetDrawColor(sh.tint.r, sh.tint.g, sh.tint.b, sh.tint.a * (0.6 + 0.4 * k))
		surface.DrawRect(0, 0, ScrW(), ScrH())
	end
	if Extra[sh.id .. "_after"] then Extra[sh.id .. "_after"](cam, t, k, abs, dt) end
	if sh.id == "arctic" then
		surface.SetDrawColor(220, 230, 240, 50 * (1 - E.OutCubic(t / 2.2)))    -- лёгкая вспышка проявления
		surface.DrawRect(0, 0, ScrW(), ScrH())
	end
end

-- ---------------------------------------------------------------- титры

local function subStyle(style)
	local sc = ScrH() / 1080
	if style == "brand" then
		return { font = WS.Font("subheavy", 64), spacing = 6 * sc, cps = 16, color = Color(236, 238, 242) }
	elseif style == "motto" then
		return { font = WS.Font("submed", 26), spacing = 5 * sc, cps = 28, color = Color(196, 204, 216) }
	end
	return { font = WS.Font("sub", 34), spacing = 2.4 * sc, cps = 45, color = Color(242, 240, 236), hl = Color(226, 190, 120) }
end

local function drawTexts(t, shot)
	local w, h = ScrW(), ScrH()
	local band = 0
	for _, tx in ipairs(I.Texts) do
		if tx.style == "sub" then
			band = math.max(band, E.Window(t, tx.at - 0.3, tx.to, 0.8, 1.2))
		end
	end
	if band > 0 then FX.SubBand(band, shot and shot.sub) end

	for _, tx in ipairs(I.Texts) do
		if t >= tx.at and t <= tx.to + 1.2 then
			local st = subStyle(tx.style)
			local o = {
				font = st.font, spacing = st.spacing, cps = st.cps, fade = 0.6, color = st.color, hl = st.hl,
				x = w / 2, maxW = w * 0.8, t = t - tx.at, alpha = 1 - E.Smooth((t - tx.to) / 1.1), rise = 4, shadow = 0.8,
			}
			if tx.style == "sub" then o.bottom = h * 0.935
			elseif tx.style == "brand" then o.y = h * 0.64
			else o.y = h * 0.735 end
			UI.Reveal(tx.text, o)
		end
	end
end

-- [ПРОБЕЛ] — Пропустить (снизу справа, мелко)
local function drawSkipHint(t)
	local a = E.Smooth((t - 1.0) / 1.0) * (skipAt and 0 or 1) * (0.55 + 0.2 * math.sin(t * 2.2))
	if a <= 0 then return end
	local w, h = ScrW(), ScrH()
	local sc = h / 1080
	local fk, ft = WS.Font("mono", 13), WS.Font("mono", 15)
	surface.SetFont(ft)
	local tw, th = surface.GetTextSize("— Пропустить")
	surface.SetFont(fk)
	local kw, kh = surface.GetTextSize("ПРОБЕЛ")
	local pad = 8 * sc
	local x = w - 28 * sc - tw - kw - pad * 3
	local y = h - 22 * sc - th
	local bw, bh = kw + pad * 2, kh + pad * 0.8
	local by = y + th / 2 - bh / 2
	draw.RoundedBox(4 * sc, x, by, bw, bh, Color(0, 0, 0, 90 * a))
	surface.SetDrawColor(220, 228, 238, 140 * a)
	surface.DrawOutlinedRect(x, by, bw, bh, math.max(1, math.floor(sc)))
	draw.SimpleText("ПРОБЕЛ", fk, x + bw / 2, by + bh / 2, Color(232, 236, 242, 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("— Пропустить", ft, x + bw + pad, y + th / 2, Color(210, 216, 226, 220 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

	local cur
	for _, sh in ipairs(I.Shots) do
		if t >= sh.from and t <= sh.to then
			cur = sh
			local lt = t - sh.from
			drawShot(sh, lt, lt / (sh.to - sh.from), dt, t)
			if sh.brush then
				-- проявление мазками от центра и закрытие мазками к центру
				local pin = E.InOutSine(lt / sh.fadeIn)
				local pout = 1 - E.InOutSine((t - (sh.to - sh.fadeOut)) / sh.fadeOut)
				FX.BrushMask(math.min(pin, pout))
			else
				-- обычное затемнение на входе и выходе кадра
				local v = E.Window(t, sh.from, sh.to - sh.fadeOut, sh.fadeIn, sh.fadeOut)
				if v < 1 then
					surface.SetDrawColor(0, 0, 0, 255 * (1 - v))
					surface.DrawRect(0, 0, w, h)
				end
			end
		end
	end

	FX.Vignette(0.8)
	FX.Grain(1)
	drawTexts(t, cur)
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
