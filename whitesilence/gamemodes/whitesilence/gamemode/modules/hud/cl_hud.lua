--[[
	HUD в духе SCP-игр: минимум элементов, изогнутые панели (как на выпуклом стекле шлема).

	Панели рисуются в текстуру (render target), затем выводятся на экран узкими полосками разной высоты —
	внешний край выше и ниже, внутренний ниже: получается изгиб. Слева — здоровье, броня, стамина; справа —
	оружие и патроны, прибор зрения и его батарея. Плюс точка прицела, виньетка, вспышка при уроне.
	Стандартный HUD Garry's Mod скрыт.
]]

local H = {}
WS.HUD = H
local C = WS.Config
local UI = WS.UI
local E = WS.Ease

-- ---------------------------------------------------------------- скрыть стандартное

local HIDE = {
	CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true, CHudCrosshair = true,
	CHudDamageIndicator = true, CHudWeaponSelection = true, CHudSuitPower = true, CHudPoisonDamageIndicator = true,
	CHudSquadStatus = true, CHudGeiger = true, CHudZoom = true, CHudChat = true, CHudHistoryResource = true,
	CHudDeathNotice = true, CHudVoiceStatus = true, CHudVoiceSelfStatus = true,
}

hook.Add("HUDShouldDraw", "ws.hud", function(name)
	if HIDE[name] then return false end
end)

-- подписи над целью, лента убийств и подобранное — свои или не нужны
hook.Add("HUDDrawTargetID", "ws.hud", function() return true end)
hook.Add("HUDDrawPickupHistory", "ws.hud", function() return true end)
hook.Add("DrawDeathNotice", "ws.hud", function() return true end)
hook.Add("HUDItemPickedUp", "ws.hud", function() return true end)
hook.Add("HUDAmmoPickedUp", "ws.hud", function() return true end)
hook.Add("HUDWeaponPickedUp", "ws.hud", function() return true end)

-- ---------------------------------------------------------------- шрифты панелей (в пикселях текстуры)

local fontsReady = false
local function fonts()
	if fontsReady then return end
	fontsReady = true
	local function f(name, font, size, weight)
		surface.CreateFont(name, { font = font, size = size, weight = weight, extended = true, antialias = true })
	end
	f("ws.hud.big", "Exo 2", 46, 700)
	f("ws.hud.mid", "Exo 2", 28, 600)
	f("ws.hud.small", "Exo 2", 20, 400)
	f("ws.hud.tiny", "Exo 2 SemiBold", 15, 600)
end

local function icon(name)
	return UI.Mat("whitesilence/icons/" .. name .. ".png", "smooth")
end

-- ---------------------------------------------------------------- render target + изгиб

local RT_W, RT_H, USED_H = 512, 256, 170
local panels = {}

