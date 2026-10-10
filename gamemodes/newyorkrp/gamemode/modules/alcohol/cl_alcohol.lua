--[[
	Опьянение на клиенте: покачивание камеры, размытие и двоение картинки, «плывущий» прицел,
	тёмные края экрана при тяжёлом опьянении.
]]

NYRP.Alcohol = NYRP.Alcohol or {}
local A = NYRP.Alcohol
local UI = NYRP.UI

local drunk = 0          -- сглаженный уровень 0..1
local myAngle = nil      -- угол, который мы положили в NYRP.Camera.ExtraAngle

local fb = CreateMaterial("nyrp_drunk_fb", "UnlitGeneric", {
	["$basetexture"] = "_rt_FullFrameFB", ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1,
})

hook.Add("Think", "nyrp.alcohol.fx", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local want = ply:Alive() and A.Level(ply) / 100 or 0
	drunk = UI.Approach(drunk, want, 0.4)
	-- покачивание взгляда (крен и «плавание»)
	local Cam = NYRP.Camera
	if not Cam then return end
	if drunk > 0.1 then
		-- не мешаем чужому эффекту (пробуждение): занимаем ExtraAngle только если он свободен или наш
		if Cam.ExtraAngle == nil or Cam.ExtraAngle == myAngle then
			local t, d = RealTime(), math.Clamp((drunk - 0.1) / 0.9, 0, 1)
			myAngle = Angle(math.sin(t * 0.9) * 2.2 * d, math.sin(t * 0.6) * 2.6 * d, math.sin(t * 0.75 + 1) * 7 * d)
			Cam.ExtraAngle = myAngle
		end
	elseif myAngle then
		if Cam.ExtraAngle == myAngle then Cam.ExtraAngle = nil end
		myAngle = nil
	end
end)

-- прицел медленно уплывает (ограниченное колебание, не накапливается)
local lastWob = 0
hook.Add("CreateMove", "nyrp.alcohol", function(cmd)
	if drunk < 0.3 then lastWob = 0 return end
	local ply = LocalPlayer()
	if not ply:Alive() then return end
	local k = (drunk - 0.3) / 0.7
	local t = RealTime()
	local wob = (math.sin(t * 0.8) * 1.6 + math.sin(t * 1.9) * 0.5) * k
	local d = wob - lastWob
	lastWob = wob
	local a = cmd:GetViewAngles()
	a.y = a.y + d
	a.p = math.Clamp(a.p + d * 0.4, -89, 89)
	cmd:SetViewAngles(a)
end)

hook.Add("RenderScreenspaceEffects", "nyrp.alcohol.fx", function()
	if drunk <= 0.12 then return end
	local d = math.Clamp((drunk - 0.12) / 0.88, 0, 1)
	-- двоение: копия кадра со смещением
	if d > 0.15 then
		render.UpdateScreenEffectTexture()
		local t = RealTime()
		local off = (UI.S(6) + UI.S(18) * d) * (0.6 + 0.4 * math.sin(t * 1.3))
		cam.Start2D()
			surface.SetMaterial(fb)
			surface.SetDrawColor(255, 255, 255, 70 * d)
			surface.DrawTexturedRect(off, math.sin(t * 0.7) * off * 0.3, ScrW(), ScrH())
		cam.End2D()
	end
	DrawMotionBlur(0.12, 0.25 + 0.55 * d, 0.01)
	DrawColorModify({
		["$pp_colour_addr"] = 0.02 * d, ["$pp_colour_addg"] = 0.01 * d, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1 + 0.05 * d,
		["$pp_colour_colour"] = 1 + 0.35 * d,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
end)

hook.Add("HUDPaintBackground", "nyrp.alcohol.fx", function()
	if drunk < 0.6 then return end
	local d = (drunk - 0.6) / 0.4
	local p = (math.sin(RealTime() * 1.5) + 1) / 2
	UI.Vignette(-UI.S(20), -UI.S(20), ScrW() + UI.S(40), ScrH() + UI.S(40), (90 + 60 * p) * d)
end)
