--[[
	Атмосфера и цветокоррекция: кинематографичный грейд (чуть приглушённые цвета, плотнее контраст,
	тёплые света / холодные тени), мягкое свечение, лёгкая дымка вдали и зерно плёнки.
	Ночью (modules/daynight) дымка темнее и холоднее.
]]

local UI = NYRP.UI

local function daylight()
	return NYRP.Time and NYRP.Time.Daylight() or 1
end

hook.Add("RenderScreenspaceEffects", "nyrp.atmosphere", function()
	if NYRP.State ~= "playing" then return end
	DrawColorModify({
		["$pp_colour_addr"] = 0.008, ["$pp_colour_addg"] = 0.004, ["$pp_colour_addb"] = 0.0,
		["$pp_colour_brightness"] = -0.015, ["$pp_colour_contrast"] = 1.09,
		["$pp_colour_colour"] = 0.86,
		["$pp_colour_mulr"] = 0.04, ["$pp_colour_mulg"] = 0.015, ["$pp_colour_mulb"] = -0.02,
	})
	DrawBloom(0.72, 0.9, 7, 7, 1, 1, 1, 0.95, 0.88)
end)

-- Дымка: видна вдали, у края мира. Цвет и плотность зависят от времени суток.
local function fog(scale)
	local d = daylight()
	local col = LerpVector(d, Vector(14, 18, 30), Vector(170, 178, 186))
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(Lerp(d, 200, 900) * scale)
	render.FogEnd(Lerp(d, 3500, 9000) * scale)
	render.FogMaxDensity(Lerp(d, 0.75, 0.45))
	render.FogColor(col.x, col.y, col.z)
	return true
end
hook.Add("SetupWorldFog", "nyrp.atmosphere", function() return fog(1) end)
hook.Add("SetupSkyboxFog", "nyrp.atmosphere", function(scale) return fog(scale) end)

-- Зерно плёнки — едва заметное, «живое» (noclamp — текстура повторяется по экрану).
local grain = Material("nyrp/ui/grain.png", "noclamp smooth")
hook.Add("HUDPaintBackground", "nyrp.atmosphere.grain", function()
	if NYRP.State ~= "playing" then return end
	local w, h = ScrW(), ScrH()
	local t = math.floor(RealTime() * 24)
	local ox, oy = (t * 37) % 256, (t * 91) % 256
	surface.SetMaterial(grain)
	surface.SetDrawColor(255, 255, 255, 9)
	surface.DrawTexturedRectUV(0, 0, w, h, ox / 256, oy / 256, ox / 256 + w / 256, oy / 256 + h / 256)
end)
