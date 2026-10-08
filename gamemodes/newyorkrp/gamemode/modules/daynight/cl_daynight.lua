--[[
	Клиент: перерисовка света после смены (lightmaps), тёмное небо ночью и на картах без env_skypaint,
	лёгкая цветокоррекция, часы в левом верхнем углу.
]]

local UI = NYRP.UI
local T = NYRP.Time

net.Receive("nyrp.time.light", function()
	-- пересчёт освещения карты после смены light style
	timer.Create("nyrp.time.redownload", 0.2, 1, function() render.RedownloadAllLightmaps(true) end)
end)

-- Ночное небо поверх 2D-скайбокса (если на карте нет env_skypaint).
local hasSkyPaint, checkedAt = false, 0
hook.Add("PostDraw2DSkyBox", "nyrp.time", function()
	local d = T.Daylight()
	if d >= 0.99 then return end
	if RealTime() > checkedAt then
		checkedAt = RealTime() + 10
		hasSkyPaint = IsValid(ents.FindByClass("env_skypaint")[1])
	end
	if hasSkyPaint then return end -- небо красит сервер через env_skypaint
	render.OverrideDepthEnable(true, false)
	cam.Start3D(vector_origin, EyeAngles())
	render.SetColorMaterial()
	render.DrawSphere(vector_origin, -64, 24, 24, Color(4, 7, 18, 235 * (1 - d)))
	cam.End3D()
	render.OverrideDepthEnable(false, false)
end)

hook.Add("RenderScreenspaceEffects", "nyrp.time", function()
	local d = T.Daylight()
	if d >= 0.99 or NYRP.State ~= "playing" then return end
	local n = 1 - d
	DrawColorModify({
		["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.012 * n,
		["$pp_colour_brightness"] = -0.02 * n, ["$pp_colour_contrast"] = 1 + 0.04 * n,
		["$pp_colour_colour"] = 1 - 0.3 * n,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0.05 * n,
	})
end)

-- Часы.
hook.Add("HUDPaint", "nyrp.time", function()
	if NYRP.HUDHidden() then return end
	local icon, name = T.Phase()
	local x, y = UI.S(26), UI.S(26)
	local col = icon == "moon" and Color(150, 175, 230) or (icon == "sun" and UI.Col.accent or UI.Col.orange)
	UI.DrawIcon(icon, x + 1, y + UI.S(10) + 2, UI.S(22), Color(0, 0, 0, 150))
	UI.DrawIcon(icon, x, y + UI.S(10), UI.S(22), col)
	local font = NYRP.Font("bold", 22)
	draw.SimpleText(T.Format(), font, x + UI.S(20) + 1, y + UI.S(10) + 2, Color(0, 0, 0, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(T.Format(), font, x + UI.S(20), y + UI.S(10), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(name, NYRP.Font("medium", 12), x + UI.S(20), y + UI.S(30), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
