--[[
	Инвентарь (Q): сумка, снаряжение, панель предмета, настройки.
	Q — открыть: камера смотрит на сумку, руки её открывают со звуком молнии, затем окно.
	Shift+Q у админов — стандартное спавн-меню.
]]

local UI = NYRP.UI
local Items = NYRP.Items
NYRP.Inventory = NYRP.Inventory or {}
local Inv = NYRP.Inventory
Inv.Data = Inv.Data or { size = 12, slots = {}, equip = {} }
Inv.Page = Inv.Page or "bag"

local SLOT = 80   -- размер ячейки (1080p)
local GAP = 8

net.Receive("nyrp.inv.sync", function()
	Inv.Data = { size = net.ReadUInt(8), slots = net.ReadTable(), equip = net.ReadTable() }
	if IsValid(Inv.Detail) and Inv.Detail.Ref then Inv.RefreshDetail() end
end)

function Inv.IsOpen() return IsValid(Inv.Root) end

local function bagCfg()
	return NYRP.Config.Bags[LocalPlayer():GetNW2String("nyrp.bag", "waistbag")] or NYRP.Config.Bags.waistbag
end

local function itemAt(kind, key)
	if kind == "eq" then return Inv.Data.equip[key] end
	return Inv.Data.slots[tonumber(key) or -1]
end

-- --------------------------------------------------------------- действия --
local function send(name, fn)
	net.Start(name)
	fn()
	net.SendToServer()
end

function Inv.Move(fk, fkey, tk, tkey)
	send("nyrp.inv.move", function()
		net.WriteString(fk) net.WriteString(tostring(fkey)) net.WriteString(tk) net.WriteString(tostring(tkey))
	end)
end
function Inv.Use(slot) send("nyrp.inv.use", function() net.WriteUInt(slot, 8) end) end
function Inv.Equip(slot) send("nyrp.inv.equip", function() net.WriteUInt(slot, 8) end) end
function Inv.Unequip(eq) send("nyrp.inv.unequip", function() net.WriteString(eq) end) end
function Inv.Drop(kind, key, all)
	send("nyrp.inv.drop", function() net.WriteString(kind) net.WriteString(tostring(key)) net.WriteBool(all) end)
end

function Inv.UseItem(kind, key)
	local it = itemAt(kind, key)
	if not it then return end
	if it.id == "idcard" then
		if NYRP.ShowPassport then NYRP.ShowPassport(it.data) end
		return
	end
	if kind == "inv" then Inv.Use(tonumber(key)) end
end

