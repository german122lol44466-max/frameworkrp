--[[
	Меню состояния здоровья (J): схема тела с ранениями по частям, справа — медицина из сумки.
	Перетащите предмет на часть тела — персонаж начнёт лечить. Успех зависит от навыка «Медицина».
]]

local UI = NYRP.UI
local Cond = NYRP.Cond
NYRP.Health = NYRP.Health or {}
local H = NYRP.Health

local GOLD = Color(247, 198, 0)
local RED = Color(226, 70, 64)
local ORANGE = Color(236, 150, 70)
local OK = Color(110, 200, 120)

local PARTS = { head = "Голова", body = "Корпус", arm = "Руки", leg = "Ноги" }

-- состояние части тела: { текст, цвет } или nil, если цела
local function partState(ply, part)
	local out = {}
	local function add(t, c) out[#out + 1] = { t, c } end
	if part == "head" then
		if Cond.Until(ply, "wound_head") > 0 then add("Пулевое ранение", RED) end
		if Cond.Until(ply, "concussion") > 0 then add("Сотрясение", ORANGE) end
	elseif part == "body" then
		if Cond.Until(ply, "wound_body") > 0 then add("Ранение в корпус", RED) end
		if ply:GetNW2Bool("nyrp.bleeding") then add("Кровотечение", RED) end
		if ply:Health() < 50 then add("Ушибы и ссадины", ORANGE) end
	elseif part == "arm" then
		if Cond.Until(ply, "wound_arm") > 0 then add("Ранение — рука дрожит", RED) end
	elseif part == "leg" then
		if Cond.Until(ply, "wound_leg") > 0 then add("Ранение — хромота", RED) end
		if Cond.Until(ply, "fracture") > 0 then add("Перелом", RED) end
		if Cond.Until(ply, "bruise") > 0 then add("Ушиб", ORANGE) end
	end
	return out
end

local function medItems()
	local list = {}
	local data = NYRP.Inventory.Data
	for slot, it in pairs(data and data.slots or {}) do
		local def = NYRP.Items.Get(it.id)
		if def and def.treats then list[#list + 1] = { slot = tonumber(slot), it = it, def = def } end
	end
	table.sort(list, function(a, b) return a.slot < b.slot end)
	return list
end

function H.Close()
	if IsValid(H.Panel) and not H.Panel.Closing then H.Panel:Close() end
end

function H.Toggle()
	if IsValid(H.Panel) and not H.Panel.Closing then H.Close() return end
	if NYRP.State ~= "playing" or not LocalPlayer():Alive() then return end
	local win, body, box = UI.Window("Состояние здоровья", "medkit", 900, 640)
	H.Panel = win
	local ply = LocalPlayer()
	local drag   -- { entry, x, y }
	local hoverPart
	local rects = {} -- part -> { {x,y,w,h}, ... } в координатах body

	local fig = vgui.Create("DPanel", body)
	fig:Dock(LEFT)
	fig:SetWide(UI.S(470))
	fig.Paint = function(s, w, h)
		local cx = w * 0.36
		local top = UI.S(10)
		local u = UI.S(1)
		rects = {
			head = { { cx - 34 * u, top, 68 * u, 78 * u } },
			body = { { cx - 62 * u, top + 92 * u, 124 * u, 170 * u } },
			arm = { { cx - 104 * u, top + 98 * u, 36 * u, 190 * u }, { cx + 68 * u, top + 98 * u, 36 * u, 190 * u } },
			leg = { { cx - 58 * u, top + 268 * u, 52 * u, 230 * u }, { cx + 6 * u, top + 268 * u, 52 * u, 230 * u } },
		}
		-- части тела
		for part, rs in pairs(rects) do
			local st = partState(ply, part)
			local col = #st > 0 and st[1][2] or OK
			local pulse = #st > 0 and (0.55 + 0.45 * math.abs(math.sin(RealTime() * 3))) or 1
			local hov = drag and hoverPart == part
			for _, r in ipairs(rs) do
				local rad = part == "head" and UI.S(30) or UI.S(14)
				UI.RoundedRect(rad, r[1], r[2], r[3], r[4], Color(col.r, col.g, col.b, (hov and 140 or 60) * pulse))
				UI.Outline(rad, r[1], r[2], r[3], r[4], hov and GOLD or Color(col.r, col.g, col.b, 200), hov and 3 or 1)
			end
		end
		-- подписи справа от фигуры
		local lx, ly = w * 0.66, UI.S(14)
		for _, part in ipairs({ "head", "body", "arm", "leg" }) do
			local st = partState(ply, part)
			draw.SimpleText(PARTS[part], NYRP.Font("bold", 17), lx, ly, #st > 0 and color_white or UI.Col.dim)
			ly = ly + UI.S(22)
			if #st == 0 then
				draw.SimpleText("в порядке", NYRP.Font("regular", 13), lx, ly, OK)
				ly = ly + UI.S(18)
			end
			for _, e in ipairs(st) do
				draw.SimpleText(e[1], NYRP.Font("medium", 13), lx, ly, e[2])
				ly = ly + UI.S(18)
			end
			ly = ly + UI.S(14)
		end
		-- здоровье
		local hp = ply:Health() / math.max(ply:GetMaxHealth(), 1)
		local by = h - UI.S(40)
		draw.SimpleText("Здоровье " .. ply:Health() .. "%", NYRP.Font("bold", 15), UI.S(10), by - UI.S(22), color_white)
		UI.RoundedRect(UI.S(4), UI.S(10), by, w - UI.S(30), UI.S(10), Color(0, 0, 0, 140))
		UI.RoundedRect(UI.S(4), UI.S(10), by, math.max(UI.S(10), (w - UI.S(30)) * hp), UI.S(10), UI.LerpColor(hp, RED, OK))
	end

	local side = vgui.Create("DPanel", body)
	side:Dock(FILL)
	side:DockMargin(UI.S(16), 0, 0, 0)
	side.Paint = function(_, w, h)
		local lvl = NYRP.Skills and NYRP.Skills.Level(ply, "medicine") or 0
		draw.SimpleText("Медицина: уровень " .. lvl, NYRP.Font("bold", 15), 0, 0, GOLD)
		draw.SimpleText("Перетащите предмет на часть тела", NYRP.Font("regular", 13), 0, UI.S(22), UI.Col.dim)
	end
	local list = vgui.Create("DScrollPanel", side)
	list:Dock(FILL)
	list:DockMargin(0, UI.S(50), 0, 0)

	local function rebuild()
		list:Clear()
		local items = medItems()
		if #items == 0 then
			local e = list:Add("DPanel")
			e:Dock(TOP)
			e:SetTall(UI.S(80))
			e.Paint = function(_, w, h)
				for i, l in ipairs(UI.Wrap("В сумке нет медицины. Бинты, шины, аптечки и хирургические наборы продают торговцы.", NYRP.Font("regular", 14), w)) do
					draw.SimpleText(l, NYRP.Font("regular", 14), 0, (i - 1) * UI.S(20), Color(170, 172, 182))
				end
			end
			return
		end
		for _, e in ipairs(items) do
			local row = list:Add("DButton")
			row:SetText("")
			row:Dock(TOP)
			row:SetTall(UI.S(64))
			row:DockMargin(0, 0, 0, UI.S(8))
			row:SetCursor("hand")
			row.Paint = function(s, w, h)
				local active = drag and drag.e == e
				UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, active and 6 or (s:IsHovered() and 22 or 12)))
				NYRP.DrawItemIcon(e.it.id, UI.S(6), UI.S(6), h - UI.S(12), h - UI.S(12), active and 60 or 255)
				draw.SimpleText(e.def.name .. (e.it.n > 1 and ("  ×" .. e.it.n) or ""), NYRP.Font("semibold", 15), h + UI.S(4), UI.S(12), color_white)
				local parts = {}
				for _, p in ipairs({ "head", "body", "arm", "leg" }) do if e.def.treats[p] then parts[#parts + 1] = string.lower(PARTS[p]) end end
				local need = e.def.treatSkill or 0
				local lvl = NYRP.Skills and NYRP.Skills.Level(ply, "medicine") or 0
				draw.SimpleText(table.concat(parts, ", ") .. (need > 0 and ("  ·  медицина " .. need) or ""), NYRP.Font("regular", 12), h + UI.S(4), UI.S(36),
					lvl >= need and UI.Col.dim or RED)
			end
			row.OnMousePressed = function(s, code)
				if code ~= MOUSE_LEFT then return end
				drag = { e = e }
				UI.Sound("drag")
			end
		end
	end
	rebuild()
	local lastSig
	win.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() end
		-- сумка изменилась — пересобрать список
		local sig = ""
		for _, e in ipairs(medItems()) do sig = sig .. e.slot .. e.it.id .. e.it.n .. (e.it.data and e.it.data.uses or "") .. ";" end
		if sig ~= lastSig then lastSig = sig if not drag then rebuild() end end
		hoverPart = nil
		if drag then
			local mx, my = fig:ScreenToLocal(gui.MouseX(), gui.MouseY())
			for part, rs in pairs(rects) do
				for _, r in ipairs(rs) do
					if mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4] then hoverPart = part end
				end
			end
			if not input.IsMouseDown(MOUSE_LEFT) then
				if hoverPart then
					net.Start("nyrp.health.treat")
					net.WriteUInt(drag.e.slot, 8)
					net.WriteString(hoverPart)
					net.SendToServer()
					UI.Sound("drop")
					s:Close()
				end
				drag = nil
			end
		end
	end
	-- «призрак» предмета у курсора
	win.PaintOver = function()
		if not drag then return end
		local sz = UI.S(56)
		NYRP.DrawItemIcon(drag.e.it.id, gui.MouseX() - sz / 2, gui.MouseY() - sz / 2, sz, sz, 230)
	end
end
