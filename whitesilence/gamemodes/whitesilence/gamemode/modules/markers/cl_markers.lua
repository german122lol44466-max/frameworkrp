--[[
	Метки задач на экране.

	WS.Markers.Set({ { pos = Vector, kind = "goto", label = "", r = 0, ent = NULL }, ... })

	Ромб с иконкой (materials/whitesilence/markers/<kind>.png), под ним подпись и расстояние в метрах.
	Вблизи метка плавно исчезает (MarkerHide/MarkerFade), у прицела становится прозрачной, за краем экрана
	превращается в стрелку по краю. Новая метка появляется с пульсом и сигналом. Зона удержания (r > 0)
	рисуется кругом на земле.
]]

local M = {}
WS.Markers = M

local C = WS.Config
local UI = WS.UI
local E = WS.Ease
local PATH = "whitesilence/markers/"

M.List = {}

M.Colors = {
	["goto"] = Color(236, 214, 160), interact = Color(236, 240, 246), search = Color(236, 240, 246),
	intel = Color(236, 240, 246), defend = Color(140, 196, 240), extract = Color(236, 200, 120),
	charge = Color(240, 150, 90), radio = Color(150, 210, 230), power = Color(250, 220, 110),
	door = Color(236, 214, 160), enemy = Color(220, 90, 80),
}

local function key(m)
	return m.kind .. math.floor(m.pos.x / 64) .. ":" .. math.floor(m.pos.y / 64)
end

function M.Set(list)
	local old = {}
	for _, m in ipairs(M.List) do old[m.key] = m end
	local fresh = false
	for _, m in ipairs(list) do
		m.key = key(m)
		local o = old[m.key]
		m.born = o and o.born or RealTime()
		if not o and m.kind ~= "enemy" then fresh = true end
	end
	M.List = list
	if fresh then WS.Audio.Play("whitesilence/game/marker.ogg", { volume = 0.5 }) end
end

local function mat(kind) return UI.Mat(PATH .. kind .. ".png", "smooth mips") end

local function meters(u) return u * 0.01905 end

local function visible()
	return WS.HUD and WS.HUD.Visible() and not (WS.Story and WS.Story.Ending)
end

-- Точка на краю экрана (эллипс) в направлении мировой позиции
local function edgePoint(pos, w, h)
	local eye, ang = EyePos(), EyeAngles()
	local dir = (pos - eye):GetNormalized()
	local x = dir:Dot(ang:Right())
	local y = -dir:Dot(ang:Up())
	local len = math.sqrt(x * x + y * y)
	if len < 0.001 then x, y, len = 0, 1, 1 end
	x, y = x / len, y / len
	local rx, ry = w * 0.44, h * 0.40
	return w / 2 + x * rx, h / 2 + y * ry, math.deg(math.atan2(x, -y))
end

hook.Add("HUDPaint", "ws.markers", function()
	if #M.List == 0 or not visible() then return end
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local eye = EyePos()
	local alphaHud = WS.HUD.Alpha or 1
	local now = RealTime()
	for _, m in ipairs(M.List) do
		local pos = IsValid(m.ent) and (m.ent:GetPos() + Vector(0, 0, 84)) or m.pos
		local dist = eye:Distance(pos)
		local fade = E.Clamp01((dist - C.MarkerHide) / C.MarkerFade)
		if fade <= 0.01 then goto next end
		do
			local col = M.Colors[m.kind] or color_white
			local age = now - m.born
			local pop = E.OutCubic(age / 0.45)
			local sp = pos:ToScreen()
			local margin = 60 * s
			local on = sp.visible and sp.x > margin and sp.x < w - margin and sp.y > margin and sp.y < h - margin
			local size = Lerp(E.Clamp01(dist / 3000), 46, 34) * s
			local a = fade * alphaHud * (0.25 + 0.75 * pop)
			local x, y, rot
			if on then
				x, y = sp.x, sp.y
				-- у прицела метка не мешает целиться
				local dc = math.sqrt((x - w / 2) ^ 2 + (y - h / 2) ^ 2)
				a = a * Lerp(E.Clamp01((dc - 30 * s) / (90 * s)), 0.3, 1)
			else
				x, y, rot = edgePoint(pos, w, h)
				size = size * 0.85
			end
			-- свечение
			UI.Additive(true)
			surface.SetMaterial(mat("glow"))
			surface.SetDrawColor(col.r, col.g, col.b, 70 * a)
			surface.DrawTexturedRect(x - size * 1.2, y - size * 1.2, size * 2.4, size * 2.4)
			UI.Additive(false)
			-- пульс при появлении
			if age < 1.6 then
				local k = (age % 0.8) / 0.8
				surface.SetMaterial(mat("ring"))
				surface.SetDrawColor(col.r, col.g, col.b, 200 * (1 - k) * fade)
				local rs = size * (1 + k * 1.6)
				surface.DrawTexturedRect(x - rs / 2, y - rs / 2, rs, rs)
			end
			local ds = size * Lerp(pop, 1.6, 1)
			surface.SetMaterial(mat(m.kind))
			surface.SetDrawColor(col.r, col.g, col.b, 255 * a)
			surface.DrawTexturedRect(x - ds / 2, y - ds / 2, ds, ds)
			if rot then
				-- стрелка снаружи ромба
				surface.SetMaterial(mat("arrow"))
				local ax = x + math.sin(math.rad(rot)) * size * 0.9
				local ay = y - math.cos(math.rad(rot)) * size * 0.9
				surface.DrawTexturedRectRotated(ax, ay, size * 0.55, size * 0.55, -rot)
			else
				local ty = y + ds * 0.55
				if m.label ~= "" then
					draw.SimpleText(WS.Upper(m.label), WS.Font("menusemi", 15), x, ty, Color(236, 240, 246, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					ty = ty + 17 * s
				end
				draw.SimpleText(string.format("%d м", math.floor(meters(dist))), WS.Font("menulight", 15), x, ty,
					Color(col.r, col.g, col.b, 200 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
		end
		::next::
	end
end)

-- Зона удержания — светящийся круг на снегу
hook.Add("PostDrawTranslucentRenderables", "ws.markers", function(depth, sky)
	if depth or sky or #M.List == 0 or not visible() then return end
	for _, m in ipairs(M.List) do
		if m.r > 0 then
			local col = M.Colors[m.kind] or color_white
			local tr = util.TraceLine({ start = m.pos + Vector(0, 0, 40), endpos = m.pos - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
			local p = (tr.Hit and tr.HitPos or m.pos) + Vector(0, 0, 3)
			local pulse = 0.6 + 0.4 * math.sin(RealTime() * 2)
			cam.Start3D2D(p, Angle(0, RealTime() * 4 % 360, 0), 1)
				surface.SetMaterial(mat("zone"))
				surface.SetDrawColor(col.r, col.g, col.b, 70 * pulse)
				surface.DrawTexturedRect(-m.r, -m.r, m.r * 2, m.r * 2)
			cam.End3D2D()
		end
	end
end)
