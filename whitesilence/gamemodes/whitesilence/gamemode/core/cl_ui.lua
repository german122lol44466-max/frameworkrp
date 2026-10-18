--[[
	Рисование: текстуры, обложка экрана (cover), аддитивное смешивание, текст с посимвольным проявлением.
]]

local UI = WS.UI

local mats = {}

-- Material с кэшем. flags по умолчанию "smooth".
function UI.Mat(path, flags)
	local key = path .. "|" .. (flags or "")
	local m = mats[key]
	if not m then
		m = Material(path, flags or "smooth")
		mats[key] = m
	end
	return m
end

function UI.Additive(on)
	if on then
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	else
		render.OverrideBlend(false)
	end
end

function UI.Rect(x, y, w, h, col)
	surface.SetDrawColor(col)
	surface.DrawRect(x, y, w, h)
end

-- ---------------------------------------------------------------- текст

-- Разбивает строку на символы UTF-8.
local function chars(s)
	local out = {}
	for _, code in utf8.codes(s) do out[#out + 1] = utf8.char(code) end
	return out
end

-- Раскладка: строки по ширине maxW, для каждого символа — смещение x. Кэшируется по (текст, шрифт, ширина, разрядка).
local layouts = {}

function UI.Layout(text, font, maxW, spacing)
	spacing = spacing or 0
	local key = text .. "\0" .. font .. "\0" .. math.floor(maxW) .. "\0" .. spacing
	local l = layouts[key]
	if l then return l end

	surface.SetFont(font)
	local words = string.Explode(" ", text)
	local lines, cur = {}, ""
	local function width(s)
		local w = surface.GetTextSize(s)
		return w + spacing * math.max(utf8.len(s) - 1, 0)
	end
	for _, w in ipairs(words) do
		local try = cur == "" and w or (cur .. " " .. w)
		if cur ~= "" and width(try) > maxW then
			lines[#lines + 1] = cur
			cur = w
		else
			cur = try
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end

	local _, lh = surface.GetTextSize("Ag")
	l = { lines = {}, lineH = lh, count = 0 }
	for _, line in ipairs(lines) do
		local cs = chars(line)
		local xs, acc = {}, ""
		for i, c in ipairs(cs) do
			xs[i] = (acc == "" and 0 or surface.GetTextSize(acc)) + spacing * (i - 1)
			acc = acc .. c
		end
		l.lines[#l.lines + 1] = { chars = cs, xs = xs, w = width(line) }
		l.count = l.count + #cs
	end
	return l
end

--[[
	Текст с посимвольным проявлением.
	o = { font, glow (размытый шрифт или nil), x, y (центр блока по x, верх по y), maxW, spacing,
	      t (секунды с начала), cps (символов в секунду), fade (длительность проявления символа),
	      alpha (общая 0..1), color, glowColor, rise (пикселей подъёма) }
	Возвращает высоту блока.
]]
function UI.Reveal(text, o)
	local l = UI.Layout(text, o.font, o.maxW or ScrW() * 0.7, o.spacing)
	local col = o.color or color_white
	local gcol = o.glowColor or Color(160, 200, 240)
	local cps, fade, rise = o.cps or 30, o.fade or 0.5, o.rise or 6
	local idx = 0
	for li, line in ipairs(l.lines) do
		local x0 = o.x - line.w / 2
		local y = o.y + (li - 1) * l.lineH * (o.lineGap or 1.12)
		for i, c in ipairs(line.chars) do
			local a = WS.Ease.OutCubic((o.t - idx / cps) / fade) * (o.alpha or 1)
			idx = idx + 1
			if a > 0.004 and c ~= " " then
				local cx, cy = x0 + line.xs[i], y + (1 - a) * rise
				if o.glow then
					surface.SetFont(o.glow)
					surface.SetTextColor(gcol.r, gcol.g, gcol.b, 90 * a)
					surface.SetTextPos(cx, cy)
					surface.DrawText(c)
				end
				surface.SetFont(o.font)
				-- тень для читаемости на светлом снегу
				surface.SetTextColor(0, 0, 0, 120 * a)
				surface.SetTextPos(cx + 1, cy + 2)
				surface.DrawText(c)
				surface.SetTextColor(col.r, col.g, col.b, 255 * a)
				surface.SetTextPos(cx, cy)
				surface.DrawText(c)
			end
		end
	end
	return #l.lines * l.lineH * (o.lineGap or 1.12)
end
