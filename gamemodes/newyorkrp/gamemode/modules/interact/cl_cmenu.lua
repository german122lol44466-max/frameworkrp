--[[
	Меню C (удерживать C): слева посередине — «Выбросить деньги», «Информация», «Упасть»
	(и «Выбросить сигарету», если она во рту). У админов поверх открывается ещё и стандартное контекстное меню.
]]

local UI = NYRP.UI
local CM = {}
NYRP.CMenu = CM

local function buttons()
	local list = {
		{ "Выбросить деньги", "cash", function() CM.Close(true) CM.DropMoney() end },
		{ "Информация", "info", function() CM.Close(true) CM.Info() end },
		{ "Упасть", "fall", function() net.Start("nyrp.cmenu.fall") net.SendToServer() CM.Close(true) end },
	}
	if NYRP.Smoking and NYRP.Smoking.State(LocalPlayer()) > 0 then
		list[#list + 1] = { "Выбросить сигарету", "smoking", function() net.Start("nyrp.smoke.drop") net.SendToServer() CM.Close(true) end }
	end
	return list
end

function CM.Open(parent)
	if IsValid(CM.Panel) then CM.Panel:Remove() end
	if NYRP.State ~= "playing" or not LocalPlayer():Alive() then return end
	local list = buttons()
	-- у админов поверх открыто стандартное контекстное меню (оно — popup и перехватывает клики),
	-- поэтому наша колонка кладётся внутрь него; у остальных — своя popup-панель
	local p = vgui.Create("EditablePanel", parent)
	CM.Panel = p
	p:SetSize(UI.S(420), ScrH())
	p:SetPos(0, 0)
	if not parent then
		p:MakePopup()
		p:SetKeyboardInputEnabled(false)
	end
	p:MoveToFront()
	p.Born = RealTime()
	p.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.18)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.15)) end
		s:SetAlpha(255 * t)
		surface.SetMaterial(UI.Mat("vgui/gradient-r"))
		surface.SetDrawColor(0, 0, 0, 200)
		surface.DrawTexturedRect(0, 0, UI.S(420), h)
	end
	p.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() CM.Close() end
		if not LocalPlayer():Alive() then CM.Close() end
	end
	local bh, gap = UI.S(50), UI.S(10)
	local total = #list * (bh + gap) - gap
	local y0 = ScrH() / 2 - total / 2
	for i, b in ipairs(list) do
		local btn = vgui.Create("DButton", p)
		btn:SetText("")
		btn:SetSize(UI.S(280), bh)
		btn:SetPos(UI.S(36), y0 + (i - 1) * (bh + gap))
		btn:SetCursor("hand")
		btn.Hover = 0
		btn.Born = RealTime() + i * 0.04
		btn.OnCursorEntered = function() UI.Sound("hover") end
		btn.DoClick = function() UI.Sound("click") b[3]() end
		btn.Paint = function(s, w, h)
			s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 12)
			local t = UI.Ease((RealTime() - s.Born) / 0.22)
			local off = (1 - t) * -UI.S(40)
			surface.SetAlphaMultiplier(t)
			UI.RoundedRect(UI.S(10), off, 0, w, h, UI.LerpColor(s.Hover, Color(12, 14, 22, 230), Color(247, 198, 0, 255)))
			UI.DrawIcon(b[2], off + UI.S(28), h / 2, UI.S(24), UI.LerpColor(s.Hover, Color(247, 198, 0), Color(14, 14, 18)))
			draw.SimpleText(b[1], NYRP.Font("bold", 18), off + UI.S(54), h / 2, UI.LerpColor(s.Hover, color_white, Color(14, 14, 18)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetAlphaMultiplier(1)
		end
	end
	UI.Sound("open")
end

function CM.Close(instant)
	local p = CM.Panel
	if not IsValid(p) or p.Closing then return end
	if instant then p:Remove() return end
	p.Closing = RealTime()
	p:SetMouseInputEnabled(false)
	timer.Simple(0.15, function() if IsValid(p) then p:Remove() end end)
end

-- --------------------------------------------------------- выбросить деньги --
function CM.DropMoney()
	local have = NYRP.Money.Get(LocalPlayer())
	local win, body = UI.Window("Выбросить деньги", "cash", 420, 330, { sub = "у вас " .. NYRP.Money.Format(have), keyboard = true })
	local amount = math.min(have, 10)
	local entry = vgui.Create("DTextEntry", body)
	entry:Dock(TOP)
	entry:SetTall(UI.S(46))
	entry:SetFont(NYRP.Font("title", 24))
	entry:SetNumeric(true)
	entry:SetValue(tostring(amount))
	entry:RequestFocus()
	local row = vgui.Create("DPanel", body)
	row:Dock(TOP)
	row:DockMargin(0, UI.S(12), 0, UI.S(12))
	row:SetTall(UI.S(38))
	row.Paint = function() end
	for _, v in ipairs({ 5, 10, 20, 50, 100 }) do
		local b = UI.AddButton(row, "$" .. v, nil, function() entry:SetValue(tostring(math.min(v, have))) end, { dock = LEFT, h = 38 })
		b:SetWide(UI.S(64))
		b:DockMargin(0, 0, UI.S(6), 0)
		b:SetAlign(TEXT_ALIGN_CENTER)
	end
	local function go()
		local n = math.floor(tonumber(entry:GetValue()) or 0)
		if n <= 0 then UI.Sound("error") return end
		if n > have then NYRP.Notify("У вас только " .. NYRP.Money.Format(have), "error") return end
		net.Start("nyrp.money.drop")
		net.WriteUInt(n, 32)
		net.SendToServer()
		win:Close()
	end
	entry.OnEnter = go
	UI.AddButton(body, "Выбросить", "cash", go, { style = "solid", accent = UI.Col.accent, h = 46 })
	UI.AddButton(body, "Всё: " .. NYRP.Money.Format(have), nil, function() entry:SetValue(tostring(have)) end, { h = 36 })
end

-- --------------------------------------------------------------- информация --
local info
net.Receive("nyrp.info", function()
	info = net.ReadTable()
	if IsValid(CM.InfoWin) and CM.InfoWin.Rebuild then CM.InfoWin.Rebuild() end
end)

function CM.Info()
	info = nil
	net.Start("nyrp.info")
	net.SendToServer()
	local ply = LocalPlayer()
	local win, body = UI.Window("Информация", "info", 520, 600)
	CM.InfoWin = win
	local role = NYRP.Roles and NYRP.Roles.Of(ply)
	local pnl = vgui.Create("DPanel", body)
	pnl:Dock(FILL)
	pnl.Paint = function(_, w, h)
		local y = 0
		local function line(label, value, col)
			draw.SimpleText(label, NYRP.Font("medium", 14), 0, y, UI.Col.dim)
			draw.SimpleText(value, NYRP.Font("semibold", 15), w, y, col or UI.Col.text, TEXT_ALIGN_RIGHT)
			y = y + UI.S(26)
		end
		draw.SimpleText(NYRP.CharName(ply), NYRP.Font("title", 30), 0, y, color_white)
		y = y + UI.S(40)
		if role then
			UI.DrawIcon(role.Icon or "user", UI.S(10), y + UI.S(10), UI.S(20), role.Color)
			draw.SimpleText(role.Name, NYRP.Font("bold", 17), UI.S(28), y, role.Color)
			y = y + UI.S(26)
			for _, l in ipairs(UI.Wrap(role.Description or "", NYRP.Font("regular", 13), w)) do
				draw.SimpleText(l, NYRP.Font("regular", 13), 0, y, UI.Col.dim)
				y = y + UI.S(18)
			end
			y = y + UI.S(10)
		end
		for _, l in ipairs(UI.Wrap(ply:GetNW2String("nyrp.desc", ""), NYRP.Font("regular", 14), w)) do
			draw.SimpleText(l, NYRP.Font("regular", 14), 0, y, Color(200, 202, 212))
			y = y + UI.S(19)
		end
		y = y + UI.S(10)
		surface.SetDrawColor(255, 255, 255, 14)
		surface.DrawRect(0, y, w, 1)
		y = y + UI.S(12)
		line("Наличные", NYRP.Money.Format(NYRP.Money.Get(ply)), UI.Col.accent)
		if info then
			for _, b in ipairs(info.banks or {}) do line("Счёт " .. b.name, NYRP.Money.Format(b.balance)) end
			line("Жильё", #(info.homes or {}) > 0 and table.concat(info.homes, ", ") or "нет")
			if info.height then line("Рост", info.height .. " см") end
		end
		line("Здоровье", ply:Health() .. "%")
		line("Сытость / вода", math.floor(ply:GetNW2Float("nyrp.hunger", 100)) .. "% / " .. math.floor(ply:GetNW2Float("nyrp.thirst", 100)) .. "%")
		y = y + UI.S(8)
		draw.SimpleText("НАВЫКИ", NYRP.Font("bold", 13), 0, y, UI.Col.dim)
		y = y + UI.S(24)
		for _, s in ipairs(NYRP.Config.Skills) do
			local v = info and info.skills and info.skills[s.id] or 0
			UI.DrawIcon(s.icon, UI.S(10), y + UI.S(9), UI.S(18), UI.Col.accent)
			draw.SimpleText(s.name, NYRP.Font("semibold", 14), UI.S(28), y, UI.Col.text)
			local cap = NYRP.Config.SkillCap or NYRP.Config.SkillMax
			for k = 1, cap do
				UI.RoundedRect(UI.S(3), w - (cap - k + 1) * UI.S(16), y + UI.S(4), UI.S(12), UI.S(10),
					k <= v and UI.Col.accent or Color(255, 255, 255, 20))
			end
			y = y + UI.S(26)
		end
	end
end

local function adminMenu() return LocalPlayer():IsAdmin() end
-- Держите C — меню открыто, отпустили — закрылось (вместе со стандартным контекстным меню у админов).
function GM:OnContextMenuOpen()
	if adminMenu() then
		self.BaseClass.OnContextMenuOpen(self)
		CM.Open(IsValid(g_ContextMenu) and g_ContextMenu or nil)
		return
	end
	CM.Open()
end
function GM:OnContextMenuClose()
	CM.Close(true)
	if adminMenu() then return self.BaseClass.OnContextMenuClose(self) end
end