local function panel(id)
	local p = panels[id]
	if p then return p end
	local rt = GetRenderTarget("ws_hud_" .. id, RT_W, RT_H)
	local mat = CreateMaterial("ws_hud_" .. id .. "_mat", "UnlitGeneric", {
		["$basetexture"] = rt:GetName(), ["$translucent"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1",
	})
	p = { rt = rt, mat = mat }
	panels[id] = p
	return p
end

local function renderPanel(id, drawFn)
	local p = panel(id)
	render.PushRenderTarget(p.rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.ClearDepth()
	render.Clear(0, 0, 0, 0)
	cam.Start2D()
	drawFn(RT_W, USED_H)
	cam.End2D()
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
	return p
end

--[[
	Вывод панели с изгибом. x, y — левый верхний угол, w, h — размер на экране;
	outer = "left" | "right" — какой край внешний (он выше и сильнее «выгнут» к зрителю).
]]
local STRIPS = 28
local function drawCurved(p, x, y, w, h, outer, alpha, curve)
	curve = curve or 0.16
	surface.SetMaterial(p.mat)
	surface.SetDrawColor(255, 255, 255, 255 * alpha)
	local mid = y + h / 2
	for i = 0, STRIPS - 1 do
		local u0, u1 = i / STRIPS, (i + 1) / STRIPS
		local d = outer == "left" and (1 - (u0 + u1) / 2) or ((u0 + u1) / 2)   -- 1 — у внешнего края
		local b = 1 + curve * d * d
		local sh = h * b
		local sy = mid - sh / 2 - h * 0.05 * d                                  -- внешний край чуть приподнят
		local sx = x + w * u0
		surface.DrawTexturedRectUV(sx, sy, w / STRIPS + 1, sh, u0, 0, u1, USED_H / RT_H)
	end
end

-- ---------------------------------------------------------------- содержимое панелей

local healthShown, staminaShown, lastHealth, flash = 100, 100, nil, 0

local function bar(x, y, w, h, frac, col, segments)
	surface.SetDrawColor(255, 255, 255, 40)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
	surface.DrawRect(x, y, w * math.Clamp(frac, 0, 1), h)
	if segments then
		surface.SetDrawColor(0, 0, 0, 255)
		for i = 1, segments - 1 do surface.DrawRect(x + w * i / segments - 1, y, 2, h) end
	end
end

local function drawLeft(w, h)
	local ply = LocalPlayer()
	local hp, maxHp = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1)
	local armor = ply:Armor()
	local st = WS.Move.Stamina(ply) / C.StaminaMax
	local low = hp / maxHp < 0.3
	local pulse = low and (0.6 + 0.4 * math.sin(RealTime() * 6)) or 1
	local hcol = low and Color(235, 70, 60) or Color(240, 242, 246)

	surface.SetMaterial(icon("health"))
	surface.SetDrawColor(hcol.r, hcol.g, hcol.b, 255 * pulse)
	surface.DrawTexturedRect(20, 22, 40, 40)
	draw.SimpleText(tostring(math.Round(healthShown)), "ws.hud.big", 72, 42, Color(hcol.r, hcol.g, hcol.b, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	bar(20, 76, 320, 7, healthShown / maxHp, hcol, 10)

	if armor > 0 then
		surface.SetMaterial(icon("armor"))
		surface.SetDrawColor(196, 210, 228, 255)
		surface.DrawTexturedRect(230, 26, 30, 30)
		draw.SimpleText(tostring(armor), "ws.hud.mid", 268, 42, Color(196, 210, 228), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local ex = WS.Move.Exhausted(ply)
	local scol = ex and Color(220, 90, 70, 255 * (0.55 + 0.45 * math.sin(RealTime() * 8))) or Color(226, 190, 120)
	surface.SetMaterial(icon("stamina"))
	surface.SetDrawColor(scol.r, scol.g, scol.b, scol.a or 255)
	surface.DrawTexturedRect(22, 100, 26, 26)
	bar(58, 110, 282, 5, staminaShown / C.StaminaMax, scol)
	draw.SimpleText("ВЫНОСЛИВОСТЬ", "ws.hud.tiny", 58, 134, Color(200, 206, 216, 170))
end

local function drawRight(w, h)
	local ply = LocalPlayer()
	local wep = ply:GetActiveWeapon()
	local x = w - 20
	if IsValid(wep) then
		local name = wep.GetPrintName and wep:GetPrintName() or wep:GetClass()
		draw.SimpleText(string.upper(name), "ws.hud.small", x, 24, Color(200, 206, 216), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		local clip = wep:Clip1()
		if clip >= 0 then
			local reserve = ply:GetAmmoCount(wep:GetPrimaryAmmoType())
			local maxClip = math.max(wep:GetMaxClip1(), 1)
			local lowAmmo = clip <= maxClip * 0.25
			local col = lowAmmo and Color(235, 90, 70) or Color(240, 242, 246)
			surface.SetFont("ws.hud.mid")
			local rw = surface.GetTextSize("/ " .. reserve)
			draw.SimpleText("/ " .. reserve, "ws.hud.mid", x, 70, Color(170, 178, 190), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			draw.SimpleText(tostring(clip), "ws.hud.big", x - rw - 10, 66, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			surface.SetFont("ws.hud.big")
			local cw = surface.GetTextSize(tostring(clip))
			surface.SetMaterial(icon("ammo"))
			surface.SetDrawColor(col.r, col.g, col.b, 230)
			surface.DrawTexturedRect(x - rw - cw - 52, 48, 34, 34)
			-- патроны в магазине — ряд штрихов
			local n = math.min(maxClip, 40)
			local sw = 300 / n
			for i = 1, n do
				local filled = i <= math.ceil(clip / maxClip * n)
				surface.SetDrawColor(255, 255, 255, filled and 200 or 35)
				surface.DrawRect(x - 300 + (i - 1) * sw, 100, math.max(sw - 2, 1), 7)
			end
		end
	end
	-- прибор зрения и батарея
	local V = WS.Vision
	if V then
		local mode = V.Mode
		local col = mode == "nvg" and Color(110, 255, 130) or mode == "thermal" and Color(255, 170, 90) or Color(170, 178, 190)
		surface.SetMaterial(icon(mode == "thermal" and "thermal" or "nvg"))
		surface.SetDrawColor(col.r, col.g, col.b, mode and 255 or 120)
		surface.DrawTexturedRect(x - 230, 120, 24, 24)
		bar(x - 196, 130, 120, 5, V.Battery / C.NVGBattery, col, 6)
		draw.SimpleText(mode == "nvg" and "ПНВ" or mode == "thermal" and "ТЕПЛОВИЗОР" or "F / N", "ws.hud.tiny", x, 132,
			Color(col.r, col.g, col.b, mode and 230 or 140), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

-- ---------------------------------------------------------------- отрисовка

function H.Visible()
	local ply = LocalPlayer()
	return IsValid(ply) and ply:Alive() and WS.Lobby.InGame(ply) and not (WS.Menu and WS.Menu.IsOpen())
		and not (WS.Intro and WS.Intro.IsPlaying())
end

H.Alpha = 0

hook.Add("HUDPaint", "ws.hud", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local FX = WS.Intro.FX
	FX.Ensure()
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local dt = FrameTime()

	-- общая виньетка в игре; при низком здоровье — красная пульсация
	if WS.Lobby.InGame(ply) and ply:Alive() then
		FX.Vignette(0.6)
		local hpk = 1 - math.Clamp(ply:Health() / math.max(ply:GetMaxHealth(), 1) / 0.35, 0, 1)
		if hpk > 0 then
			local p = (0.5 + 0.5 * math.sin(RealTime() * 4)) * hpk
			surface.SetMaterial(UI.Mat(WS.Intro.Path .. "vignette.png", "smooth"))
			surface.SetDrawColor(160, 0, 0, 200 * p)
			surface.DrawTexturedRect(0, 0, w, h)
		end
	end

	-- вспышка при уроне
	local hp = ply:Health()
	if lastHealth and hp < lastHealth and ply:Alive() then flash = math.min(1, flash + (lastHealth - hp) / 30) end
	lastHealth = hp
	if flash > 0 then
		surface.SetDrawColor(140, 0, 0, 120 * flash)
		surface.DrawRect(0, 0, w, h)
		flash = math.max(0, flash - dt * 1.8)
	end

	H.Alpha = WS.Approach(H.Alpha, H.Visible() and (WS.Wake and WS.Wake.HudAlpha() or 1) or 0, 2.5)
	if H.Alpha <= 0.01 then return end
	fonts()
	healthShown = Lerp(dt * 8, healthShown, math.max(hp, 0))
	staminaShown = Lerp(dt * 10, staminaShown, WS.Move.Stamina(ply))

	local pl = renderPanel("l", drawLeft)
	local pr = renderPanel("r", drawRight)
	local pw, ph = 460 * s, 460 * s * USED_H / RT_W
	drawCurved(pl, 36 * s, h - ph - 34 * s, pw, ph, "left", H.Alpha)
	drawCurved(pr, w - pw - 36 * s, h - ph - 34 * s, pw, ph, "right", H.Alpha)

	-- точка прицела (у TFA свой прицел — тогда не рисуем)
	local wep = ply:GetActiveWeapon()
	if not (IsValid(wep) and wep.IsTFAWeapon) then
		local cx, cy = w / 2, h / 2
		surface.SetDrawColor(0, 0, 0, 120 * H.Alpha)
		surface.DrawRect(cx - 2, cy - 2, 4, 4)
		surface.SetDrawColor(240, 242, 246, 200 * H.Alpha)
		surface.DrawRect(cx - 1, cy - 1, 2, 2)
	end
end)
