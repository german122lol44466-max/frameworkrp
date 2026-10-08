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
	local r = UI.S(9)
	UI.RoundedRect(r, x, y, w, h, sel and Color(20, 22, 30, 235) or Color(10, 12, 18, 190))
	if sel then
		UI.Outline(r, x, y, w, h, UI.Col.accent, 1)
		UI.RoundedRect(UI.S(2), x + w * 0.3, y + h - UI.S(3), w * 0.4, UI.S(3), UI.Col.accent)
	else
		UI.Outline(r, x, y, w, h, Color(255, 255, 255, 14), 1)
	end
	local model = wep.WorldModel or (wep.GetWeaponWorldModel and wep:GetWeaponWorldModel())
	local mat = model and model ~= "" and NYRP.ModelIconMat(model)
	local iconH = h - UI.S(26)
	if mat then
		surface.SetMaterial(mat)
		surface.SetDrawColor(255, 255, 255, (sel and 255 or 150) * a)
		local s = math.min(w - UI.S(10), iconH)
		surface.DrawTexturedRect(x + w / 2 - s / 2, y + UI.S(3) + (iconH - s) / 2, s, s)
	else
		UI.DrawIcon(wep:GetClass() == "nyrp_hands" and "hand" or "crosshair", x + w / 2, y + UI.S(3) + iconH / 2, iconH * 0.42,
			Color(255, 255, 255, (sel and 220 or 110) * a))
	end
	local name = nameOf(wep)
	surface.SetFont(NYRP.Font("semibold", 12))
	while #name > 3 and surface.GetTextSize(name) > w - UI.S(10) do name = string.sub(name, 1, -2) end
	draw.SimpleText(name, NYRP.Font("semibold", 12), x + w / 2, y + h - UI.S(13),
		Color(236, 237, 242, (sel and 255 or 140) * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if sel then
		local clip, ammo = wep:Clip1(), LocalPlayer():GetAmmoCount(wep:GetPrimaryAmmoType())
		if clip >= 0 or wep:GetPrimaryAmmoType() >= 0 then
			local ammoText = clip >= 0 and (clip .. "/" .. ammo) or tostring(ammo)
			draw.SimpleText(ammoText, NYRP.Font("bold", 11), x + w - UI.S(7), y + UI.S(9), UI.Col.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	draw.SimpleText(wep:GetSlot() + 1, NYRP.Font("bold", 11), x + UI.S(8), y + UI.S(9), sel and UI.Col.accent or UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local alpha = 0
hook.Add("HUDPaint", "nyrp.weaponselect", function()
	if open and RealTime() - lastInput > 2.5 then open = false end
	if open then
		for i = #list, 1, -1 do if not IsValid(list[i]) then refresh() break end end
	end
	alpha = UI.Approach(alpha, open and 1 or 0, open and 16 or 10)
	if alpha < 0.01 or #list == 0 then return end

	-- компактная лента: маленькие карточки, выбранная чуть шире
	local w, h, gap = UI.S(84), UI.S(72), UI.S(6)
	local wSel = UI.S(108)
	local total = (#list - 1) * (w + gap) + wSel
	local x0 = ScrW() / 2 - total / 2
	local y = ScrH() - UI.S(176) + (1 - UI.Ease(alpha)) * UI.S(24) -- над полоской выносливости
	surface.SetAlphaMultiplier(alpha)
	UI.BlurRect(x0 - UI.S(8), y - UI.S(8), total + UI.S(16), h + UI.S(16), 3, 255 * alpha)
	UI.RoundedRect(UI.S(12), x0 - UI.S(8), y - UI.S(8), total + UI.S(16), h + UI.S(16), Color(6, 8, 14, 150))
	local x = x0
	for i, wep in ipairs(list) do
		local sel = i == index
		local cw = sel and wSel or w
		cardX[i] = cardX[i] and UI.Approach(cardX[i], x, 18) or x
		card(cardX[i], y, cw, h, wep, sel, alpha)
		x = x + cw + gap
	end
	surface.SetAlphaMultiplier(1)
end)
