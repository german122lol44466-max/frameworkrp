--[[
	Брифинг миссии — короткое интро при выходе на первую главу (≈24 с, [ПРОБЕЛ] — пропустить у себя):
	тактическая карта района медленно наезжает, по ней прорисовывается маршрут группы и вспыхивают метки
	(высадка → последний сигнал «Дельта-14» → объект 7 → озеро), слева печатаются поля задачи,
	голос штаба ведёт брифинг (реплики brief_1..3, с субтитрами). В конце — затемнение и пробуждение.

	Кроме того — сцена крушения вертолёта (ws.story.cutscene "crash"): тряска, сирена, удар, белая вспышка,
	темнота со звоном в ушах, затем пробуждение у обломков.
]]

local S = WS.Story
local UI = WS.UI
local E = WS.Ease
local B = {}
WS.Briefing = B

local LEN = 24
local t0, skipped
local mapMat

-- маршрут и метки в долях карты (карта 1600×900, tools/content/briefing_map.py)
local ROUTE = { { 0.14, 0.82 }, { 0.22, 0.7 }, { 0.31, 0.64 }, { 0.38, 0.52 }, { 0.47, 0.46 }, { 0.58, 0.4 }, { 0.68, 0.33 }, { 0.78, 0.26 } }
local MARKS = {
	{ at = 6.0, p = { 0.14, 0.82 }, text = "ВЫСАДКА · МОГ «БУРАН»", col = Color(226, 190, 120) },
	{ at = 8.5, p = { 0.38, 0.52 }, text = "ПОСЛЕДНИЙ СИГНАЛ «ДЕЛЬТА-14»", col = Color(214, 92, 84) },
	{ at = 11.5, p = { 0.58, 0.4 }, text = "ОБЪЕКТ 7", col = Color(214, 92, 84) },
	{ at = 14.0, p = { 0.78, 0.26 }, text = "?", col = Color(150, 196, 236) },
}
local FIELDS = {
	{ at = 1.2, k = "ОПЕРАЦИЯ", v = "«БЕЛАЯ ТИШИНА»" },
	{ at = 2.4, k = "ОТРЯД", v = "МОГ «Буран», позывной штаба — «Ледник»" },
	{ at = 3.6, k = "ЗАДАЧА", v = "Найти МОГ «Дельта-14», установить причину потери связи, нейтрализовать угрозу" },
	{ at = 5.4, k = "РАЙОН", v = "Арктика, квадрат 71-44. Объект 7 — бункер Фонда" },
	{ at = 6.8, k = "ПОГОДА", v = "Метель, видимость менее 50 м, −34 °C" },
	{ at = 8.2, k = "ПРАВИЛА", v = "Огонь — только по подтверждённой цели. Не верить эфиру" },
}

function B.Active()
	return t0 ~= nil and not skipped and RealTime() - t0 < LEN
end

local function finish()
	if not t0 then return end
	t0 = nil
	if WS.Wake then WS.Wake.Start() end
end

function B.Start()
	t0, skipped = RealTime(), false
	mapMat = UI.Mat("whitesilence/menu/briefing_map.jpg", "smooth")
	WS.Audio.Play("whitesilence/game/radio.ogg", { volume = 0.5 })
	local delay = 1.5
	for _, id in ipairs({ "brief_1", "brief_2", "brief_3" }) do
		timer.Simple(delay, function()
			if not B.Active() then return end
			WS.Audio.Play("whitesilence/story/" .. id .. ".ogg", { volume = 0.95 })
			B.sub = { id = id, t = RealTime() }
		end)
		delay = delay + S.LineTime(id) + 0.9
	end
	-- гул штабной аппаратной под брифингом
	B.hum = WS.Audio.Play("whitesilence/menu/drone.ogg", { volume = 0.0, fade = 0.01, loop = true })
	B.hum:Fade(0.35, 2)
end

net.Receive("ws.story.briefing", function() B.Start() end)

hook.Add("Think", "ws.briefing", function()
	if not t0 then return end
	local t = RealTime() - t0
	if (t > 1 and input.IsKeyDown(KEY_SPACE) and not vgui.GetKeyboardFocus()) or t > LEN then
		skipped = t <= LEN
		for h in pairs(WS.Audio.Active) do
			if h.path and h.path:find("brief_") then h:Stop(0.5) end
		end
		if B.hum then B.hum:Stop(1.5) B.hum = nil end
		finish()
	end
end)

