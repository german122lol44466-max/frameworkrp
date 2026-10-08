--[[
	Голос: без стандартных панелей справа. Внизу по центру, над полоской выносливости — значок режима
	(шёпот/голос/крик), который «дышит» от громкости вашего голоса. Над говорящими — свой значок
	(modules/chat/cl_overhead). После смены режима 5 секунд виден радиус слышимости вокруг вас.
]]

local UI = NYRP.UI
local V = NYRP.Voice
local speaking, anim, level = false, 0, 0
local waves = {}

-- Не вызываем базовые функции — они создают стандартные панели.
function GM:PlayerStartVoice(ply)
	if ply == LocalPlayer() then speaking = true end
end

function GM:PlayerEndVoice(ply)
	if ply == LocalPlayer() then speaking = false end
end

hook.Add("HUDPaint", "nyrp.voice", function()
	if NYRP.HUDHidden() then return end
	local me = LocalPlayer()
	local talking = speaking or me:IsSpeaking()
	anim = UI.Approach(anim, talking and 1 or 0, talking and 14 or 8)
	if anim < 0.01 then return end

	local vol = me:VoiceVolume()
	if vol <= 0 and talking then vol = 0.25 + math.abs(math.sin(RealTime() * 7)) * 0.2 end
	level = UI.Approach(level, math.Clamp(vol * 2.2, 0, 1), 18)

	local x, y = ScrW() / 2, ScrH() - UI.S(100) -- по центру, над полоской выносливости
	if level > 0.45 and (waves[#waves] or 0) < RealTime() - 0.25 then waves[#waves + 1] = RealTime() end
	for i = #waves, 1, -1 do
		local t = (RealTime() - waves[i]) / 0.9
		if t > 1 then table.remove(waves, i)
		else UI.Ring(x, y, UI.S(26) + t * UI.S(26), Color(247, 198, 0, 120 * (1 - t) * anim)) end
	end
	local r = (UI.S(24) + level * UI.S(9)) * (0.6 + 0.4 * UI.Ease(anim))
	UI.Circle(x, y + UI.S(3), r + UI.S(4), Color(0, 0, 0, 90 * anim))
	UI.Circle(x, y, r, Color(255, 255, 255, 245 * anim))
	UI.DrawIcon(V.ModeOf(me).icon, x, y, r * 1.05, Color(10, 12, 18, 255 * anim))
end)

-- ------------------------------------------------------- смена режима --
local shownAt, shownMode = 0, nil

function V.SetMode(i)
	if not V.Modes[i] then return end
	net.Start("nyrp.voice.mode")
	net.WriteUInt(i, 4)
	net.SendToServer()
	shownAt, shownMode = RealTime(), i
	UI.Sound("toggle")
end

local function ringPoly(r, thick, seg)
	local out = {}
	for k = 0, seg - 1 do
		local a0, a1 = k / seg * math.pi * 2, (k + 1) / seg * math.pi * 2
		out[#out + 1] = {
			{ x = math.cos(a0) * r, y = math.sin(a0) * r }, { x = math.cos(a1) * r, y = math.sin(a1) * r },
			{ x = math.cos(a1) * (r - thick), y = math.sin(a1) * (r - thick) }, { x = math.cos(a0) * (r - thick), y = math.sin(a0) * (r - thick) },
		}
	end
	return out
end

-- Радиус слышимости: кольцо на земле вокруг персонажа (5 секунд после смены).
hook.Add("PostDrawTranslucentRenderables", "nyrp.voice.radius", function(depth, sky)
	if sky or not shownMode then return end
	local t = RealTime() - shownAt
	if t > 5 then shownMode = nil return end
	local ply = LocalPlayer()
	local mode = V.Modes[shownMode]
	local a = math.min(t / 0.3, 1) * math.min((5 - t) / 0.6, 1)
	local grow = UI.Ease(math.min(t / 0.6, 1))
	local r = mode.range * grow
	cam.Start3D2D(ply:GetPos() + Vector(0, 0, 3), Angle(0, 0, 0), 1)
	draw.NoTexture()
	surface.SetDrawColor(mode.col.r, mode.col.g, mode.col.b, 200 * a)
	for _, q in ipairs(ringPoly(r, math.max(3, r * 0.012), 96)) do surface.DrawPoly(q) end
	surface.SetDrawColor(mode.col.r, mode.col.g, mode.col.b, 28 * a)
	for _, q in ipairs(ringPoly(r, r * 0.25, 96)) do surface.DrawPoly(q) end
	cam.End3D2D()
end)

hook.Add("HUDPaint", "nyrp.voice.mode", function()
	if not shownMode or NYRP.HUDHidden() then return end
	local t = RealTime() - shownAt
	local mode = V.Modes[shownMode]
	local a = math.min(t / 0.25, 1) * math.min(math.max(5 - t, 0) / 0.5, 1)
	if a <= 0 then return end
	local meters = math.Round(mode.range / 52)
	local text = mode.name .. " · слышно на ~" .. meters .. " м"
	local font = NYRP.Font("semibold", 16)
	local w = UI.TextSize(text, font) + UI.S(60)
	local x, y = ScrW() / 2 - w / 2, ScrH() - UI.S(160) + (1 - a) * UI.S(10)
	surface.SetAlphaMultiplier(a)
	UI.RoundedRect(UI.S(16), x, y, w, UI.S(34), Color(10, 11, 16, 220))
	UI.Outline(UI.S(16), x, y, w, UI.S(34), UI.Alpha(mode.col, 90), 1)
	UI.DrawIcon(mode.icon, x + UI.S(24), y + UI.S(17), UI.S(18), mode.col)
	draw.SimpleText(text, font, x + UI.S(42), y + UI.S(17), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	surface.SetAlphaMultiplier(1)
end)
