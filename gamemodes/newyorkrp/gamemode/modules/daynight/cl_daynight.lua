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

-- Часов на экране нет: время смотрят в телефоне (NYRP.Time.Format()).
