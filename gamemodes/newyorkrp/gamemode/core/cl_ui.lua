--[[
	Тема интерфейса и помощники рисования: масштаб, цвета, иконки, круги, блюр, звуки, затемнения.
]]

NYRP.UI = NYRP.UI or {}
local UI = NYRP.UI

UI.Col = {
	bg = Color(9, 11, 17, 235),
	panel = Color(16, 18, 26, 235),
	panel2 = Color(24, 27, 37, 240),
	slot = Color(255, 255, 255, 9),
	stroke = Color(255, 255, 255, 16),
	text = Color(236, 237, 242),
	dim = Color(150, 155, 170),
	faint = Color(92, 97, 112),
	accent = Color(247, 198, 0),
	orange = Color(255, 138, 36),
	red = Color(214, 70, 64),
	green = Color(104, 200, 120),
	nameGreen = Color(120, 214, 110),
	blue = Color(96, 164, 232),
	hp = Color(128, 26, 30),
	hunger = Color(150, 116, 18),
	thirst = Color(28, 88, 128),
	black = Color(0, 0, 0),
}

function UI.S(x)
	return math.Round(x * ScrH() / 1080)
end

local mats = {}
function UI.Mat(path)
	local m = mats[path]
	if not m then
		m = Material(path, "smooth mips")
		mats[path] = m
	end
	return m
end

function UI.Icon(name)
	return UI.Mat("nyrp/icons/" .. name .. ".png")
end

-- Иконка по центру (x, y).
function UI.DrawIcon(name, x, y, size, col)
	surface.SetMaterial(UI.Icon(name))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

