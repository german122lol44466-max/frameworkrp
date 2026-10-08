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

-- Отрисовка как в Helix: названия по дуге справа от центра экрана, выбранное — жёлтым и крупнее,
-- чем дальше от выбранного — тем мельче и прозрачнее; под списком — подсказка оружия (Instructions).
local alpha, delta = 0, 1
local infoA = 0
local infoH = 0
local matScale = Vector(1, 1, 0)

local function instructions(w)
	local t = w.Instructions or ""
	if w:GetClass() == "nyrp_hands" then t = "ПКМ — взять / отпустить предмет или тело\nЛКМ — бросить · R + мышь — повернуть" end
	return string.Trim(t)
end

hook.Add("HUDPaint", "nyrp.weaponselect", function()
	if open and RealTime() - lastInput > 3 then open = false end
	if open then
		for i = #list, 1, -1 do if not IsValid(list[i]) then refresh() break end end
	end
	local ft = FrameTime()
	alpha = Lerp(ft * 10, alpha, open and 1 or 0)
	if alpha < 0.01 or #list == 0 then return end
	delta = Lerp(ft * 12, delta, index)

	local x, y = ScrW() * 0.5, ScrH() * 0.5
	local spacing = math.pi * 0.85
	local radius = UI.S(240) * alpha
	local shiftX = ScrW() * 0.02
	local font = NYRP.Font("title", 34)
	-- высота подсказки выбранного оружия: всё, что ниже выбранного, сдвигаем вниз на неё (как в Helix)
	local selW = list[index]
	local selInfo = IsValid(selW) and instructions(selW) or ""
	local infoLines = 0
	if selInfo ~= "" then
		for _, line in ipairs(string.Explode("\n", selInfo)) do
			infoLines = infoLines + #UI.Wrap(line, NYRP.Font("regular", 14), ScrW() * 0.3)
		end
	end
	infoH = Lerp(ft * 10, infoH or 0, selInfo ~= "" and (UI.S(30) + infoLines * UI.S(18)) or 0)
	for i, w in ipairs(list) do
		local theta = (i - delta) * 0.1
		local fade = math.Clamp(1 - math.abs(theta * 3), 0, 1)
		if fade > 0 then
			local sel = i == index
			local col = sel and UI.Col.accent or Color(240, 241, 245)
			local name = utf8.upper and utf8.upper(nameOf(w)) or string.upper(nameOf(w))
			surface.SetFont(font)
			local _, th = surface.GetTextSize(name)
			local scale = math.max(0.2, 1 - math.abs(theta * 2))
			local m = Matrix()
			local push = i > index and infoH * math.Clamp(i - delta, 0, 1) or 0
			m:Translate(Vector(shiftX + x + math.cos(theta * spacing + math.pi) * radius + radius,
				y + math.sin(theta * spacing + math.pi) * radius - th / 2 + push, 1))
			m:Scale(matScale * scale)
			cam.PushModelMatrix(m)
			draw.SimpleText(name, font, 3, th / 2 + 3, Color(0, 0, 0, 160 * fade * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(name, font, 0, th / 2, Color(col.r, col.g, col.b, 255 * fade * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cam.PopModelMatrix()
		end
	end
	-- подсказка выбранного оружия
	local w = list[index]
	local info = IsValid(w) and instructions(w) or ""
	infoA = Lerp(ft * 4, infoA, info ~= "" and 1 or 0)
	if info ~= "" and infoA > 0.01 then
		local ix, iy = x + shiftX + UI.S(8), y + UI.S(36)
		draw.SimpleText("УПРАВЛЕНИЕ", NYRP.Font("bold", 13), ix, iy, UI.Alpha(UI.Col.accent, 255 * infoA * alpha))
		local ly = iy + UI.S(18)
		for _, line in ipairs(string.Explode("\n", info)) do
			for _, l in ipairs(UI.Wrap(line, NYRP.Font("regular", 14), ScrW() * 0.3)) do
				draw.SimpleText(l, NYRP.Font("regular", 14), ix, ly, Color(220, 222, 230, 230 * infoA * alpha))
				ly = ly + UI.S(18)
			end
		end
	end
end)
