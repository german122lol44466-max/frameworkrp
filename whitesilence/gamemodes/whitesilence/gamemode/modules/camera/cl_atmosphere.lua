--[[
	Атмосфера в игре — чтобы любая карта выглядела как Арктика, а не как Garry's Mod:
	  • туман метели (мир и скайбокс), дальность совпадает с тем, насколько далеко видят враги;
	  • холодная цветокоррекция, лёгкое свечение, плёночное зерно;
	  • снег вокруг игрока (3D-частицы по ветру) и порывы ветра в звуке;
	  • тяжёлая виньетка: сильнее на бегу, при усталости и ранениях.
	ws_fog 0 / ws_snow 0 — выключить туман / снег.
]]

local A = {}
WS.Atmos = A

local fogOn = CreateClientConVar("ws_fog", "1", true, false, "Туман метели", 0, 1)
local snowOn = CreateClientConVar("ws_snow", "1", true, false, "Снег вокруг игрока", 0, 1)

local function inGame()
	local ply = LocalPlayer()
	return IsValid(ply) and WS.Lobby.InGame(ply) and not (WS.Menu and WS.Menu.IsOpen()) and not (WS.Intro and WS.Intro.IsPlaying())
end

-- ---------------------------------------------------------------- туман

local FOG_COL = { 196, 206, 218 }
local fogEnd = 2600

hook.Add("SetupWorldFog", "ws.atmos", function()
	if not fogOn:GetBool() or not inGame() then return end
	-- в ПНВ и тепловизоре туман «пробивается» дальше
	local mode = WS.Vision and WS.Vision.Mode
	local far = mode == "thermal" and 4200 or (mode == "nvg" and 3200 or fogEnd)
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(120)
	render.FogEnd(far)
	render.FogMaxDensity(mode and 0.75 or 0.94)
	render.FogColor(FOG_COL[1], FOG_COL[2], FOG_COL[3])
	return true
end)

hook.Add("SetupSkyboxFog", "ws.atmos", function(scale)
	if not fogOn:GetBool() or not inGame() then return end
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(0)
	render.FogEnd(800 * scale)
	render.FogMaxDensity(0.98)
	render.FogColor(FOG_COL[1], FOG_COL[2], FOG_COL[3])
	return true
end)

-- ---------------------------------------------------------------- цвет

local grade = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0.004, ["$pp_colour_addb"] = 0.018,
	["$pp_colour_brightness"] = -0.02, ["$pp_colour_contrast"] = 1.08, ["$pp_colour_colour"] = 0.72,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0.05,
}

hook.Add("RenderScreenspaceEffects", "ws.atmos", function()
	if not inGame() or not LocalPlayer():Alive() then return end
	if WS.Vision and WS.Vision.Mode then return end   -- у ПНВ своя картинка
	DrawColorModify(grade)
	DrawBloom(0.72, 1.2, 9, 9, 1, 1, 0.9, 0.95, 1)
end)

-- ---------------------------------------------------------------- снег (частицы вокруг камеры)

local emitter
local nextSnow = 0
local wind = Vector(140, 60, 0)

hook.Add("Think", "ws.atmos", function()
	if not snowOn:GetBool() or not inGame() then return end
	local now = CurTime()
	if now < nextSnow then return end
	nextSnow = now + 0.05
	local eye = EyePos()
	-- под крышей снега нет
	local sky = util.TraceLine({ start = eye, endpos = eye + Vector(0, 0, 2000), mask = MASK_SOLID_BRUSHONLY })
	if not sky.HitSky and sky.Hit then return end
	if not emitter or not emitter:IsValid() then emitter = ParticleEmitter(eye, false) end
	if not emitter then return end
	emitter:SetPos(eye)
	-- порывы
	local gust = 0.6 + 0.6 * math.sin(now * 0.37) + 0.3 * math.sin(now * 1.3)
	wind = Vector(150 * gust, 70 * gust, 0)
	for _ = 1, 10 do
		local pos = eye + Vector(math.Rand(-700, 700), math.Rand(-700, 700), math.Rand(-120, 420)) - wind * 0.4
		local p = emitter:Add("particle/particle_glow_05", pos)
		if p then
			p:SetVelocity(wind + Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(-120, -70)))
			p:SetDieTime(math.Rand(2.5, 4.5))
			p:SetStartAlpha(0)
			p:SetEndAlpha(math.Rand(140, 220))
			p:SetStartSize(math.Rand(0.8, 2.2))
			p:SetEndSize(math.Rand(0.8, 2.2))
			p:SetColor(235, 242, 250)
			p:SetAirResistance(10)
			p:SetGravity(Vector(0, 0, -60))
			p:SetCollide(true)
			p:SetBounce(0)
		end
	end
end)

-- ---------------------------------------------------------------- ветер в звуке

local windSnd
timer.Create("ws.atmos.wind", 1, 0, function()
	local on = inGame()
	if on and not windSnd then
		windSnd = WS.Audio.Play("whitesilence/intro/blizzard.ogg", { volume = 0.22, fade = 4, loop = true })
	elseif not on and windSnd then
		windSnd:Stop(3)
		windSnd = nil
	end
	if windSnd then
		-- в помещении тише
		local eye = EyePos()
		local sky = util.TraceLine({ start = eye, endpos = eye + Vector(0, 0, 2000), mask = MASK_SOLID_BRUSHONLY })
		local indoor = sky.Hit and not sky.HitSky
		local gust = 0.6 + 0.3 * math.sin(CurTime() * 0.37)
		windSnd:Fade((indoor and 0.07 or 0.24) * (0.7 + gust * 0.5), 1)
	end
end)

-- ---------------------------------------------------------------- виньетка

local vig = 0
function A.DrawVignette(ply)
	local FX = WS.Intro.FX
	local st = WS.Move.Stamina(ply) / WS.Config.StaminaMax
	local hp = math.Clamp(ply:Health() / math.max(ply:GetMaxHealth(), 1), 0, 1)
	local run = ply:GetVelocity():Length2D() > WS.Config.WalkSpeed + 25
	local want = 0.95 + (run and 0.15 or 0) + (1 - st) * 0.25 + (1 - hp) * 0.3
	vig = WS.Approach(vig, want, 0.8)
	-- два слоя: края почти чёрные, тень заходит далеко к центру
	FX.Vignette(math.min(vig, 1))
	FX.Vignette(math.Clamp(vig - 0.45, 0, 1))
	local w, h = ScrW(), ScrH()
	surface.SetMaterial(WS.UI.Mat(WS.Intro.Path .. "vignette.png", "smooth"))
	surface.SetDrawColor(8, 12, 20, 160 * math.min(vig, 1))
	surface.DrawTexturedRect(-w * 0.12, -h * 0.12, w * 1.24, h * 1.24)
	-- лёгкое зерно — чтобы картинка не была «чистой» движковой
	FX.Grain(0.25)
end