function UI.Circle(x, y, r, col)
	surface.SetMaterial(UI.Mat("nyrp/ui/circle.png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - r, y - r, r * 2, r * 2)
end

function UI.Ring(x, y, r, col)
	surface.SetMaterial(UI.Mat("nyrp/ui/ring.png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - r, y - r, r * 2, r * 2)
end

function UI.Glow(x, y, w, h, col)
	surface.SetMaterial(UI.Mat("nyrp/ui/glow.png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - w / 2, y - h / 2, w, h)
end

function UI.Alpha(col, a)
	return Color(col.r, col.g, col.b, a)
end

function UI.LerpColor(t, a, b)
	return Color(Lerp(t, a.r, b.r), Lerp(t, a.g, b.g), Lerp(t, a.b, b.b), Lerp(t, a.a or 255, b.a or 255))
end

-- Плавное приближение к цели, не зависящее от FPS.
function UI.Approach(cur, target, speed)
	return Lerp(1 - math.exp(-(speed or 10) * FrameTime()), cur, target)
end

function UI.Ease(t)
	t = math.Clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

function UI.EaseInOut(t)
	t = math.Clamp(t, 0, 1)
	return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2
end

-- Блюр экрана под панелью (вызывать из Paint).
local blur = Material("pp/blurscreen")
function UI.BlurPanel(pnl, amount, alpha)
	local x, y = pnl:LocalToScreen(0, 0)
	surface.SetMaterial(blur)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	for i = 1, 3 do
		blur:SetFloat("$blur", i / 3 * (amount or 6))
		blur:Recompute()
		render.UpdateScreenEffectTexture()
		surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
	end
end

-- Блюр прямоугольника экрана (из HUDPaint и т.п.).
function UI.BlurRect(x, y, w, h, amount, alpha)
	render.SetScissorRect(x, y, x + w, y + h, true)
	surface.SetMaterial(blur)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	for i = 1, 3 do
		blur:SetFloat("$blur", i / 3 * (amount or 6))
		blur:Recompute()
		render.UpdateScreenEffectTexture()
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
	end
	render.SetScissorRect(0, 0, 0, 0, false)
end

-- Полигон скруглённого прямоугольника (для масок стенсила и ровных форм).
local polyCache = {}
function UI.RoundedPoly(x, y, w, h, r, seg)
	seg = seg or 6
	r = math.min(r, w / 2, h / 2)
	local key = table.concat({ x, y, w, h, r, seg }, ":")
	local poly = polyCache[key]
	if poly then return poly end
	poly = {}
	local corners = { { x + w - r, y + r, -90 }, { x + w - r, y + h - r, 0 }, { x + r, y + h - r, 90 }, { x + r, y + r, 180 } }
	for _, c in ipairs(corners) do
		for i = 0, seg do
			local a = math.rad(c[3] + 90 * i / seg)
			poly[#poly + 1] = { x = c[1] + math.cos(a) * r, y = c[2] + math.sin(a) * r }
		end
	end
	if table.Count(polyCache) > 512 then polyCache = {} end
	polyCache[key] = poly
	return poly
end

function UI.RoundedRect(r, x, y, w, h, col)
	draw.NoTexture()
	surface.SetDrawColor(col)
	surface.DrawPoly(UI.RoundedPoly(x, y, w, h, r))
end

local function stencilBegin()
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.OverrideColorWriteEnable(true, false)
	draw.NoTexture()
	surface.SetDrawColor(255, 255, 255, 255)
end

local function stencilUse(ref)
	render.OverrideColorWriteEnable(false, false)
	render.SetStencilReferenceValue(ref)
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
end

-- fn() рисуется только внутри скруглённого прямоугольника.
function UI.Masked(r, x, y, w, h, fn)
	stencilBegin()
	render.SetStencilReferenceValue(1)
	surface.DrawPoly(UI.RoundedPoly(x, y, w, h, r))
	stencilUse(1)
	fn()
	render.SetStencilEnable(false)
end

function UI.RoundedBlurPanel(pnl, r, amount)
	local w, h = pnl:GetSize()
	UI.Masked(r, 0, 0, w, h, function() UI.BlurPanel(pnl, amount) end)
end

-- Обводка скруглённого прямоугольника толщиной t.
function UI.Outline(r, x, y, w, h, col, t)
	t = t or 1
	stencilBegin()
	render.SetStencilReferenceValue(1)
	surface.DrawPoly(UI.RoundedPoly(x, y, w, h, r))
	render.SetStencilReferenceValue(0)
	surface.DrawPoly(UI.RoundedPoly(x + t, y + t, w - t * 2, h - t * 2, math.max(r - t, 0)))
	stencilUse(1)
	surface.SetDrawColor(col)
	surface.DrawRect(x, y, w, h)
	render.SetStencilEnable(false)
end

-- Мягкая виньетка внутри панели.
function UI.Vignette(x, y, w, h, alpha)
	surface.SetMaterial(UI.Mat("nyrp/ui/vignette.png"))
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	surface.DrawTexturedRect(x, y, w, h)
end

function UI.Sound(name)
	if GetConVar("nyrp_ui_sounds"):GetBool() then
		surface.PlaySound("nyrp/ui/" .. name .. ".wav")
	end
end

-- Перенос текста по словам в пределах ширины.
function UI.Wrap(text, font, width)
	surface.SetFont(font)
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		local test = line == "" and word or (line .. " " .. word)
		if surface.GetTextSize(test) > width and line ~= "" then
			lines[#lines + 1] = line
			line = word
		else
			line = test
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

function UI.TextSize(text, font)
	surface.SetFont(font)
	return surface.GetTextSize(text)
end

-- Затемнение экрана: fade -> callback в полной темноте -> hold -> выход.
local fades = {}
function UI.Fade(inTime, hold, outTime, callback, col)
	fades[#fades + 1] = { start = RealTime(), inT = inTime or 0.4, hold = hold or 0.2, outT = outTime or 0.5, cb = callback, col = col or color_black }
end

function UI.FadeAlpha()
	local a = 0
	local now = RealTime()
	for i = #fades, 1, -1 do
		local f = fades[i]
		local t = now - f.start
		local alpha
		if t < f.inT then
			alpha = t / f.inT
		elseif t < f.inT + f.hold then
			alpha = 1
			if f.cb then local cb = f.cb f.cb = nil cb() end
		elseif t < f.inT + f.hold + f.outT then
			if f.cb then local cb = f.cb f.cb = nil cb() end
			alpha = 1 - (t - f.inT - f.hold) / f.outT
		else
			if f.cb then local cb = f.cb f.cb = nil cb() end
			table.remove(fades, i)
			alpha = 0
		end
		a = math.max(a, alpha)
	end
	return a
end

hook.Add("PostRenderVGUI", "nyrp.fade", function()
	local a = UI.FadeAlpha()
	if a > 0 then
		surface.SetDrawColor(0, 0, 0, a * 255)
		surface.DrawRect(0, 0, ScrW(), ScrH())
	end
end)
