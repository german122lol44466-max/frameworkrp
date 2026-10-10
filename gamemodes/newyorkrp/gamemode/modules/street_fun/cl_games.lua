--[[
	Кости, монетка и карты (клиент): результат над головой игрока на 5 секунд —
	кубики с точками, монетка, карта или число броска. Всплывает, покачивается и тает.
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun
local UI = NYRP.UI

local shows = {}   -- [ply] = { kind, a, b, born }
local LIFE = 5

net.Receive("nyrp.fun.show", function()
	local ply, kind, a, b = net.ReadEntity(), net.ReadString(), net.ReadUInt(32), net.ReadUInt(32)
	if not IsValid(ply) then return end
	shows[ply] = { kind = kind, a = a, b = b, born = RealTime() }
end)

local PIPS = {
	[1] = { { 0, 0 } },
	[2] = { { -1, -1 }, { 1, 1 } },
	[3] = { { -1, -1 }, { 0, 0 }, { 1, 1 } },
	[4] = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
	[5] = { { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
	[6] = { { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } },
}

local function die(x, y, s, n, spin, a)
	local m = Matrix()
	m:Translate(Vector(x, y, 0))
	m:Rotate(Angle(0, spin, 0))
	cam.PushModelMatrix(m, true)
	UI.RoundedRect(s * 0.18, -s / 2 + 3, -s / 2 + 5, s, s, Color(0, 0, 0, 90 * a))
	UI.RoundedRect(s * 0.18, -s / 2, -s / 2, s, s, Color(246, 244, 238, 255 * a))
	UI.Outline(s * 0.18, -s / 2, -s / 2, s, s, Color(0, 0, 0, 60 * a), 2)
	for _, p in ipairs(PIPS[n] or PIPS[1]) do
		UI.Circle(p[1] * s * 0.27, p[2] * s * 0.27, s * 0.09, n == 1 and Color(200, 30, 40, 255 * a) or Color(20, 20, 24, 255 * a))
	end
	cam.PopModelMatrix()
end

local function card(n, a, flip)
	local r, s = SF.CardParts(n)
	local red = SF.Suits[s][2]
	local w, h = 120, 170
	local sx = math.abs(math.cos(flip))   -- «переворот» карты при появлении
	local m = Matrix()
	m:Scale(Vector(sx, 1, 1))
	cam.PushModelMatrix(m, true)
	UI.RoundedRect(10, -w / 2 + 4, -h / 2 + 6, w, h, Color(0, 0, 0, 100 * a))
	if flip > math.pi / 2 then
		UI.RoundedRect(10, -w / 2, -h / 2, w, h, Color(250, 250, 246, 255 * a))
		UI.Outline(10, -w / 2, -h / 2, w, h, Color(0, 0, 0, 50 * a), 2)
		local col = red and Color(206, 34, 44, 255 * a) or Color(20, 20, 26, 255 * a)
		local suit = SF.Suits[s][1]
		draw.SimpleText(SF.Ranks[r], NYRP.FontRaw("title", 34), -w / 2 + 12, -h / 2 + 6, col)
		draw.SimpleText(suit, NYRP.FontRaw("semibold", 26), -w / 2 + 14, -h / 2 + 42, col)
		draw.SimpleText(suit, NYRP.FontRaw("semibold", 80), 0, 10, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(SF.Ranks[r], NYRP.FontRaw("title", 34), w / 2 - 12, h / 2 - 6, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	else
		-- рубашка
		UI.RoundedRect(10, -w / 2, -h / 2, w, h, Color(150, 30, 40, 255 * a))
		UI.Outline(10, -w / 2 + 8, -h / 2 + 8, w - 16, h - 16, Color(255, 220, 200, 120 * a), 2)
	end
	cam.PopModelMatrix()
end

local function drawShow(sh, a, t)
	local pop = UI.Ease(math.min(t / 0.35, 1))
	local m = Matrix()
	m:Scale(Vector(0.6 + 0.4 * pop, 0.6 + 0.4 * pop, 1))
	cam.PushModelMatrix(m, true)
	if sh.kind == "dice" then
		local spin = (1 - pop) * 300
		die(-50, 0, 80, sh.a, spin, a)
		die(50, 0, 80, sh.b, -spin * 0.8, a)
		draw.SimpleText("= " .. (sh.a + sh.b), NYRP.FontRaw("title", 34), 0, 70, Color(255, 255, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	elseif sh.kind == "coin" then
		local flip = math.min(t / 0.8, 1)
		local sx = math.abs(math.cos(flip * math.pi * 5))
		local cm = Matrix()
		cm:Scale(Vector(math.max(sx, 0.08), 1, 1))
		cam.PushModelMatrix(cm, true)
		UI.Circle(3, 5, 64, Color(0, 0, 0, 90 * a))
		UI.Circle(0, 0, 64, Color(214, 170, 60, 255 * a))
		UI.Circle(0, 0, 54, Color(236, 196, 90, 255 * a))
		if flip >= 1 then UI.DrawIcon(sh.a == 1 and "badge" or "coins", 0, 0, 56, Color(150, 110, 30, 255 * a)) end
		cam.PopModelMatrix()
		if flip >= 1 then
			draw.SimpleText(sh.a == 1 and "ОРЁЛ" or "РЕШКА", NYRP.FontRaw("title", 38), 0, 96, Color(255, 255, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	elseif sh.kind == "card" then
		card(sh.a, a, math.min(t / 0.6, 1) * math.pi)
	else
		-- /roll: «кубик-ромб» с числом
		local spin = (1 - pop) * 200
		local rm = Matrix()
		rm:Rotate(Angle(0, 45 + spin, 0))
		cam.PushModelMatrix(rm, true)
		UI.RoundedRect(14, -52 + 3, -52 + 5, 104, 104, Color(0, 0, 0, 90 * a))
		UI.RoundedRect(14, -52, -52, 104, 104, Color(247, 198, 0, 255 * a))
		cam.PopModelMatrix()
		local shown = t < 0.6 and math.random(1, math.max(sh.b, 2)) or sh.a
		draw.SimpleText(tostring(shown), NYRP.FontRaw("title", shown >= 1000 and 30 or 46), 0, 0, Color(14, 14, 18, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("из " .. sh.b, NYRP.FontRaw("semibold", 26), 0, 92, Color(255, 255, 255, 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	cam.PopModelMatrix()
end

hook.Add("PostDrawTranslucentRenderables", "nyrp.fun.show", function(depth, sky)
	if depth or sky then return end
	local eye = EyePos()
	for ply, sh in pairs(shows) do
		local t = RealTime() - sh.born
		if not IsValid(ply) or t > LIFE or not ply:Alive() then
			shows[ply] = nil
		elseif ply ~= LocalPlayer() or (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then
			local head = ply:LookupBone("ValveBiped.Bip01_Head1")
			local hp = head and ply:GetBonePosition(head) or ply:EyePos()
			local pos = hp + Vector(0, 0, 30 + math.sin(RealTime() * 2) * 1.2)
			if pos:DistToSqr(eye) < 700 * 700 then
				local a = math.Clamp((LIFE - t) / 0.6, 0, 1)
				cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
				drawShow(sh, a, t)
				cam.End3D2D()
			end
		end
	end
end)

-- свой результат от первого лица — на экране, сверху по центру
hook.Add("HUDPaint", "nyrp.fun.show", function()
	local me = LocalPlayer()
	local sh = shows[me]
	if not sh or (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then return end
	local t = RealTime() - sh.born
	if t > LIFE then return end
	local a = math.Clamp((LIFE - t) / 0.6, 0, 1)
	local m = Matrix()
	local k = UI.S(100) / 100
	m:Translate(Vector(ScrW() / 2, UI.S(170), 0))
	m:Scale(Vector(k, k, 1))
	cam.PushModelMatrix(m, true)
	drawShow(sh, a, t)
	cam.PopModelMatrix()
end)
