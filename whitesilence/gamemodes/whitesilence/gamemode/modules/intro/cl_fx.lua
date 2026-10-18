--[[
	Эффекты интро: метель (частицы с глубиной), туман, полосы снега, свечение, зерно, виньетка, кинорамка.
]]

local I = WS.Intro
local UI = WS.UI
local FX = {}
I.FX = FX

local flakeMat, streakMat, fogMat, grainMat, vigMat

function FX.Init()
	flakeMat = UI.Mat(I.Path .. "flake.png", "smooth")
	streakMat = UI.Mat(I.Path .. "streak.png", "smooth")
	fogMat = UI.Mat(I.Path .. "fog.png", "smooth noclamp")
	grainMat = UI.Mat(I.Path .. "grain.png", "noclamp")
	vigMat = UI.Mat(I.Path .. "vignette.png", "smooth")
	FX.flakes = {}
	FX.streaks = {}
end

-- ---------------------------------------------------------------- метель

local function newFlake(w, h, anywhere)
	local z = math.random() ^ 1.6          -- больше дальних, мелких
	return {
		x = math.Rand(-40, w + 40),
		y = anywhere and math.Rand(-40, h + 40) or -30,
		z = z,
		ph = math.Rand(0, 100),
		s = math.Rand(0.7, 1.3),
	}
end

-- Порыв ветра: 0..1, медленно гуляет
function FX.Gust(t)
	return 0.55 + 0.25 * math.sin(t * 0.37) + 0.15 * math.sin(t * 1.13 + 1.7) + 0.05 * math.sin(t * 3.1)
end

--[[
	mode: "blizzard" — косой летящий снег (вид сбоку); "calm" — хлопья медленно ложатся (вид сверху).
	intensity 0..1 — плотность и яркость.
]]
function FX.Snow(t, dt, mode, intensity, alpha)
	local w, h = ScrW(), ScrH()
	local sc = h / 1080
	local want = math.floor((mode == "calm" and 260 or 620) * intensity * math.Clamp(w * h / (1920 * 1080), 0.6, 1.6))
	local fl = FX.flakes
	while #fl < want do fl[#fl + 1] = newFlake(w, h, true) end
	while #fl > want do fl[#fl] = nil end

	local gust = FX.Gust(t)
	surface.SetMaterial(flakeMat)
	for i = 1, #fl do
		local f = fl[i]
		local z = f.z
		local vx, vy
		if mode == "calm" then
			vx = (math.sin(t * 0.6 + f.ph) * 22 + 18) * (0.4 + z) * sc
			vy = (28 + 40 * z) * sc
		else
			vx = (220 + 640 * gust) * (0.25 + z * 1.3) * f.s * sc
			vy = (60 + 160 * z) * f.s * sc + math.sin(t * 2 + f.ph) * 40 * sc
		end
		f.x = f.x + vx * dt
		f.y = f.y + vy * dt
		if f.x > w + 60 then f.x = -60 f.y = math.Rand(-40, h) end
		if f.x < -60 then f.x = w + 60 end
		if f.y > h + 40 then f.y = -40 f.x = math.Rand(-40, w) end

		local size = (2 + z * z * 16) * f.s * sc
		local a = (40 + z * 150) * intensity * alpha
		if z > 0.92 then a = a * 0.45 size = size * 1.8 end   -- совсем близкие — мягкие «боке»
		local speed = math.sqrt(vx * vx + vy * vy)
		local len = size * (1 + speed / (900 * sc) * (mode == "calm" and 0 or 2.2))
		surface.SetDrawColor(235, 242, 250, a)
		if len > size * 1.2 then
			surface.DrawTexturedRectRotated(f.x, f.y, len, size, -math.deg(math.atan2(vy, vx)))
		else
			surface.DrawTexturedRect(f.x - size / 2, f.y - size / 2, size, size)
		end
	end
end

-- ---------------------------------------------------------------- туман: два бесшовных слоя едут с разной скоростью

function FX.Fog(t, alpha, speed, col)
	local w, h = ScrW(), ScrH()
	col = col or Color(200, 214, 230)
	surface.SetMaterial(fogMat)
	for i, k in ipairs({ { 1.0, 0.9 }, { 1.7, 0.55 } }) do
		local scale = h * k[1] * 1.6
		local u = (t * speed * (0.6 + i * 0.5) * (0.6 + FX.Gust(t) * 0.6)) / scale * h
		local v = math.sin(t * 0.1 + i) * 0.05
		surface.SetDrawColor(col.r, col.g, col.b, 255 * alpha * k[2])
		surface.DrawTexturedRectUV(0, 0, w, h, -u, v, -u + w / scale, v + h / scale)
	end
end

-- ---------------------------------------------------------------- полосы снега, летящие мимо двери вертолёта

function FX.Streaks(dt, x, y, w, h, alpha)
	local st = FX.streaks
	local sc = ScrH() / 1080
	while #st < 40 do
		st[#st + 1] = { x = math.Rand(x, x + w), y = math.Rand(y, y + h), v = math.Rand(1800, 3600), l = math.Rand(60, 200), a = math.Rand(40, 140) }
	end
	surface.SetMaterial(streakMat)
	for _, s in ipairs(st) do
		s.x = s.x - s.v * sc * dt
		if s.x < x - 200 * sc then s.x = x + w + math.Rand(0, 300) * sc s.y = math.Rand(y, y + h) end
		surface.SetDrawColor(225, 235, 248, s.a * alpha)
		surface.DrawTexturedRect(s.x, s.y, s.l * sc, 6 * sc)
	end
end

-- ---------------------------------------------------------------- свечение (аддитивное мягкое пятно)

function FX.Glow(x, y, r, col, a)
	UI.Additive(true)
	surface.SetMaterial(flakeMat)
	surface.SetDrawColor(col.r, col.g, col.b, math.Clamp(255 * a, 0, 255))
	surface.DrawTexturedRect(x - r, y - r, r * 2, r * 2)
	UI.Additive(false)
end

-- Мягкое тёмное пятно (подложка под текст)
function FX.Shade(cx, cy, w, h, a)
	surface.SetMaterial(flakeMat)
	surface.SetDrawColor(0, 0, 0, math.Clamp(255 * a, 0, 255))
	surface.DrawTexturedRect(cx - w / 2, cy - h / 2, w, h)
end

-- ---------------------------------------------------------------- плёнка: зерно, виньетка, кинорамка

function FX.Grain(alpha)
	local w, h = ScrW(), ScrH()
	local u, v = math.random(), math.random()
	local k = 256 * 1.5 * h / 1080
	surface.SetMaterial(grainMat)
	surface.SetDrawColor(255, 255, 255, 18 * alpha)
	surface.DrawTexturedRectUV(0, 0, w, h, u, v, u + w / k, v + h / k)
end

function FX.Vignette(alpha)
	surface.SetMaterial(vigMat)
	surface.SetDrawColor(255, 255, 255, 255 * alpha)
	surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
end

-- Чёрные полосы 2.39:1; k 0..1 — насколько выдвинуты. Возвращает высоту полосы.
function FX.Letterbox(k)
	local w, h = ScrW(), ScrH()
	local bar = math.max(0, (h - w / 2.39) / 2) * k
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, w, bar)
	surface.DrawRect(0, h - bar, w, bar + 1)
	return bar
end
