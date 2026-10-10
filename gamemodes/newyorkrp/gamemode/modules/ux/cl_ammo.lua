--[[
	Счётчик патронов справа снизу (над водяным знаком): название оружия, в магазине / в запасе,
	ряд патронов магазина, состояние «поднято / опущено». Выстрел — толчок цифры и вылетающая гильза,
	перезарядка — полоса прогресса, мало патронов — красный. Только для оружия с патронами.
	Стандартный HUD патронов скрыт в core/sh_config.lua (HiddenHUD: CHudAmmo, CHudSecondaryAmmo).
]]

local UI = NYRP.UI
local SF = NYRP.Safety

NYRP.Config.HiddenHUD.CHudAmmo = true
NYRP.Config.HiddenHUD.CHudSecondaryAmmo = true

local AMMO_NAMES = {
	Pistol = "9 мм", ["357"] = ".357 Magnum", SMG1 = "4.6 мм", AR2 = "5.56 мм", Buckshot = "12 калибр",
	XBowBolt = "Болты", RPG_Round = "Ракеты", SMG1_Grenade = "Подствольные гранаты", Grenade = "Гранаты",
	AR2AltFire = "Энергошары", slam = "SLAM",
}

local names = {}
local function weaponName(wep)
	local cls = wep:GetClass()
	if names[cls] then return names[cls] end
	for _, def in pairs(NYRP.Items and NYRP.Items.List or {}) do
		if def.class == cls then names[cls] = def.name break end
	end
	if not names[cls] then
		local pn = wep:GetPrintName() or cls
		if string.sub(pn, 1, 1) == "#" then pn = language.GetPhrase(string.sub(pn, 2)) end
		names[cls] = pn
	end
	return names[cls]
end

local st = { alpha = 0, kick = 0, clip = nil, wep = nil, shells = {}, reload = 0, lowered = 0, flash = 0 }

local function isReloading(ply, wep)
	local vm = ply:GetViewModel()
	if not IsValid(vm) then return false, 0 end
	local act = vm:GetSequenceActivity(vm:GetSequence())
	if act == ACT_VM_RELOAD or act == ACT_VM_RELOAD_EMPTY or act == ACT_SHOTGUN_RELOAD_START or act == ACT_SHOTGUN_RELOAD_FINISH then
		return true, vm:GetCycle()
	end
	return false, 0
end

