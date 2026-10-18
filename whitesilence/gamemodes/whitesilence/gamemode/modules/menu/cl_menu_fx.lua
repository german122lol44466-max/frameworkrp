--[[
	Эффекты главного меню: искры из оборванного кабеля (вспышками, со звуком и отблеском),
	угольки, медленно плывущие вверх, мигающий прожектор.
]]

local MFX = {}
WS.Menu.FX = MFX

local UI = WS.UI
local sparks, embers = {}, {}
local nextBurst = 0
MFX.Light = 0          -- 0..1 — насколько сейчас светят искры (отблеск у источника)
MFX.Flicker = 1        -- яркость прожектора

-- Источник искр — доля экрана (кабель на фоновой картине), задаётся из cl_menu.lua
MFX.Source = { 0.8, 0.12 }

local function burst(n)
	local w, h = ScrW(), ScrH()
	local sx, sy = MFX.Source[1] * w, MFX.Source[2] * h
	local sc = h / 1080
	for _ = 1, n do
		local a = math.Rand(-math.pi * 0.95, -math.pi * 0.05)   -- в основном вниз-в стороны
		local v = math.Rand(80, 520) * sc
		sparks[#sparks + 1] = {
			x = sx, y = sy, vx = math.cos(a) * v * 0.9, vy = -math.sin(a) * v * 0.35 - math.Rand(0, 120) * sc,
			life = math.Rand(0.5, 1.6), age = 0, size = math.Rand(1.5, 3.2) * sc, bounce = math.random() < 0.5,
		}
	end
	MFX.Light = 1
	WS.Audio.Play("whitesilence/menu/spark.ogg", { volume = math.Rand(0.35, 0.6) })
end

function MFX.Reset()
	sparks, embers = {}, {}
	nextBurst = RealTime() + 1.5
end

function MFX.Think(dt)
	local now = RealTime()
	local w, h = ScrW(), ScrH()
	local sc = h / 1080
	if now > nextBurst then
		burst(math.random(18, 46))
		nextBurst = now + math.Rand(2.2, 6.5)
	end
	MFX.Light = math.max(0, MFX.Light - dt * 3.2)
	-- прожектор иногда «моргает»
	if math.random() < dt * 0.25 then
		MFX.FlickerUntil = now + math.Rand(0.08, 0.35)
		if math.random() < 0.5 then WS.Audio.Play("whitesilence/menu/flicker.ogg", { volume = 0.3 }) end
	end
	MFX.Flicker = (MFX.FlickerUntil and now < MFX.FlickerUntil) and math.Rand(0.15, 0.6) or 1

	local floor = h * 0.94
	for i = #sparks, 1, -1 do
		local s = sparks[i]
		s.age = s.age + dt
		s.vy = s.vy + 900 * sc * dt
		s.vx = s.vx * (1 - dt * 0.8)
		s.x = s.x + s.vx * dt
		s.y = s.y + s.vy * dt
		if s.bounce and s.y > floor and s.vy > 0 then
			s.y = floor
			s.vy = -s.vy * 0.3
			s.vx = s.vx * 0.6
			s.bounce = false
		end
		if s.age > s.life or s.y > h + 20 then table.remove(sparks, i) end
	end
	-- угольки: редкие, медленные, тёплые точки, плывут вверх и вбок
	if #embers < 26 and math.random() < dt * 6 then
		embers[#embers + 1] = { x = math.Rand(0.35, 1.05) * w, y = h + 10, vx = math.Rand(-20, 6) * sc,
			vy = -math.Rand(18, 55) * sc, ph = math.Rand(0, 6), life = math.Rand(6, 14), age = 0, size = math.Rand(1.2, 2.6) * sc }
	end
	for i = #embers, 1, -1 do
		local e = embers[i]
		e.age = e.age + dt
		e.x = e.x + (e.vx + math.sin(now * 0.8 + e.ph) * 12 * sc) * dt
		e.y = e.y + e.vy * dt
		if e.age > e.life or e.y < -20 then table.remove(embers, i) end
	end
end

function MFX.Draw(alpha)
	local w, h = ScrW(), ScrH()
	local flake = UI.Mat(WS.Intro.Path .. "flake.png", "smooth")
	local streak = UI.Mat(WS.Intro.Path .. "streak.png", "smooth")
	UI.Additive(true)
	-- отблеск у источника во время вспышки
	if MFX.Light > 0 then
		local sx, sy = MFX.Source[1] * w, MFX.Source[2] * h
		surface.SetMaterial(flake)
		surface.SetDrawColor(255, 150, 60, 120 * MFX.Light * alpha)
		surface.DrawTexturedRect(sx - h * 0.25, sy - h * 0.25, h * 0.5, h * 0.5)
		surface.SetDrawColor(255, 230, 180, 220 * MFX.Light * alpha)
		surface.DrawTexturedRect(sx - h * 0.03, sy - h * 0.03, h * 0.06, h * 0.06)
	end
	-- искры: вытянуты по скорости, остывают от бело-жёлтого к красному
	surface.SetMaterial(streak)
	for _, s in ipairs(sparks) do
		local k = s.age / s.life
		local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
		local len = math.max(s.size * 2, speed * 0.035)
		local r, g, b = 255, Lerp(k, 230, 90), Lerp(k, 160, 20)
		surface.SetDrawColor(r, g, b, 255 * (1 - k) * alpha)
		surface.DrawTexturedRectRotated(s.x, s.y, len, s.size * 2.2, -math.deg(math.atan2(s.vy, s.vx)))
	end
	surface.SetMaterial(flake)
	for _, e in ipairs(embers) do
		local k = e.age / e.life
		local a = math.sin(math.pi * k) * (0.6 + 0.4 * math.sin(RealTime() * 5 + e.ph))
		surface.SetDrawColor(255, 140, 60, 170 * a * alpha)
		surface.DrawTexturedRect(e.x - e.size * 2, e.y - e.size * 2, e.size * 4, e.size * 4)
	end
	UI.Additive(false)
end
