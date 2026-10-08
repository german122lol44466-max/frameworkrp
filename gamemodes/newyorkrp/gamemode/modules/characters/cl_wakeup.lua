--[[
	Появление персонажа: после затемнения он «открывает глаза» (веки, моргание, размытие)
	шорох одежды и глубокий вдох (реальная запись, sound/nyrp/fx/wake.wav).
]]

local UI = NYRP.UI
local wake

-- Открытость глаз во времени: 0 — закрыты, 1 — открыты.
local keys = { { 0, 0 }, { 0.7, 0 }, { 1.5, 0.35 }, { 1.8, 0.06 }, { 2.9, 0.62 }, { 3.15, 0.42 }, { 4.2, 1 } }
local function openness(t)
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			return Lerp(UI.EaseInOut((t - a[1]) / (b[1] - a[1])), a[2], b[2])
		end
	end
	return 1
end

function NYRP.Wakeup(gender, silent)
	NYRP.Chars.HoldBlack = false
	timer.Remove("nyrp.holdblack")
	wake = { start = RealTime() }
	UI.Sound("spawn")
	local pitch = gender == "female" and 112 or 100
	if not silent then timer.Simple(0.45, function()
		if IsValid(LocalPlayer()) then LocalPlayer():EmitSound("nyrp/fx/wake.wav", 60, pitch, 0.8, CHAN_STATIC) end
	end) end
end

hook.Add("Think", "nyrp.wakeup", function()
	if not wake then return end
	local t = RealTime() - wake.start
	-- глубокий вдох: голова чуть запрокидывается
	local yawn = math.Clamp((t - 1.6) / 0.8, 0, 1) * (1 - math.Clamp((t - 3.4) / 0.9, 0, 1))
	NYRP.Camera.ExtraAngle = Angle(-9 * UI.EaseInOut(yawn) + math.sin(t * 1.3) * 1.5 * (1 - math.Clamp(t / 5, 0, 1)), 0,
		math.sin(t * 0.9) * 2 * (1 - math.Clamp(t / 5, 0, 1)))
	if t > 5 then
		wake = nil
		NYRP.Camera.ExtraAngle = nil
	end
end)

hook.Add("RenderScreenspaceEffects", "nyrp.wakeup", function()
	if not wake then return end
	local o = openness(RealTime() - wake.start)
	DrawColorModify({
		["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.08 * (1 - o), ["$pp_colour_contrast"] = 1,
		["$pp_colour_colour"] = 1 - 0.75 * (1 - o),
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
	if o < 0.95 then DrawMotionBlur(0.15, 0.8 * (1 - o), 0.01) end
end)

hook.Add("PostRenderVGUI", "nyrp.wakeup", function()
	if not wake then return end
	local t = RealTime() - wake.start
	local o = openness(t)
	local w, h = ScrW(), ScrH()
	if o < 1 then UI.BlurRect(0, 0, w, h, 10 * (1 - o)) end
	local lid = h / 2 * (1 - o)
	local soft = h * 0.22
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, w, lid)
	surface.DrawRect(0, h - lid, w, lid)
	surface.SetMaterial(UI.Mat("vgui/gradient-u"))
	surface.DrawTexturedRect(0, lid, w, soft)
	surface.SetMaterial(UI.Mat("vgui/gradient-d"))
	surface.DrawTexturedRect(0, h - lid - soft, w, soft)
end)
