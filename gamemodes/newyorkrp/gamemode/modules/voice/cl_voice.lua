--[[
	Голос: без стандартных панелей справа. Снизу по центру — значок микрофона,
	который «дышит» от громкости вашего голоса. Над говорящими — свой значок (modules/chat/cl_overhead).
]]

local UI = NYRP.UI
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

	local x, y = ScrW() / 2, ScrH() - UI.S(70)
	if level > 0.45 and (waves[#waves] or 0) < RealTime() - 0.25 then waves[#waves + 1] = RealTime() end
	for i = #waves, 1, -1 do
		local t = (RealTime() - waves[i]) / 0.9
		if t > 1 then table.remove(waves, i)
		else UI.Ring(x, y, UI.S(26) + t * UI.S(26), Color(247, 198, 0, 120 * (1 - t) * anim)) end
	end
	local r = (UI.S(24) + level * UI.S(9)) * (0.6 + 0.4 * UI.Ease(anim))
	UI.Circle(x, y + UI.S(3), r + UI.S(4), Color(0, 0, 0, 90 * anim))
	UI.Circle(x, y, r, Color(255, 255, 255, 245 * anim))
	UI.DrawIcon("mic", x, y, r * 1.05, Color(10, 12, 18, 255 * anim))
end)