hook.Add("HUDPaint", "nyrp.ammo", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local wep = ply:Alive() and ply:GetActiveWeapon()
	local show = IsValid(wep) and not NYRP.HUDHidden() and string.sub(wep:GetClass(), 1, 5) ~= "nyrp_"
		and wep:GetPrimaryAmmoType() >= 0 and not (NYRP.Phone and NYRP.Phone.Open)
		and not (NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen())
	st.alpha = UI.Approach(st.alpha, show and 1 or 0, show and 7 or 10)
	if st.alpha < 0.01 then st.wep = nil return end
	if show then st.wep = wep end
	wep = st.wep
	if not IsValid(wep) then return end

	local clip, maxClip = wep:Clip1(), wep:GetMaxClip1()
	local reserve = ply:GetAmmoCount(wep:GetPrimaryAmmoType())
	local hasClip = maxClip > 0 and clip >= 0
	local shown = hasClip and clip or reserve

	-- выстрел: цифра дёргается, гильза улетает
	if st.clip and st.wepPrev == wep then
		if shown < st.clip then
			st.kick = 1
			st.shells[#st.shells + 1] = { born = RealTime(), dir = math.Rand(0.6, 1.2) }
		elseif shown > st.clip then
			st.flash = 1
			UI.Sound("hover")
		end
	end
	st.clip, st.wepPrev = shown, wep
	st.kick = UI.Approach(st.kick, 0, 7)
	st.flash = UI.Approach(st.flash, 0, 3)
	local reloading, cyc = isReloading(ply, wep)
	st.reload = UI.Approach(st.reload, reloading and 1 or 0, 10)
	local lowered = SF.Lowered(ply, wep)
	st.lowered = UI.Approach(st.lowered, lowered and 1 or 0, 8)

	local a = UI.Ease(st.alpha)
	surface.SetAlphaMultiplier(a)
	local W, H = UI.S(260), UI.S(104)
	local wmH = UI.S(300) * 120 / 600
	local x = ScrW() - W - UI.S(18) + (1 - a) * UI.S(30)
	local y = ScrH() - UI.S(14) - wmH - UI.S(12) - H
	UI.RoundedRect(UI.S(14), x, y, W, H, Color(10, 12, 20, 200))
	UI.Outline(UI.S(14), x, y, W, H, Color(255, 255, 255, 14), 1)
	if st.flash > 0.01 then UI.Outline(UI.S(14), x, y, W, H, Color(247, 198, 0, 160 * st.flash), 2) end

	local low = hasClip and maxClip > 0 and clip <= math.max(1, math.floor(maxClip * 0.25))
	local numCol = low and UI.LerpColor(0.5 + 0.5 * math.sin(RealTime() * 8), UI.Col.red, Color(255, 120, 110)) or UI.Col.text

	-- шапка: название и режим
	draw.SimpleText(string.upper(weaponName(wep)), NYRP.Font("bold", 13), x + UI.S(16), y + UI.S(12), UI.Col.dim)
	local mode = lowered and "ОПУЩЕНО" or "ПОДНЯТО"
	local modeCol = lowered and Color(160, 166, 180) or UI.Col.orange
	if not SF.Applies(wep) then mode, modeCol = "", nil end
	if modeCol then
		local mf = NYRP.Font("bold", 11)
		local mw = UI.TextSize(mode, mf) + UI.S(30)
		local mx = x + W - mw - UI.S(12)
		UI.RoundedRect(UI.S(9), mx, y + UI.S(10), mw, UI.S(18), UI.Alpha(modeCol, 40))
		UI.DrawIcon(lowered and "shield" or "crosshair", mx + UI.S(11), y + UI.S(19), UI.S(11), modeCol)
		draw.SimpleText(mode, mf, mx + UI.S(19), y + UI.S(19), modeCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- цифры: в магазине / в запасе
	local big = NYRP.Font("title", 44)
	local kickY = -st.kick * UI.S(6)
	local by = y + UI.S(56) + kickY
	local scale = 1 + st.kick * 0.08
	local ctext = tostring(shown)
	local m = Matrix()
	m:Translate(Vector(x + UI.S(16), by, 0))
	m:Scale(Vector(scale, scale, 1))
	m:Translate(Vector(-(x + UI.S(16)), -by, 0))
	cam.PushModelMatrix(m, true)
	draw.SimpleText(ctext, big, x + UI.S(16), by, numCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	cam.PopModelMatrix()
	local cw = UI.TextSize(ctext, big)
	if hasClip then
		draw.SimpleText("/ " .. reserve, NYRP.Font("titlemed", 22), x + UI.S(24) + cw, y + UI.S(62), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local ammoName = AMMO_NAMES[game.GetAmmoName(wep:GetPrimaryAmmoType()) or ""] or game.GetAmmoName(wep:GetPrimaryAmmoType()) or ""
	draw.SimpleText(hasClip and "в магазине / в запасе" or "в запасе", NYRP.Font("regular", 11), x + W - UI.S(14), y + UI.S(48), UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText(ammoName, NYRP.Font("semibold", 12), x + W - UI.S(14), y + UI.S(64), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	-- ряд патронов магазина (или полоса, если магазин большой)
	local rowY = y + H - UI.S(18)
	local rowX, rowW = x + UI.S(16), W - UI.S(32)
	if hasClip and maxClip <= 40 then
		local gap = UI.S(2)
		local bw = math.max(UI.S(2), math.floor((rowW - gap * (maxClip - 1)) / maxClip))
		bw = math.min(bw, UI.S(9))
		for i = 1, maxClip do
			local filled = i <= clip
			UI.RoundedRect(1, rowX + (i - 1) * (bw + gap), rowY, bw, UI.S(8),
				filled and (low and UI.Col.red or Color(247, 198, 0, 230)) or Color(255, 255, 255, 18))
		end
	elseif hasClip then
		UI.RoundedRect(UI.S(3), rowX, rowY, rowW, UI.S(6), Color(255, 255, 255, 18))
		UI.RoundedRect(UI.S(3), rowX, rowY, rowW * math.Clamp(clip / maxClip, 0, 1), UI.S(6), low and UI.Col.red or UI.Col.accent)
	end

	-- перезарядка
	if st.reload > 0.01 then
		local ra = st.reload
		UI.RoundedRect(UI.S(14), x, y, W, H, Color(10, 12, 20, 170 * ra))
		draw.SimpleText("ПЕРЕЗАРЯДКА", NYRP.Font("title", 20), x + W / 2, y + H / 2 - UI.S(8), Color(247, 198, 0, 255 * ra), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		UI.RoundedRect(UI.S(3), x + UI.S(30), y + H / 2 + UI.S(14), W - UI.S(60), UI.S(5), Color(255, 255, 255, 25 * ra))
		UI.RoundedRect(UI.S(3), x + UI.S(30), y + H / 2 + UI.S(14), (W - UI.S(60)) * math.Clamp(cyc, 0, 1), UI.S(5), Color(247, 198, 0, 255 * ra))
	end

	-- гильзы
	for i = #st.shells, 1, -1 do
		local s = st.shells[i]
		local t = (RealTime() - s.born) / 0.45
		if t >= 1 then
			table.remove(st.shells, i)
		else
			local sx = x + UI.S(30) + t * UI.S(70) * s.dir
			local sy = y + UI.S(40) - math.sin(t * math.pi) * UI.S(34) + t * UI.S(20)
			UI.RoundedRect(1, sx, sy, UI.S(3), UI.S(8), Color(214, 170, 60, 255 * (1 - t)))
		end
	end
	surface.SetAlphaMultiplier(1)
end)
