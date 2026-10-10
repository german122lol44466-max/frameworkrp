--[[
	Граффити (клиент): рисунки на стенах (3D2D по нормали стены, с учётом освещения),
	призрачный предпросмотр под прицелом с баллончиком и окно выбора рисунка (R).
	SF.DrawTag(tagIndex, color, seed, alpha, light) — рисует тег в точке (0, 0) ~520×300 пикселей
	(и в мире, и в окне выбора).
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun
local UI = NYRP.UI

local graf = {}          -- [id] = { pos, normal, ang, tag, col, seed, s, light, lightAt }
SF.ClientGraffiti = graf
SF.SelTag = math.Clamp(tonumber(cookie.GetString("nyrp.graf.tag", "1")) or 1, 1, #SF.Tags)

local fontsMade = false
local function fonts()
	if fontsMade then return end
	fontsMade = true
	surface.CreateFont("nyrp.graf.a", { font = "Coolvetica", size = 150, weight = 500, extended = true, antialias = true })
	surface.CreateFont("nyrp.graf.b", { font = "Oswald SemiBold", size = 140, weight = 600, extended = true, antialias = true })
end

-- ------------------------------------------------------------ рисование --
local function rng(seed)
	local s = (seed * 7919) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function(a, b)
		s = (s * 16807) % 2147483647
		local f = s / 2147483647
		return a + (b - a) * f
	end
end

local function mul(c, k, a)
	return Color(math.min(c.r * k, 255), math.min(c.g * k, 255), math.min(c.b * k, 255), a)
end

local function poly(pts, col)
	surface.SetDrawColor(col)
	draw.NoTexture()
	surface.DrawPoly(pts)
end

local function circle(x, y, r, col)
	UI.Circle(x, y, r, col)
end

local function star(x, y, r, col)
	for i = 0, 4 do
		local a1 = math.rad(-90 + i * 72)
		local a2 = math.rad(-90 + i * 72 - 36)
		local a3 = math.rad(-90 + i * 72 + 36)
		poly({
			{ x = x + math.cos(a2) * r * 0.42, y = y + math.sin(a2) * r * 0.42 },
			{ x = x + math.cos(a1) * r, y = y + math.sin(a1) * r },
			{ x = x + math.cos(a3) * r * 0.42, y = y + math.sin(a3) * r * 0.42 },
		}, col)
	end
	circle(x, y, r * 0.45, col)
end

local function thickLine(x1, y1, x2, y2, t, col)
	local dx, dy = x2 - x1, y2 - y1
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 0.01 then return end
	local nx, ny = -dy / l * t / 2, dx / l * t / 2
	poly({ { x = x1 + nx, y = y1 + ny }, { x = x1 - nx, y = y1 - ny }, { x = x2 - nx, y = y2 - ny }, { x = x2 + nx, y = y2 + ny } }, col)
	poly({ { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny }, { x = x1 + nx, y = y1 + ny } }, col)
end

local OFFS = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }
local function outlinedText(text, font, x, y, col, out, w)
	for _, o in ipairs(OFFS) do
		draw.SimpleText(text, font, x + o[1] * w, y + o[2] * w, out, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	draw.SimpleText(text, font, x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function SF.DrawTag(idx, col, seed, alpha, light)
	fonts()
	local tag = SF.Tags[idx]
	if not tag then return end
	alpha = alpha or 255
	light = light or 1
	local r = rng(seed or idx)
	local font = tag.font == "b" and "nyrp.graf.b" or "nyrp.graf.a"
	surface.SetFont(font)
	local tw, th = surface.GetTextSize(tag.text)
	local main = mul(col, light, alpha)
	local dark = Color(10 * light, 10 * light, 14 * light, alpha * 0.92)
	local hi = Color(255 * light, 255 * light, 255 * light, alpha)
	local deco = tag.deco

	-- оформление ПОД текстом
	if deco == "bubble" then
		-- «throw-up»: пухлое облако под буквами
		local n = math.max(4, math.floor(tw / 70))
		for i = 0, n do
			local x = -tw / 2 + tw * i / n
			circle(x, r(-8, 8), th * 0.5 + 14, dark)
		end
		for i = 0, n do
			local x = -tw / 2 + tw * i / n
			circle(x, r(-6, 6), th * 0.5, main)
		end
	end

	local textCol = deco == "bubble" and hi or main
	outlinedText(tag.text, font, 0, 0, textCol, dark, 6)
	-- блик на буквах
	if deco ~= "bubble" then
		draw.SimpleText(tag.text, font, -3, -3, Color(255 * light, 255 * light, 255 * light, alpha * 0.18), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- подтёки краски
	local drips = deco == "drips" and 9 or 3
	for i = 1, drips do
		local x = r(-tw / 2 + 10, tw / 2 - 10)
		local len = r(14, deco == "drips" and 90 or 40)
		local y0 = th * 0.32
		surface.SetDrawColor(main)
		surface.DrawRect(x - 3, y0, 6, len)
		circle(x, y0 + len, 5, main)
	end

	-- оформление НАД / ВОКРУГ текста
	if deco == "crown" then
		local cw, cy = math.min(tw * 0.6, 220), -th * 0.5 - 18
		local x0 = -cw / 2
		-- корона: зубцы
		for i = 0, 2 do
			local bx = x0 + cw * i / 2
			poly({ { x = bx - cw * 0.16, y = cy }, { x = bx, y = cy - 70 }, { x = bx + cw * 0.16, y = cy } }, main)
			circle(bx, cy - 74, 10, main)
		end
		surface.SetDrawColor(main)
		surface.DrawRect(x0 - cw * 0.08, cy - 4, cw * 1.16, 18)
	elseif deco == "arrow" then
		local y = th * 0.42 + 18
		thickLine(-tw / 2 - 20, y + 14, tw / 2 + 10, y - 6, 14, main)
		local ax, ay = tw / 2 + 10, y - 6
		poly({ { x = ax - 10, y = ay - 30 }, { x = ax + 46, y = ay - 10 }, { x = ax + 6, y = ay + 30 } }, main)
	elseif deco == "stars" then
		star(-tw / 2 - 50, -th * 0.25, 34, main)
		star(tw / 2 + 50, -th * 0.35, 26, main)
		star(tw / 2 + 30, th * 0.3, 18, main)
	elseif deco == "cross" then
		for _, sx in ipairs({ -tw / 2 - 55, tw / 2 + 55 }) do
			thickLine(sx - 30, -30, sx + 30, 30, 14, main)
			thickLine(sx - 30, 30, sx + 30, -30, 14, main)
		end
		surface.SetDrawColor(main)
		surface.DrawRect(-tw / 2, -6, tw, 12)
	elseif deco == "heart" then
		local hx, hy, hr = -tw / 2 - 70, -10, 30
		circle(hx - hr * 0.7, hy - hr * 0.3, hr, main)
		circle(hx + hr * 0.7, hy - hr * 0.3, hr, main)
		poly({ { x = hx - hr * 1.65, y = hy }, { x = hx + hr * 1.65, y = hy }, { x = hx, y = hy + hr * 1.9 } }, main)
	elseif deco == "smile" then
		local sx, sy, sr = tw / 2 + 80, 0, 56
		circle(sx, sy, sr + 6, dark)
		circle(sx, sy, sr, main)
		circle(sx - 18, sy - 14, 8, dark)
		circle(sx + 18, sy - 14, 8, dark)
		for i = 0, 10 do
			local a = math.rad(20 + i * 14)
			circle(sx + math.cos(a) * 30, sy + math.sin(a) * 26, 5, dark)
		end
	end
end

-- ---------------------------------------------------------------- сеть --
local function angFor(n, rot)
	local ang = n:Angle()
	ang:RotateAroundAxis(ang:Up(), 90)
	ang:RotateAroundAxis(ang:Forward(), 90)
	ang:RotateAroundAxis(n, rot or 0)
	return ang
end

local function readOne()
	local id = net.ReadUInt(32)
	local pos, n = net.ReadVector(), net.ReadVector()
	local tag, col, rot, s = net.ReadUInt(8), net.ReadString(), net.ReadFloat(), net.ReadFloat()
	graf[id] = { pos = pos, normal = n, ang = angFor(n, rot), tag = tag, col = SF.Colors[col] and SF.Colors[col].col or color_white,
		seed = id, s = s, light = 1, lightAt = 0 }
end

net.Receive("nyrp.graf.full", function()
	graf = {}
	SF.ClientGraffiti = graf
	for _ = 1, net.ReadUInt(8) do readOne() end
end)
net.Receive("nyrp.graf.add", function()
	readOne()
end)
net.Receive("nyrp.graf.del", function()
	graf[net.ReadUInt(32)] = nil
end)

hook.Add("InitPostEntity", "nyrp.graffiti", function()
	timer.Simple(3, function()
		net.Start("nyrp.graf.req")
		net.SendToServer()
	end)
end)

-- ------------------------------------------------------------- в мире --
local SCALE = 0.11
local DRAW_DIST = 1600 * 1600

local function lightAt(g)
	if RealTime() < g.lightAt then return g.light end
	g.lightAt = RealTime() + 1 + math.random()
	local lc = render.GetLightColor(g.pos + g.normal * 4)
	g.light = math.Clamp(math.max(lc.x, lc.y, lc.z) * 1.8 + 0.12, 0.18, 1)
	return g.light
end

-- предпросмотр: куда ляжет рисунок
local function ghost()
	local ply = LocalPlayer()
	local w = ply:GetActiveWeapon()
	if not IsValid(w) or w:GetClass() ~= "nyrp_spraycan" then return end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 110, filter = ply, mask = MASK_SOLID })
	if not tr.Hit or tr.HitSky or not tr.HitWorld or math.abs(tr.HitNormal.z) > 0.35 then return end
	local inv = NYRP.Inventory and NYRP.Inventory.Data
	local it = inv and inv.equip and inv.equip.tool
	local c = it and SF.ColorOf(it.id)
	local col = c and SF.Colors[c].col or color_white
	cam.Start3D2D(tr.HitPos + tr.HitNormal * 0.8, angFor(tr.HitNormal, 0), SCALE)
	SF.DrawTag(SF.SelTag, col, 1, 70 + math.sin(RealTime() * 4) * 20, 1)
	cam.End3D2D()
end

hook.Add("PostDrawTranslucentRenderables", "nyrp.graffiti", function(depth, sky)
	if depth or sky then return end
	local eye = EyePos()
	for _, g in pairs(graf) do
		local to = eye - g.pos
		if to:LengthSqr() < DRAW_DIST and to:Dot(g.normal) > 0 then
			cam.Start3D2D(g.pos, g.ang, SCALE * g.s)
			SF.DrawTag(g.tag, g.col, g.seed, 235, lightAt(g))
			cam.End3D2D()
		end
	end
	ghost()
end)

-- --------------------------------------------------------- выбор рисунка --
function SF.OpenTagMenu()
	if IsValid(SF.TagMenu) then SF.TagMenu:Close() return end
	local inv = NYRP.Inventory and NYRP.Inventory.Data
	local it = inv and inv.equip and inv.equip.tool
	local c = it and SF.ColorOf(it.id)
	local col = c and SF.Colors[c].col or color_white
	local win, body = UI.Window("Выбор рисунка", "flame", 780, 560, { sub = c and ("Цвет: " .. SF.Colors[c].name) or nil })
	SF.TagMenu = win
	local cols, gap = 4, UI.S(10)
	local cw = (body:GetWide() - gap * (cols - 1)) / cols
	local ch = (body:GetTall() - gap * 2) / 3
	for i = 1, #SF.Tags do
		local b = vgui.Create("DButton", body)
		b:SetText("")
		b:SetPos(((i - 1) % cols) * (cw + gap), math.floor((i - 1) / cols) * (ch + gap))
		b:SetSize(cw, ch)
		b.Paint = function(s, w, h)
			local sel = SF.SelTag == i
			UI.RoundedRect(UI.S(10), 0, 0, w, h, sel and Color(247, 198, 0, 30) or (s:IsHovered() and Color(255, 255, 255, 14) or Color(255, 255, 255, 6)))
			UI.Outline(UI.S(10), 0, 0, w, h, sel and UI.Col.accent or UI.Col.stroke, 1)
			-- «кирпичная» подложка
			surface.SetDrawColor(120, 60, 40, 40)
			for y = UI.S(8), h - UI.S(8), UI.S(14) do surface.DrawRect(UI.S(8), y, w - UI.S(16), 1) end
			local sx, sy = s:LocalToScreen(w / 2, h / 2 - UI.S(4))
			local k = math.min(w / 640, h / 380)
			local m = Matrix()
			m:Translate(Vector(sx, sy, 0))
			m:Scale(Vector(k, k, 1))
			render.PushFilterMin(TEXFILTER.ANISOTROPIC)
			render.PushFilterMag(TEXFILTER.ANISOTROPIC)
			cam.PushModelMatrix(m, true)
			SF.DrawTag(i, col, 1, 255, 1)
			cam.PopModelMatrix()
			render.PopFilterMag()
			render.PopFilterMin()
		end
		b.DoClick = function()
			SF.SelTag = i
			cookie.Set("nyrp.graf.tag", tostring(i))
			UI.Sound("click")
			win:Close()
			NYRP.Notify("Рисунок выбран: «" .. SF.Tags[i].text .. "». ЛКМ по стене — нанести.", "info", 3)
		end
	end
end

-- облачко краски у тех, кто сейчас рисует
local emitter
local nextMist = 0
hook.Add("Think", "nyrp.graffiti.mist", function()
	if RealTime() < nextMist then return end
	nextMist = RealTime() + 0.05
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetNW2Float("nyrp.sprayUntil", 0) > CurTime() and p:GetPos():DistToSqr(EyePos()) < 1200 * 1200 then
			if not emitter then emitter = ParticleEmitter(p:GetPos()) end
			local tr = util.TraceLine({ start = p:EyePos(), endpos = p:EyePos() + p:GetAimVector() * 110, filter = p })
			local c = SF.Colors[p:GetNW2String("nyrp.sprayCol", "white")]
			local col = c and c.col or color_white
			local from = p:EyePos() - Vector(0, 0, 14) + p:GetAimVector() * 20
			local pt = emitter and emitter:Add("particle/particle_smokegrenade", from)
			if pt then
				local dir = (tr.HitPos - from):GetNormalized()
				pt:SetVelocity(dir * math.Rand(120, 180) + VectorRand() * 12)
				pt:SetDieTime(math.Rand(0.5, 0.9))
				pt:SetStartAlpha(110)
				pt:SetEndAlpha(0)
				pt:SetStartSize(2)
				pt:SetEndSize(math.Rand(10, 16))
				pt:SetColor(col.r, col.g, col.b)
				pt:SetAirResistance(200)
				pt:SetCollide(true)
			end
		end
	end
end)