function Inv.ContextMenu(kind, key)
	local it = itemAt(kind, key)
	if not it then return end
	local def = Items.Get(it.id)
	if not def then return end
	local opts = {}
	if def.use or it.id == "idcard" then
		opts[#opts + 1] = { text = def.useText or "Использовать", icon = it.id == "idcard" and "id" or "check", func = function() Inv.UseItem(kind, key) end }
	end
	if it.id == "idcard" and kind == "inv" then
		opts[#opts + 1] = { text = "Показать человеку", icon = "user", func = function()
			send("nyrp.inv.view", function() net.WriteUInt(tonumber(key), 8) end)
		end }
	end
	if Items.EquipTarget(def) then
		if kind == "eq" then
			opts[#opts + 1] = { text = def.category == "weapon" and "Убрать в сумку" or "Снять", icon = "arrow_left", func = function() Inv.Unequip(key) end }
		else
			opts[#opts + 1] = { text = def.category == "weapon" and "Взять в руки" or "Надеть", icon = def.category == "weapon" and "crosshair" or "hanger",
				func = function() Inv.Equip(tonumber(key)) end }
		end
	end
	opts[#opts + 1] = { text = "Осмотреть", icon = "eye", func = function() Inv.ShowDetail(kind, key) end }
	if not def.noDrop then
		opts[#opts + 1] = { divider = true }
		opts[#opts + 1] = { text = "Бросить", icon = "arrow_right", color = UI.Col.red, func = function() Inv.Drop(kind, key, false) end }
		if it.n > 1 then
			opts[#opts + 1] = { text = "Бросить всё (" .. it.n .. ")", icon = "trash", color = UI.Col.red, func = function() Inv.Drop(kind, key, true) end }
		end
	end
	UI.Menu(opts)
end

-- ---------------------------------------------------------------- ячейка --
-- kind: "inv" (ячейка сумки), "eq" (слот снаряжения), key: индекс или id слота.
Inv.SlotPanels = {}
local SLOTP = {}

function SLOTP:Init()
	self.Hover = 0
	self.Pop = 0
	self:SetCursor("hand")
	Inv.SlotPanels[self] = true
end
function SLOTP:OnRemove() Inv.SlotPanels[self] = nil end
function SLOTP:Setup(kind, key, opts)
	self.Kind, self.Key = kind, key
	self.Opts = opts or {}
end
function SLOTP:GetItem() return itemAt(self.Kind, self.Key) end

function SLOTP:OnCursorEntered()
	if self:GetItem() then UI.Sound("hover") end
end

function SLOTP:OnMousePressed(code)
	local it = self:GetItem()
	if code == MOUSE_RIGHT then
		if it then Inv.ContextMenu(self.Kind, self.Key) end
		return
	end
	if code ~= MOUSE_LEFT or not it then return end
	Inv.Press = { panel = self, x = gui.MouseX(), y = gui.MouseY(), kind = self.Kind, key = self.Key }
end

function SLOTP:Accepts(dragKind, dragKey, item)
	if self.Kind == "invlist" then return dragKind == "eq" end
	if self.Kind == "eq" then
		return dragKind == "inv" and Items.EquipTarget(Items.Get(item.id)) == self.Key
	end
	return true
end

function SLOTP:Paint(w, h)
	local it = self:GetItem()
	local drag = Inv.Drag
	local dragging = drag and drag.kind == self.Kind and tostring(drag.key) == tostring(self.Key)
	local accepting = drag and not dragging and self:Accepts(drag.kind, drag.key, drag.item)
	self.Hover = UI.Approach(self.Hover, (self:IsHovered() or (accepting and self.DropHover)) and 1 or 0, 14)
	local r = UI.S(8)

	local bg = self.Kind == "eq" and Color(255, 255, 255, 10) or Color(0, 0, 0, 70)
	UI.RoundedRect(r, 0, 0, w, h, bg)
	if accepting then UI.RoundedRect(r, 0, 0, w, h, Color(247, 198, 0, 14 + self.Hover * 30)) end
	UI.Outline(r, 0, 0, w, h, accepting and UI.Alpha(UI.Col.accent, 120 + self.Hover * 100) or Color(255, 255, 255, 14 + self.Hover * 40), 1)

	if it and not dragging then
		local pad = UI.S(6)
		NYRP.DrawItemIcon(it.id, pad, pad, w - pad * 2, h - pad * 2)
		if it.n > 1 then
			draw.SimpleText("×" .. it.n, NYRP.Font("bold", 14), w - UI.S(6), h - UI.S(4), UI.Col.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
		if Inv.DetailRef and Inv.DetailRef.kind == self.Kind and tostring(Inv.DetailRef.key) == tostring(self.Key) then
			UI.Outline(r, 0, 0, w, h, UI.Col.accent, 2)
		end
	elseif self.Opts.icon then
		UI.DrawIcon(self.Opts.icon, w / 2, h / 2 - (self.Opts.label and UI.S(6) or 0), math.min(w, h) * 0.36, Color(255, 255, 255, 40 + self.Hover * 40))
		if self.Opts.label then
			draw.SimpleText(self.Opts.label, NYRP.Font("medium", 12), w / 2, h - UI.S(8), Color(255, 255, 255, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end
end
vgui.Register("NYRP.InvSlot", SLOTP, "Panel")

-- Найти ячейку под курсором (для бросания).
local function slotUnderCursor()
	local mx, my = gui.MouseX(), gui.MouseY()
	for p in pairs(Inv.SlotPanels) do
		if IsValid(p) and p:IsVisible() and p.Kind then
			local x, y = p:LocalToScreen(0, 0)
			if mx >= x and my >= y and mx < x + p:GetWide() and my < y + p:GetTall() then return p end
		end
	end
end

local function overPanel(pnl)
	if not IsValid(pnl) or not pnl:IsVisible() then return false end
	local mx, my = gui.MouseX(), gui.MouseY()
	local x, y = pnl:LocalToScreen(0, 0)
	return mx >= x and my >= y and mx < x + pnl:GetWide() and my < y + pnl:GetTall()
end

-- Перетаскивание обрабатывается глобально: нажали на ячейку -> сдвинули -> отпустили над целью.
local function dragThink()
	local p = Inv.Press
	if p and not Inv.Drag and input.IsMouseDown(MOUSE_LEFT) then
		if math.abs(gui.MouseX() - p.x) + math.abs(gui.MouseY() - p.y) > 6 then
			local it = itemAt(p.kind, p.key)
			if it then
				Inv.Drag = { kind = p.kind, key = p.key, item = it }
				UI.Sound("drag")
			end
		end
	end
	for s in pairs(Inv.SlotPanels) do if IsValid(s) then s.DropHover = false end end
	local under = Inv.Drag and slotUnderCursor()
	if under then under.DropHover = true end

	if p and not input.IsMouseDown(MOUSE_LEFT) then
		local drag = Inv.Drag
		Inv.Press, Inv.Drag = nil, nil
		if not drag then
			-- простой клик — панель предмета
			if IsValid(p.panel) then Inv.ShowDetail(p.kind, p.key) end
			return
		end
		local target = slotUnderCursor()
		if target then
			if target.Kind == drag.kind and tostring(target.Key) == tostring(drag.key) then return end
			if not target:Accepts(drag.kind, drag.key, drag.item) then UI.Sound("error") return end
			if drag.kind == "eq" and target.Kind == "eq" then return end
			if target.Kind == "invlist" then
				-- пустая ячейка списка: снять вещь в любую свободную ячейку
				if drag.kind ~= "eq" then return end
				Inv.Move("eq", drag.key, "inv", "")
			else
				Inv.Move(drag.kind, drag.key, target.Kind, target.Key)
			end
			UI.Sound("drop")
		elseif Inv.DropZone and overPanel(Inv.DropZone) and drag.kind == "eq" then
			Inv.Move("eq", drag.key, "inv", "")
			UI.Sound("drop")
		elseif not overPanel(Inv.Frame) and not overPanel(Inv.Detail) and not overPanel(Inv.Settings) then
			local def = Items.Get(drag.item.id)
			if def and not def.noDrop then
				Inv.Drop(drag.kind, drag.key, false)
				UI.Sound("drop")
			end
		end
	end
end

-- -------------------------------------------------- рамка «сумки» (ткань) --
-- Весь декор — отдельные материалы: nyrp/ui/fabric, zipper, zipper_pull, stitch_h/v, rivet.
local function tiled(mat, x, y, w, h, tw, th)
	surface.SetMaterial(UI.Mat(mat))
	surface.DrawTexturedRectUV(x, y, w, h, 0, 0, w / tw, h / th)
end

local function paintBag(pnl, w, h, title, icon)
	local r = UI.S(18)
	UI.Masked(r, 0, 0, w, h, function()
		surface.SetDrawColor(255, 255, 255, 255)
		tiled("nyrp/ui/fabric.png", 0, 0, w, h, UI.S(200), UI.S(200))
		surface.SetMaterial(UI.Mat("vgui/gradient-d"))
		surface.SetDrawColor(0, 0, 0, 140)
		surface.DrawTexturedRect(0, h * 0.35, w, h * 0.65)
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 150)
		-- лента и зубья молнии
		local zy = UI.S(16)
		surface.SetDrawColor(18, 17, 16, 255)
		surface.DrawRect(0, zy - UI.S(5), w, UI.S(22))
		surface.SetDrawColor(255, 255, 255, 255)
		tiled("nyrp/ui/zipper.png", UI.S(8), zy, w - UI.S(16), UI.S(12), UI.S(24), UI.S(12))
	end)
	-- строчка по краю
	local inset = UI.S(11)
	surface.SetDrawColor(255, 255, 255, 200)
	tiled("nyrp/ui/stitch_h.png", inset + r, UI.S(44), w - (inset + r) * 2, UI.S(5), UI.S(18), UI.S(5))
	tiled("nyrp/ui/stitch_h.png", inset + r, h - inset - UI.S(3), w - (inset + r) * 2, UI.S(5), UI.S(18), UI.S(5))
	tiled("nyrp/ui/stitch_v.png", inset - UI.S(2), UI.S(52), UI.S(5), h - UI.S(52) - inset - r, UI.S(5), UI.S(18))
	tiled("nyrp/ui/stitch_v.png", w - inset - UI.S(3), UI.S(52), UI.S(5), h - UI.S(52) - inset - r, UI.S(5), UI.S(18))
	-- заклёпки по углам
	local rs = UI.S(14)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(UI.Mat("nyrp/ui/rivet.png"))
	for _, c in ipairs({ { inset + UI.S(4), UI.S(40) }, { w - inset - UI.S(4), UI.S(40) }, { inset + UI.S(4), h - inset - UI.S(4) }, { w - inset - UI.S(4), h - inset - UI.S(4) } }) do
		surface.DrawTexturedRect(c[1] - rs / 2, c[2] - rs / 2, rs, rs)
	end
	UI.Outline(r, 0, 0, w, h, Color(0, 0, 0, 200), 2)
	-- бегунок с язычком у правого верхнего края
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(UI.Mat("nyrp/ui/zipper_pull.png"))
	surface.DrawTexturedRect(w - UI.S(200), UI.S(6), UI.S(28), UI.S(56))
	if title then
		UI.DrawIcon(icon or "briefcase", UI.S(40), UI.S(64), UI.S(22), UI.Col.accent)
		draw.SimpleText(string.upper(title), NYRP.Font("title", 24), UI.S(60), UI.S(64), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

-- --------------------------------------------------------- полоски статов --
local function statBars(parent, x, y, h)
	local p = vgui.Create("DPanel", parent)
	p:SetPos(x, y)
	p:SetSize(UI.S(64), h)
	p.Paint = function(_, w, ph)
		local ply = LocalPlayer()
		local vals = {
			{ ply:Health() / math.max(ply:GetMaxHealth(), 1), UI.Col.hp, "heart", "Здоровье" },
			{ ply:GetNW2Float("nyrp.hunger", 100) / 100, UI.Col.hunger, "food", "Сытость" },
			{ ply:GetNW2Float("nyrp.thirst", 100) / 100, UI.Col.thirst, "droplet", "Жажда" },
		}
		local bw = UI.S(6)
		local barH = ph - UI.S(30)
		for i, v in ipairs(vals) do
			local bx = (i - 1) * UI.S(22) + UI.S(4)
			local frac = math.Clamp(v[1], 0, 1)
			UI.RoundedRect(bw / 2, bx, 0, bw, barH, Color(0, 0, 0, 120))
			UI.RoundedRect(bw / 2, bx, barH * (1 - frac), bw, barH * frac, v[2])
			UI.DrawIcon(v[3], bx + bw / 2, barH + UI.S(16), UI.S(14), UI.LerpColor(0.4, v[2], color_white))
		end
	end
	p:SetTooltip("Здоровье · Сытость · Жажда")
	return p
end

-- ------------------------------------------------------------- сетка сумки --
local function bagGrid(parent, x, y)
	local cfg = bagCfg()
	local slot, gap = UI.S(SLOT), UI.S(GAP)
	local grid = vgui.Create("DPanel", parent)
	grid:SetPos(x, y)
	grid:SetSize(cfg.cols * (slot + gap) - gap, cfg.rows * (slot + gap) - gap)
	grid.Paint = function() end
	for i = 1, cfg.cols * cfg.rows do
		local s = vgui.Create("NYRP.InvSlot", grid)
		s:SetSize(slot, slot)
		s:SetPos(((i - 1) % cfg.cols) * (slot + gap), math.floor((i - 1) / cfg.cols) * (slot + gap))
		s:Setup("inv", i)
	end
	return grid
end

-- Список предметов сумки по фильтру (одежда/оружие на странице снаряжения).
local function filteredList(parent, x, y, cols, rows, filter, slotW, slotH, title)
	local gap = UI.S(GAP)
	local list = vgui.Create("DPanel", parent)
	list:SetPos(x, y)
	list:SetSize(cols * (slotW + gap) - gap, UI.S(26) + rows * (slotH + gap) - gap)
	list.Paint = function(_, w)
		draw.SimpleText(title, NYRP.Font("title", 15), 0, 0, UI.Col.dim)
	end
	list.Slots = {}
	for i = 1, cols * rows do
		local s = vgui.Create("NYRP.InvSlot", list)
		s:SetSize(slotW, slotH)
		s:SetPos(((i - 1) % cols) * (slotW + gap), UI.S(26) + math.floor((i - 1) / cols) * (slotH + gap))
		list.Slots[i] = s
	end
	list.Think = function()
		local idx = {}
		for k = 1, Inv.Data.size do
			local it = Inv.Data.slots[k]
			if it and filter(Items.Get(it.id)) then idx[#idx + 1] = k end
		end
		for i, s in ipairs(list.Slots) do
			if idx[i] then s:Setup("inv", idx[i]) else s:Setup("invlist", "any") end
		end
	end
	return list
end

-- -------------------------------------------------- манекен со снаряжением --
local function paperdoll(parent, x, y, w, h, compact)
	local area = vgui.Create("DPanel", parent)
	area:SetPos(x, y)
	area:SetSize(w, h)
	local cx, cy = w / 2, h * 0.5
	local R = math.min(w * 0.4, h * 0.4)
	area.Paint = function(_, pw, ph)
		-- полукруг-фон
		local seg = 48
		local poly = { { x = cx - R * 1.06, y = cy + R * 0.32 } }
		for i = 0, seg do
			local a = math.rad(200 - 220 * i / seg)
			poly[#poly + 1] = { x = cx + math.cos(a) * R * 1.06, y = cy - math.sin(a) * R * 1.06 }
		end
		poly[#poly + 1] = { x = cx + R * 1.06, y = cy + R * 0.32 }
		draw.NoTexture()
		surface.SetDrawColor(0, 0, 0, 90)
		surface.DrawPoly(poly)
		UI.Glow(cx, cy - R * 0.2, R * 2.2, R * 2.2, Color(90, 150, 220, 22))
		-- подиум
		UI.Glow(cx, cy + R * 0.52, R * 1.3, R * 0.32, Color(90, 160, 235, 90))
		UI.Glow(cx, cy + R * 0.52, R * 0.6, R * 0.12, Color(255, 255, 255, 50))
		-- дуга
		for i = 0, 63 do
			local a1, a2 = math.rad(200 - 220 * i / 64), math.rad(200 - 220 * (i + 1) / 64)
			surface.SetDrawColor(255, 255, 255, 22)
			surface.DrawLine(cx + math.cos(a1) * R, cy - math.sin(a1) * R, cx + math.cos(a2) * R, cy - math.sin(a2) * R)
		end
	end

	local mdl = vgui.Create("DModelPanel", area)
	local mh = R * 1.55
	mdl:SetSize(mh * 0.62, mh)
	mdl:SetPos(cx - mdl:GetWide() / 2, cy - mh * 0.62)
	mdl:SetModel(LocalPlayer():GetModel())
	mdl:SetFOV(30)
	mdl:SetMouseInputEnabled(false)
	local ent = mdl:GetEntity()
	if IsValid(ent) then
		local seq = ent:LookupSequence("idle_all_01")
		if seq >= 0 then ent:ResetSequence(seq) end
	end
	mdl.LayoutEntity = function(s, e)
		e:SetAngles(Angle(0, 18 + math.sin(RealTime() * 0.4) * 6, 0))
		s:RunAnimation()
		s:SetCamPos(Vector(130, 0, 40))
		s:SetLookAt(Vector(0, 0, 37))
	end

	-- слоты одежды по дуге: снизу слева -> верх -> снизу справа
	local order = { "pants", "gloves", "jacket", "head", "glasses", "mask", "shirt", "shoes" }
	local slot = UI.S(compact and 66 or 72)
	for i, id in ipairs(order) do
		local def = Items.EquipSlot[id]
		local a = math.rad(200 - 220 * (i - 1) / (#order - 1))
		local s = vgui.Create("NYRP.InvSlot", area)
		s:SetSize(slot, slot)
		s:SetPos(cx + math.cos(a) * R - slot / 2, cy - math.sin(a) * R - slot / 2)
		s:Setup("eq", id, { icon = def.icon, label = def.name })
		s:SetTooltip(def.name)
	end

	-- слоты оружия под моделью
	local ww, wh = UI.S(compact and 120 or 136), UI.S(compact and 66 or 72)
	local wy = cy + R * 0.72
	local total = #Items.WeaponSlots * (ww + UI.S(GAP)) - UI.S(GAP)
	for i, ws in ipairs(Items.WeaponSlots) do
		local s = vgui.Create("NYRP.InvSlot", area)
		s:SetSize(ww, wh)
		s:SetPos(cx - total / 2 + (i - 1) * (ww + UI.S(GAP)), wy)
		s:Setup("eq", ws.id, { icon = ws.icon, label = ws.name })
	end
	return area, wy + wh
end

-- --------------------------------------------------------- панель предмета --
function Inv.ShowDetail(kind, key)
	local it = itemAt(kind, key)
	if not it then return end
	Inv.DetailRef = { kind = kind, key = key }
	UI.Sound("expand")
	Inv.BuildDetail()
end

function Inv.RefreshDetail()
	local ref = Inv.DetailRef
	if not ref or not itemAt(ref.kind, ref.key) then
		if IsValid(Inv.Detail) then Inv.Detail:Remove() end
		Inv.DetailRef = nil
		return
	end
	Inv.BuildDetail(true)
end

function Inv.BuildDetail(silent)
	local ref = Inv.DetailRef
	if not IsValid(Inv.Root) or not ref then return end
	local it = itemAt(ref.kind, ref.key)
	local def = it and Items.Get(it.id)
	if not def then return end
	local old = IsValid(Inv.Detail) and Inv.Detail
	local pnl = vgui.Create("DPanel", Inv.Root)
	Inv.Detail = pnl
	pnl.Ref = ref
	local w, h = UI.S(320), math.max(Inv.Frame:GetTall(), UI.S(560))
	pnl:SetSize(w, h)
	local fx, fy = Inv.Frame:GetPos()
	pnl.TargetX = fx - w - UI.S(16)
	pnl:SetPos(old and pnl.TargetX or fx, fy + (Inv.Frame:GetTall() - h) / 2)
	if old then old:Remove() end
	pnl.Think = function(s)
		if not IsValid(Inv.Frame) then return end
		local x, y = s:GetPos()
		local fx2 = Inv.Frame:GetPos()
		s.TargetX = fx2 - w - UI.S(16)
		s:SetPos(UI.Approach(x, s.TargetX, 14), y)
	end
	pnl.Paint = function(s, pw, ph)
		UI.RoundedBlurPanel(s, UI.S(16), 4)
		UI.RoundedRect(UI.S(16), 0, 0, pw, ph, Color(12, 14, 22, 236))
		UI.Outline(UI.S(16), 0, 0, pw, ph, UI.Col.stroke, 1)
		local lines = UI.Wrap(def.name, NYRP.Font("title", 24), pw - UI.S(70))
		for i, l in ipairs(lines) do
			draw.SimpleText(l, NYRP.Font("title", 24), UI.S(20), UI.S(18) + (i - 1) * UI.S(28), UI.Col.text)
		end
		local ty = UI.S(18) + #lines * UI.S(28)
		draw.SimpleText(string.upper(Items.Categories[def.category] or ""), NYRP.Font("semibold", 13), UI.S(20), ty, UI.Col.accent)
		s.HeaderH = ty + UI.S(22)
	end
	local close = vgui.Create("NYRP.IconButton", pnl)
	close:SetSize(UI.S(30), UI.S(30))
	close:SetPos(w - UI.S(44), UI.S(16))
	close.DoClick = function()
		Inv.DetailRef = nil
		pnl:Remove()
	end

	local mdl = vgui.Create("DModelPanel", pnl)
	mdl:SetPos(UI.S(16), UI.S(84))
	mdl:SetSize(w - UI.S(32), UI.S(190))
	mdl:SetModel(def.model)
	mdl:SetFOV(30)
	mdl.PaintOver = function() end
	local e = mdl:GetEntity()
	if IsValid(e) then
		local mn, mx = e:GetModelBounds()
		local center = (mn + mx) / 2
		local rad = (mx - mn):Length() / 2
		mdl:SetLookAt(center)
		mdl:SetCamPos(center + Vector(1, 0.35, 0.55):GetNormalized() * rad / math.sin(math.rad(15)) * 1.05)
	end
	mdl.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, RealTime() * 30 % 360, 0)) end
	local mbg = mdl.Paint
	mdl.Paint = function(s, pw, ph)
		UI.Glow(pw / 2, ph * 0.6, pw * 0.9, ph * 0.8, Color(247, 198, 0, 18))
		mbg(s, pw, ph)
	end

	local info = vgui.Create("DPanel", pnl)
	info:SetPos(UI.S(20), UI.S(284))
	info:SetSize(w - UI.S(40), h - UI.S(284) - UI.S(170))
	info.Paint = function(_, pw)
		local y = 0
		for _, l in ipairs(UI.Wrap(def.desc or "", NYRP.Font("regular", 15), pw)) do
			draw.SimpleText(l, NYRP.Font("regular", 15), 0, y, UI.Col.dim)
			y = y + UI.S(20)
		end
		if it.id == "idcard" and it.data and it.data.name then
			y = y + UI.S(6)
			draw.SimpleText("Владелец: " .. it.data.name, NYRP.Font("semibold", 15), 0, y, UI.Col.text)
			y = y + UI.S(22)
		end
		if #def.buffs > 0 then
			y = y + UI.S(10)
			draw.SimpleText("ЭФФЕКТЫ", NYRP.Font("title", 14), 0, y, UI.Col.faint)
			y = y + UI.S(22)
			for _, b in ipairs(def.buffs) do
				local col = b[2] and UI.Col.green or UI.Col.red
				UI.Circle(UI.S(9), y + UI.S(9), UI.S(9), UI.Alpha(col, 40))
				UI.DrawIcon(b[2] and "plus" or "minus", UI.S(9), y + UI.S(9), UI.S(12), col)
				draw.SimpleText(b[1], NYRP.Font("medium", 15), UI.S(26), y + UI.S(9), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				y = y + UI.S(24)
			end
		end
		if it.n > 1 then
			draw.SimpleText("Количество: " .. it.n .. " / " .. def.stack, NYRP.Font("medium", 14), 0, y + UI.S(8), UI.Col.faint)
		end
	end

	local by = h - UI.S(160)
	local function btn(label, icon, style, fn, accent)
		local b = vgui.Create("NYRP.Button", pnl)
		b:SetSize(w - UI.S(40), UI.S(42))
		b:SetPos(UI.S(20), by)
		b:SetLabel(label)
		b:SetIcon(icon)
		b:SetStyle(style or "flat")
		if accent then b:SetAccent(accent) end
		b.DoClick = fn
		by = by + UI.S(48)
	end
	if def.use or it.id == "idcard" then
		btn(def.useText or "Использовать", it.id == "idcard" and "id" or "check", "solid", function() Inv.UseItem(ref.kind, ref.key) end)
	end
	if Items.EquipTarget(def) then
		if ref.kind == "eq" then
			btn(def.category == "weapon" and "Убрать в сумку" or "Снять", "arrow_left", "ghost", function() Inv.Unequip(ref.key) end)
		else
			btn(def.category == "weapon" and "Взять в руки" or "Надеть", def.category == "weapon" and "crosshair" or "hanger",
				(def.use and "ghost") or "solid", function() Inv.Equip(tonumber(ref.key)) end)
		end
	end
	if not def.noDrop then
		btn("Бросить", "arrow_right", "ghost", function() Inv.Drop(ref.kind, ref.key, false) end, UI.Col.red)
	end
	if not silent and not old then UI.Sound("open") end
end

-- ------------------------------------------------------------------ окна --
local function headerButtons(frame, w, opts)
	local gear = vgui.Create("NYRP.IconButton", frame)
	gear:SetIcon("settings")
	gear:SetSize(UI.S(34), UI.S(34))
	gear:SetPos(w - UI.S(96), UI.S(47))
	gear:SetTooltip("Настройки")
	gear.DoClick = function() Inv.ToggleSettings() end
	local close = vgui.Create("NYRP.IconButton", frame)
	close:SetSize(UI.S(34), UI.S(34))
	close:SetPos(w - UI.S(54), UI.S(47))
	close.DoClick = function() Inv.Close() end
end

function Inv.BuildFrame()
	if IsValid(Inv.Frame) then Inv.Frame:Remove() end
	if IsValid(Inv.Detail) then Inv.Detail:Remove() end
	local root = Inv.Root
	local cfg = bagCfg()
	local slot, gap = UI.S(SLOT), UI.S(GAP)
	local gridW, gridH = cfg.cols * (slot + gap) - gap, cfg.rows * (slot + gap) - gap
	local pad = UI.S(30)
	local top = UI.S(100)
	local combined = GetConVar("nyrp_inv_combined"):GetBool()
	local page = combined and "combined" or Inv.Page

	local frame = vgui.Create("DPanel", root)
	Inv.Frame = frame
	frame.Born = RealTime()
	local w, h
	if page == "bag" then
		w = pad * 2 + UI.S(76) + gridW + UI.S(44)
		h = top + gridH + pad + UI.S(36)
	elseif page == "equip" then
		w, h = UI.S(1180), UI.S(720)
	else
		w = pad * 2 + UI.S(76) + gridW + UI.S(40) + UI.S(640)
		h = math.max(top + gridH + pad + UI.S(36), UI.S(720))
	end
	frame:SetSize(w, h)
	frame.HomeX = ScrW() / 2 - w / 2
	frame:SetPos(frame.HomeX, ScrH() / 2 - h / 2)
	frame.Paint = function(s, pw, ph)
		local t = UI.Ease((RealTime() - s.Born) / 0.3)
		s:SetAlpha(255 * t)
		local used = table.Count(Inv.Data.slots)
		paintBag(s, pw, ph, cfg.name, cfg.icon)
		draw.SimpleText(used .. " / " .. Inv.Data.size, NYRP.Font("semibold", 15), UI.S(62) + UI.TextSize(string.upper(cfg.name), NYRP.Font("title", 24)) + UI.S(12),
			UI.S(64), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if page ~= "equip" then
			draw.SimpleText("Перетащите предмет за пределы сумки, чтобы выбросить · ПКМ — действия", NYRP.Font("regular", 13),
				pad, ph - UI.S(26), Color(255, 255, 255, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	frame.Think = function(s)
		local x, y = s:GetPos()
		local target = Inv.SettingsOpen and (s.HomeX - UI.S(200)) or s.HomeX
		s:SetPos(UI.Approach(x, target, 12), y)
	end
	headerButtons(frame, w)

	if page == "bag" or page == "combined" then
		statBars(frame, pad, top, gridH)
		bagGrid(frame, pad + UI.S(76), top)
		if page == "bag" then
			-- стрелка «к снаряжению» у правого верхнего угла сетки
			local arrow = vgui.Create("NYRP.IconButton", frame)
			arrow:SetIcon("arrow_right")
			arrow:SetSize(UI.S(34), UI.S(34))
			arrow:SetPos(pad + UI.S(76) + gridW + UI.S(8), top + (UI.S(SLOT) - UI.S(34)) / 2)
			arrow:SetTooltip("Снаряжение")
			arrow.DoClick = function()
				Inv.Page = "equip"
				UI.Sound("swipe")
				Inv.BuildFrame()
			end
		end
	end
	if page == "combined" then
		local ax = pad + UI.S(76) + gridW + UI.S(40)
		paperdoll(frame, ax, UI.S(84), UI.S(620), h - UI.S(100), true)
	elseif page == "equip" then
		local back = vgui.Create("NYRP.IconButton", frame)
		back:SetIcon("arrow_left")
		back:SetSize(UI.S(30), UI.S(30))
		back:SetPos(w - UI.S(140), UI.S(49))
		back:SetTooltip("К сумке")
		back.DoClick = function()
			Inv.Page = "bag"
			UI.Sound("swipe")
			Inv.BuildFrame()
		end
		local lslot = UI.S(70)
		local clothes = filteredList(frame, pad, UI.S(100), 3, 6, function(d) return d and d.category == "clothing" end, lslot, lslot, "ОДЕЖДА В СУМКЕ")
		Inv.DropZone = clothes
		local area, bottom = paperdoll(frame, pad + UI.S(260), UI.S(80), UI.S(600), UI.S(500))
		filteredList(frame, pad + UI.S(260) + UI.S(40), UI.S(80) + bottom + UI.S(10), 4, 1,
			function(d) return d and d.category == "weapon" end, UI.S(120), UI.S(66), "ОРУЖИЕ В СУМКЕ")
		-- справа — подсказка
		local hint = vgui.Create("DPanel", frame)
		hint:SetPos(w - UI.S(250), UI.S(110))
		hint:SetSize(UI.S(220), UI.S(400))
		hint.Paint = function(_, pw)
			draw.SimpleText("СНАРЯЖЕНИЕ", NYRP.Font("title", 15), 0, 0, UI.Col.dim)
			local y = UI.S(30)
			for _, l in ipairs(UI.Wrap("Перетащите одежду из списка слева в слот на дуге, а оружие — в слоты под персонажем. Одевание занимает пару секунд.", NYRP.Font("regular", 14), pw)) do
				draw.SimpleText(l, NYRP.Font("regular", 14), 0, y, UI.Col.faint)
				y = y + UI.S(19)
			end
			y = y + UI.S(16)
			local ply = LocalPlayer()
			draw.SimpleText("Броня: " .. ply:Armor(), NYRP.Font("semibold", 15), 0, y, UI.Col.text)
		end
	end
	if Inv.DetailRef then Inv.BuildDetail(true) end
end

function Inv.ToggleSettings()
	Inv.SettingsOpen = not Inv.SettingsOpen
	UI.Sound(Inv.SettingsOpen and "expand" or "close")
	if not Inv.SettingsOpen then
		if IsValid(Inv.Settings) then Inv.Settings:AlphaTo(0, 0.2, 0, function(_, p) p:Remove() end) end
		return
	end
	local f = Inv.Frame
	local w, h = UI.S(380), math.min(f:GetTall(), UI.S(600))
	local pnl = vgui.Create("DPanel", Inv.Root)
	Inv.Settings = pnl
	pnl:SetSize(w, h)
	pnl.Born = RealTime()
	pnl.Think = function(s)
		local fr = Inv.Frame  -- окно могло пересоздаться (смена страницы/режима)
		if not IsValid(fr) then return end
		local fx, fy = fr:GetPos()
		s:SetPos(fx + fr:GetWide() + UI.S(16), fy + (fr:GetTall() - h) / 2)
	end
	pnl.Paint = function(s, pw, ph)
		s:SetAlpha(255 * UI.Ease((RealTime() - s.Born) / 0.3))
		UI.RoundedBlurPanel(s, UI.S(16), 4)
		UI.RoundedRect(UI.S(16), 0, 0, pw, ph, Color(12, 14, 22, 236))
		UI.Outline(UI.S(16), 0, 0, pw, ph, UI.Col.stroke, 1)
		UI.DrawIcon("settings", UI.S(32), UI.S(34), UI.S(22), UI.Col.accent)
		draw.SimpleText("НАСТРОЙКИ", NYRP.Font("title", 24), UI.S(54), UI.S(34), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local body = vgui.Create("DPanel", pnl)
	body:SetPos(UI.S(22), UI.S(64))
	body:SetSize(w - UI.S(36), h - UI.S(80))
	body.Paint = function() end
	UI.BuildSettings(body)
end

function Inv.Rebuild()
	if Inv.IsOpen() then Inv.BuildFrame() end
end

-- ------------------------------------------------------- открыть/закрыть --
function Inv.Open()
	if Inv.IsOpen() then return end
	local root = vgui.Create("EditablePanel")
	Inv.Root = root
	root:SetSize(ScrW(), ScrH())
	root:MakePopup()
	root.Born = RealTime()
	root.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.35)
		UI.BlurPanel(s, 3 * t)
		surface.SetDrawColor(4, 5, 10, 120 * t)
		surface.DrawRect(0, 0, w, h)
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 160 * t)
	end
	root.PaintOver = function()
		local d = Inv.Drag
		if d then
			local s = UI.S(SLOT)
			NYRP.DrawItemIcon(d.item.id, gui.MouseX() - s / 2, gui.MouseY() - s / 2, s, s, 230)
		end
	end
	root.Think = dragThink
	root.OnKeyCodePressed = function(_, key)
		if key == KEY_Q or key == KEY_TAB or key == KEY_I then Inv.Close() end
	end
	Inv.SettingsOpen = false
	Inv.BuildFrame()
	UI.Sound("open")
end

function Inv.Close()
	if IsValid(Inv.Root) then
		Inv.Root:Remove()
		UI.Sound("close")
		net.Start("nyrp.inv.close")
		net.SendToServer()
	end
	if IsValid(UI.ActiveMenu) then UI.ActiveMenu:Remove() end
	if NYRP.Bags.FPClose then NYRP.Bags.FPClose() end
	Inv.Press, Inv.Drag, Inv.DropZone = nil, nil, nil
	Inv.Opening = false
end

function Inv.Toggle()
	if Inv.IsOpen() then Inv.Close() return end
	if Inv.Opening then return end
	local ply = LocalPlayer()
	if NYRP.State ~= "playing" or not ply:Alive() or not NYRP.HasCharacter(ply) then return end
	Inv.Opening = true
	if NYRP.Bags.FPStart then NYRP.Bags.FPStart() end
	net.Start("nyrp.inv.open")
	net.SendToServer()
	-- руки достают сумку, открывают молнию/клапан, потом — окно
	local delay = NYRP.Bags.FPOpenDelay and NYRP.Bags.FPOpenDelay() or 0.95
	timer.Simple(delay, function()
		if not Inv.Opening then return end
		Inv.Opening = false
		if LocalPlayer():Alive() then Inv.Open() end
	end)
end

-- Q — инвентарь; Shift+Q у админов — стандартное спавн-меню.
local spawnMenuOpened = false
function GM:OnSpawnMenuOpen()
	if LocalPlayer():IsAdmin() and input.IsKeyDown(KEY_LSHIFT) then
		spawnMenuOpened = true
		return self.BaseClass.OnSpawnMenuOpen(self)
	end
	Inv.Toggle()
end

function GM:OnSpawnMenuClose()
	if spawnMenuOpened then
		spawnMenuOpened = false
		return self.BaseClass.OnSpawnMenuClose(self)
	end
end

-- Контекстное меню (C) только у админов.
function GM:OnContextMenuOpen()
	if LocalPlayer():IsAdmin() then return self.BaseClass.OnContextMenuOpen(self) end
end
function GM:OnContextMenuClose()
	if LocalPlayer():IsAdmin() then return self.BaseClass.OnContextMenuClose(self) end
end

hook.Add("NYRP.StateChanged", "nyrp.inv", function(state)
	if state ~= "playing" then Inv.Close() end
end)
hook.Add("Think", "nyrp.inv.dead", function()
	if Inv.IsOpen() and not LocalPlayer():Alive() then Inv.Close() end
end)
