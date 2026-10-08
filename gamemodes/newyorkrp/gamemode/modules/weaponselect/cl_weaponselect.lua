--[[
	Выбор оружия: колесо мыши / цифры 1–6 открывают ленту карточек внизу экрана.
	Карточки сгруппированы по слотам; у каждой — 3D-иконка модели, название и патроны.
	ЛКМ — взять, ПКМ — отмена; сама закрывается через пару секунд.
]]

local UI = NYRP.UI
local WS = {}
NYRP.WeaponSelect = WS

NYRP.Config.HiddenHUD.CHudWeaponSelection = true

local open, openAt, lastInput = false, 0, 0
local list, index = {}, 1
local cardX = {}

local function weapons()
	local out = {}
	for _, w in ipairs(LocalPlayer():GetWeapons()) do
		if IsValid(w) then out[#out + 1] = w end
	end
	table.sort(out, function(a, b)
		local sa, sb = a:GetSlot(), b:GetSlot()
		if sa ~= sb then return sa < sb end
		return a:GetSlotPos() < b:GetSlotPos()
	end)
	return out
end

local function nameOf(w)
	local n = w:GetPrintName() or w:GetClass()
	return language.GetPhrase(n)
end

local function refresh()
	local cur = list[index]
	list = weapons()
	index = 1
	for i, w in ipairs(list) do
		if w == (IsValid(cur) and cur or LocalPlayer():GetActiveWeapon()) then index = i end
	end
end

local function show()
	if not open then
		open = true
		openAt = RealTime()
		list = {}
		refresh()
	end
	lastInput = RealTime()
end

local function move(dir)
	show()
	if #list == 0 then return end
	index = (index - 1 + dir) % #list + 1
	UI.Sound("hover")
end

local function slot(n)
	show()
	local found = {}
	for i, w in ipairs(list) do if w:GetSlot() == n - 1 then found[#found + 1] = i end end
	if #found == 0 then return end
	local nextI = found[1]
	for k, i in ipairs(found) do
		if i == index then nextI = found[k % #found + 1] end
	end
	index = nextI
	UI.Sound("hover")
end

local function confirm()
	local w = list[index]
	open = false
	if IsValid(w) then
		input.SelectWeapon(w)
		UI.Sound("click")
	end
end

hook.Add("PlayerBindPress", "nyrp.weaponselect", function(ply, bind, pressed)
	if not pressed or NYRP.State ~= "playing" or not ply:Alive() or ply:InVehicle() then return end
	if NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() then return end
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == "weapon_physgun" and input.IsMouseDown(MOUSE_LEFT) and string.find(bind, "inv", 1, true) then return end
	if bind == "invnext" then move(1) return true end
	if bind == "invprev" then move(-1) return true end
	local n = tonumber(string.match(bind, "^slot(%d)$"))
	if n then slot(n) return true end
	if open and string.find(bind, "+attack2", 1, true) then open = false UI.Sound("close") return true end
	if open and string.find(bind, "+attack", 1, true) then confirm() return true end
end)

local function card(x, y, w, h, wep, sel, a)
	UI.RoundedRect(UI.S(14), x, y, w, h, sel and Color(20, 22, 32, 240) or Color(12, 14, 22, 200))
	if sel then
		UI.Outline(UI.S(14), x, y, w, h, UI.Col.accent, 2)
		UI.Glow(x + w / 2, y + h, w * 1.2, UI.S(60), Color(247, 198, 0, 40))
	else
		UI.Outline(UI.S(14), x, y, w, h, Color(255, 255, 255, 18), 1)
	end
	local model = wep.WorldModel or (wep.GetWeaponWorldModel and wep:GetWeaponWorldModel())
	local mat = model and model ~= "" and NYRP.ModelIconMat(model)
	local iconH = h - UI.S(56)
	if mat then
		surface.SetMaterial(mat)
		surface.SetDrawColor(255, 255, 255, 255 * a)
		local s = math.min(w - UI.S(20), iconH)
		surface.DrawTexturedRect(x + w / 2 - s / 2, y + UI.S(8) + (iconH - s) / 2, s, s)
	else
		UI.DrawIcon(wep:GetClass() == "nyrp_hands" and "hand" or "crosshair", x + w / 2, y + UI.S(8) + iconH / 2, iconH * 0.45,
			Color(255, 255, 255, (sel and 220 or 120) * a))
	end
	local name = nameOf(wep)
	draw.SimpleText(name, NYRP.Font(sel and "bold" or "semibold", sel and 16 or 14), x + w / 2, y + h - UI.S(36),
		Color(236, 237, 242, (sel and 255 or 170) * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local clip, ammo = wep:Clip1(), LocalPlayer():GetAmmoCount(wep:GetPrimaryAmmoType())
	local ammoText = clip >= 0 and (clip .. " / " .. ammo) or (wep:GetPrimaryAmmoType() >= 0 and tostring(ammo) or "—")
	draw.SimpleText(ammoText, NYRP.Font("medium", 13), x + w / 2, y + h - UI.S(16), Color(150, 155, 170, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- номер слота
	UI.Circle(x + UI.S(18), y + UI.S(18), UI.S(11), sel and UI.Col.accent or Color(255, 255, 255, 22))
	draw.SimpleText(wep:GetSlot() + 1, NYRP.Font("bold", 12), x + UI.S(18), y + UI.S(18), sel and UI.Col.black or UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local alpha = 0
hook.Add("HUDPaint", "nyrp.weaponselect", function()
	if open and RealTime() - lastInput > 2.5 then open = false end
	if open then
		for i = #list, 1, -1 do if not IsValid(list[i]) then refresh() break end end
	end
	alpha = UI.Approach(alpha, open and 1 or 0, open and 16 or 10)
	if alpha < 0.01 or #list == 0 then return end

	local w, h, gap = UI.S(150), UI.S(150), UI.S(10)
	local wSel = UI.S(190)
	local total = (#list - 1) * (w + gap) + wSel
	local x0 = ScrW() / 2 - total / 2
	local y = ScrH() - UI.S(200) + (1 - UI.Ease(alpha)) * UI.S(40)
	surface.SetAlphaMultiplier(alpha)
	-- подложка
	UI.BlurRect(x0 - UI.S(16), y - UI.S(46), total + UI.S(32), h + UI.S(72), 4, 255 * alpha)
	UI.RoundedRect(UI.S(18), x0 - UI.S(16), y - UI.S(46), total + UI.S(32), h + UI.S(72), Color(6, 8, 14, 170))
	draw.SimpleText("ОРУЖИЕ", NYRP.Font("title", 18), x0, y - UI.S(24), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText("ЛКМ — взять · ПКМ — отмена · колесо / 1–6 — выбор", NYRP.Font("regular", 13), x0 + total, y - UI.S(24), UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	local x = x0
	for i, wep in ipairs(list) do
		local sel = i == index
		local cw = sel and wSel or w
		cardX[i] = cardX[i] and UI.Approach(cardX[i], x, 18) or x
		local lift = sel and UI.S(10) or 0
		card(cardX[i], y - lift, cw, h + lift, wep, sel, alpha)
		x = x + cw + gap
	end
	surface.SetAlphaMultiplier(1)
end)