local function mapPoint(p, mx, my, mw, mh) return mx + p[1] * mw, my + p[2] * mh end

local function drawBriefing(w, h, s, t)
	WS.Intro.FX.Ensure()
	local a = E.Smooth(t / 1.0) * (1 - E.Smooth((t - (LEN - 1.2)) / 1.2))
	surface.SetDrawColor(4, 6, 9, 255)
	surface.DrawRect(0, 0, w, h)
	-- карта: медленный наезд к цели
	local zoom = 1.04 + t * 0.006
	local mw, mh = w * 0.62 * zoom, w * 0.62 * zoom * 900 / 1600
	local mx, my = w * 0.34 - (mw - w * 0.62) * 0.6, h * 0.16 - (mh - w * 0.62 * 900 / 1600) * 0.4
	render.SetScissorRect(w * 0.34, h * 0.16, w * 0.96, h * 0.16 + w * 0.62 * 900 / 1600, true)
	surface.SetMaterial(mapMat)
	surface.SetDrawColor(255, 255, 255, 230 * a)
	surface.DrawTexturedRect(mx, my, mw, mh)
	-- маршрут прорисовывается
	local prog = E.Clamp01((t - 5.5) / 9)
	local segs = #ROUTE - 1
	local upto = prog * segs
	for i = 1, segs do
		local k = math.Clamp(upto - (i - 1), 0, 1)
		if k <= 0 then break end
		local x0, y0 = mapPoint(ROUTE[i], mx, my, mw, mh)
		local x1, y1 = mapPoint(ROUTE[i + 1], mx, my, mw, mh)
		local xe, ye = Lerp(k, x0, x1), Lerp(k, y0, y1)
		-- пунктир
		local dist = math.sqrt((xe - x0) ^ 2 + (ye - y0) ^ 2)
		local n = math.floor(dist / (10 * s))
		for j = 0, n - 1, 2 do
			local u0, u1 = j / math.max(n, 1), math.min((j + 1) / math.max(n, 1), 1)
			surface.SetDrawColor(226, 190, 120, 230 * a)
			surface.DrawLine(Lerp(u0, x0, xe), Lerp(u0, y0, ye), Lerp(u1, x0, xe), Lerp(u1, y0, ye))
			surface.DrawLine(Lerp(u0, x0, xe), Lerp(u0, y0, ye) + 1, Lerp(u1, x0, xe), Lerp(u1, y0, ye) + 1)
		end
	end
	for _, m in ipairs(MARKS) do
		local lt = t - m.at
		if lt > 0 then
			local x, y = mapPoint(m.p, mx, my, mw, mh)
			local k = E.OutCubic(lt / 0.5)
			local pulse = (lt % 1.6) / 1.6
			surface.SetMaterial(UI.Mat("whitesilence/markers/ring.png", "smooth"))
			surface.SetDrawColor(m.col.r, m.col.g, m.col.b, 200 * (1 - pulse) * a)
			local r = (14 + pulse * 40) * s
			surface.DrawTexturedRect(x - r, y - r, r * 2, r * 2)
			surface.SetMaterial(UI.Mat("whitesilence/markers/goto.png", "smooth"))
			surface.SetDrawColor(m.col.r, m.col.g, m.col.b, 255 * k * a)
			surface.DrawTexturedRect(x - 14 * s, y - 14 * s, 28 * s, 28 * s)
			draw.SimpleTextOutlined(m.text, WS.Font("menusemi", 15), x + 20 * s, y, Color(m.col.r, m.col.g, m.col.b, 255 * k * a),
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200 * a))
		end
	end
	render.SetScissorRect(0, 0, 0, 0, false)
	-- рамка карты и развёртка
	local fx, fy, fw, fh = w * 0.34, h * 0.16, w * 0.62, w * 0.62 * 900 / 1600
	surface.SetDrawColor(226, 190, 120, 120 * a)
	surface.DrawOutlinedRect(fx, fy, fw, fh, 1)
	local scan = fy + (t * 0.18 % 1) * fh
	surface.SetDrawColor(150, 196, 236, 30 * a)
	surface.DrawRect(fx, scan, fw, 2 * s)
	draw.SimpleText("ЛИСТ 71-44 · СПУТНИКОВАЯ СЪЁМКА НЕДОСТУПНА · МЕТЕЛЬ", WS.Font("menulight", 13), fx, fy - 18 * s, Color(150, 160, 172, 200 * a))

	-- поля задачи (печатаются)
	local x, y = w * 0.04, h * 0.16
	draw.SimpleText("ФОНД SCP · БРИФИНГ", WS.Font("menusemi", 16), x, y - 34 * s, Color(196, 38, 38, 255 * a))
	for _, f in ipairs(FIELDS) do
		local lt = t - f.at
		if lt > 0 then
			draw.SimpleText(f.k, WS.Font("menusemi", 14), x, y, Color(150, 158, 170, 255 * a))
			-- печать по символу, по левому краю, с переносом строк
			local font = WS.Font("menu", 19)
			local lay = UI.Layout(f.v, font, w * 0.27)
			local left = math.floor(lt * 55)
			local ly = y + 20 * s
			for _, line in ipairs(lay.lines) do
				if left <= 0 then break end
				local n = math.min(left, #line.chars)
				left = left - n
				draw.SimpleText(table.concat(line.chars, "", 1, n), font, x, ly, Color(232, 236, 242, 255 * a))
				ly = ly + 24 * s
			end
			y = ly + 20 * s
		end
	end

	-- субтитры голоса штаба
	if B.sub then
		local lt = RealTime() - B.sub.t
		local dur = S.LineTime(B.sub.id)
		if lt < dur + 0.6 then
			local sa = E.Window(lt, 0, 0.25, dur, dur + 0.6) * a
			draw.SimpleText("ЛЕДНИК", WS.Font("submed", 20), w / 2, h * 0.86 - 40 * s, Color(150, 196, 236, 240 * sa), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			UI.Reveal(S.Lines[B.sub.id].text, { font = WS.Font("sub", 28), x = w / 2, y = h * 0.86 - 36 * s, maxW = w * 0.6, t = lt,
				cps = 45, fade = 0.3, alpha = sa, color = Color(232, 236, 242), rise = 3, shadow = 0.8 })
		end
	end
	WS.Intro.FX.Grain(0.5 * a)
	WS.Intro.FX.Vignette(0.9)
	if t > 1 then
		draw.SimpleText("[ПРОБЕЛ] — пропустить", WS.Font("menulight", 15), w - 30 * s, h - 26 * s, Color(150, 160, 172, 160 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end
end

-- ---------------------------------------------------------------- крушение

local crashT
net.Receive("ws.story.cutscene", function()
	local scene = net.ReadString()
	if scene ~= "crash" then return end
	crashT = RealTime()
	WS.Audio.Play("whitesilence/intro/heli_interior.ogg", { volume = 0.8 })
	surface.PlaySound("ambient/alarms/klaxon1.wav")
	timer.Simple(1.6, function()
		surface.PlaySound("ambient/explosions/explode_9.wav")
		WS.Audio.Play("whitesilence/intro/fade_boom.ogg", { volume = 1 })
		WS.Audio.StopAll(0.2)
		timer.Simple(0.3, function() WS.Audio.Play("whitesilence/game/tinnitus.ogg", { volume = 0.6 }) end)
	end)
	timer.Simple(7.0, function()
		crashT = nil
		if WS.Wake then WS.Wake.Start() end
	end)
end)

hook.Add("CalcView", "ws.crash", function(ply, origin, angles, fov)
	if not crashT then return end
	local t = RealTime() - crashT
	if t > 1.6 then return end
	local k = t / 1.6
	local shake = Angle(math.Rand(-1, 1) * 6 * k, math.Rand(-1, 1) * 6 * k, math.sin(t * 9) * 25 * k)
	return { origin = origin + VectorRand() * 3 * k, angles = angles + shake, fov = fov }
end)

hook.Add("HUDPaint", "ws.briefing", function()
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	if B.Active() then drawBriefing(w, h, s, RealTime() - t0) end
	if crashT then
		local t = RealTime() - crashT
		if t < 1.6 then
			surface.SetDrawColor(160, 20, 10, (0.3 + 0.3 * math.sin(t * 20)) * 120)
			surface.DrawRect(0, 0, w, h)
		else
			-- белая вспышка → чернота
			local white = 1 - E.Smooth((t - 1.6) / 0.6)
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawRect(0, 0, w, h)
			if white > 0 then
				surface.SetDrawColor(255, 250, 240, 255 * white)
				surface.DrawRect(0, 0, w, h)
			end
		end
	end
end)

hook.Add("HUDShouldDraw", "ws.briefing", function(name)
	if B.Active() and name ~= "CHudGMod" then return false end
end)
