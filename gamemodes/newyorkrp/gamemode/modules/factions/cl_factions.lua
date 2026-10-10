--[[
	Служебный компьютер: вкладки «Устав», «Вызовы 911», «На смене» и вкладка службы
	(NYPD — розыск и штрафы, EMS — пострадавшие, FDNY — очаги пожаров).
]]

local UI = NYRP.UI
local F = NYRP.Factions

local EXTRA = {
	police = { name = "Розыск", icon = "handcuffs", empty = "Сейчас никто не в розыске" },
	medic = { name = "Пострадавшие", icon = "critical", empty = "Пострадавших нет" },
	fire = { name = "Пожары", icon = "fire", empty = "Активных возгораний нет" },
}

local function act(ent, a, x, y, z)
	net.Start("nyrp.terminal.act")
	net.WriteEntity(ent)
	net.WriteString(a)
	net.WriteString(x or "")
	net.WriteString(y or "")
	net.WriteString(z or "")
	net.SendToServer()
end

local function roleColor(r)
	local R = NYRP.Roles.List[r]
	return R and R.Color or Color(247, 198, 0)
end

local function statusIcon(name, x, y, s, col)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. name .. ".png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
end

-- строка списка: текст слева, кнопки справа
local function row(parent, text, sub, col, buttons)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(UI.S(sub and 58 or 44))
	p:DockMargin(0, 0, 0, UI.S(6))
	p.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
		surface.SetDrawColor(col)
		surface.DrawRect(0, UI.S(8), 3, h - UI.S(16))
		draw.SimpleText(text, NYRP.Font("semibold", 15), UI.S(16), sub and UI.S(10) or h / 2, color_white, TEXT_ALIGN_LEFT, sub and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
		if sub then draw.SimpleText(sub, NYRP.Font("regular", 12), UI.S(16), UI.S(32), UI.Col.dim) end
	end
	for _, b in ipairs(buttons or {}) do
		local btn = UI.AddButton(p, b[1], b[2], b[3], { dock = RIGHT, accent = b[4] or col, style = b[5] })
		btn:SetWide(UI.S(b[6] or 150))
		btn:DockMargin(UI.S(6), UI.S(8), UI.S(8), UI.S(8))
	end
	return p
end

local function emptyText(parent, text)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:SetTall(UI.S(60))
	l:SetFont(NYRP.Font("medium", 15))
	l:SetTextColor(UI.Col.dim)
	l:SetContentAlignment(5)
	l:SetText(text)
end

net.Receive("nyrp.terminal", function()
	local ent, d = net.ReadEntity(), net.ReadTable()
	local R = NYRP.Roles.List[d.role]
	local col = roleColor(d.role)
	local keepTab = IsValid(F.Win) and F.Win.Tab or "charter"
	if IsValid(F.Win) then F.Win:Remove() end
	local onDuty = LocalPlayer():GetNW2Bool("nyrp.onDuty")
	local win, body = UI.Window((R and R.Name or d.role) .. " — служебный компьютер", "keyboard", 980, 660,
		{ sub = "на смене: " .. #d.staff .. (onDuty and " · вы на дежурстве" or "") })
	F.Win = win
	win.Tab = keepTab

	-- слева вкладки
	local side = vgui.Create("DPanel", body)
	side:Dock(LEFT)
	side:SetWide(UI.S(220))
	side:DockMargin(0, 0, UI.S(14), 0)
	side.Paint = function() end
	local page = vgui.Create("NYRP.Scroll", body)
	page:Dock(FILL)

	local tabs = {
		{ id = "charter", name = "Устав", icon = "certificate" },
		{ id = "calls", name = "Вызовы 911 (" .. #d.calls .. ")", icon = "phone_call" },
		{ id = "staff", name = "На смене", icon = "users" },
	}
	if EXTRA[d.role] then tabs[#tabs + 1] = { id = "extra", name = EXTRA[d.role].name .. " (" .. #d.extra .. ")", icon = "warning" } end
	if d.role == "police" then tabs[#tabs + 1] = { id = "fine", name = "Выписать штраф", icon = "clipboard" } end

	local function show(id)
		win.Tab = id
		page:Clear()
		local canvas = page
		if id == "charter" then
			local txt = vgui.Create("DLabel", canvas)
			txt:Dock(TOP)
			txt:SetWrap(true)
			txt:SetAutoStretchVertical(true)
			txt:SetFont(NYRP.Font("regular", 15))
			txt:SetTextColor(Color(225, 228, 238))
			txt:SetText(d.charter or "")
			txt:DockMargin(UI.S(6), UI.S(4), UI.S(12), UI.S(12))
		elseif id == "calls" then
			if #d.calls == 0 then emptyText(canvas, "Вызовов нет") end
			local first = true
			for _, c in ipairs(d.calls) do
				local sub = (c.from ~= "" and ("звонил: " .. c.from .. " · ") or "") .. c.ago .. " с назад" .. (c.taken and (" · принял " .. c.taken) or " · не принят")
				local btns = {}
				if not c.taken and first then
					first = false
					btns[1] = { "Принять", "check", function() act(ent, "accept") end, nil, "solid" }
				end
				row(canvas, c.reason .. (c.comment ~= "" and (" — " .. c.comment) or ""), sub, c.taken and UI.Col.dim or Color(230, 70, 60), btns)
			end
		elseif id == "staff" then
			if #d.staff == 0 then emptyText(canvas, "Никого нет на смене") end
			for _, s in ipairs(d.staff) do row(canvas, s.name, nil, s.alive and col or UI.Col.dim) end
		elseif id == "extra" then
			local E = EXTRA[d.role]
			if #d.extra == 0 then emptyText(canvas, E.empty) end
			for _, e in ipairs(d.extra) do
				local sub = e.left and ("розыск ещё " .. math.max(0, math.ceil(e.left / 60)) .. " мин") or nil
				row(canvas, e.text, sub, col, { { "Метка", "map_pin", function() act(ent, "mark", tostring(e.id), E.name) end } })
			end
		elseif id == "fine" then
			local form = vgui.Create("DPanel", canvas)
			form:Dock(TOP)
			form:SetTall(UI.S(330))
			form.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 6))
				draw.SimpleText("Протокол об административном нарушении NYPD", NYRP.Font("bold", 17), UI.S(16), UI.S(14), color_white)
				draw.SimpleText("Штраф ляжет на банковский счёт нарушителя (раздел «Штрафы» в банке).", NYRP.Font("regular", 12), UI.S(16), UI.S(40), UI.Col.dim)
				draw.SimpleText("Нарушитель", NYRP.Font("medium", 13), UI.S(16), UI.S(70), UI.Col.dim)
				draw.SimpleText("Сумма, $", NYRP.Font("medium", 13), UI.S(16), UI.S(140), UI.Col.dim)
				draw.SimpleText("Статья / причина", NYRP.Font("medium", 13), UI.S(16), UI.S(210), UI.Col.dim)
			end
			local who = vgui.Create("DComboBox", form)
			who:SetPos(UI.S(16), UI.S(92))
			who:SetSize(UI.S(380), UI.S(36))
			who:SetFont(NYRP.Font("medium", 15))
			who:SetValue("выберите человека")
			for _, n in ipairs(d.people or {}) do who:AddChoice(n) end
			local amount = vgui.Create("NYRP.TextEntry", form)
			amount:SetPos(UI.S(16), UI.S(162))
			amount:SetSize(UI.S(180), UI.S(36))
			amount:SetNumeric(true)
			amount:SetValue("100")
			local reason = vgui.Create("NYRP.TextEntry", form)
			reason:SetPos(UI.S(16), UI.S(232))
			reason:SetSize(UI.S(560), UI.S(36))
			reason:SetPlaceholderText("например: нарушение общественного порядка")
			win:SetKeyboardInputEnabled(true)
			local send = UI.AddButton(form, "Выписать штраф", "clipboard", function()
				local name = who:GetSelected()
				if not name then return end
				act(ent, "fine", name, amount:GetValue(), reason:GetValue())
			end, { dock = false, style = "solid", accent = col })
			send:SetPos(UI.S(16), UI.S(282))
			send:SetSize(UI.S(240), UI.S(38))
		end
	end

	for _, t in ipairs(tabs) do
		local b = UI.AddButton(side, t.name, t.icon, function() show(t.id) end, { accent = col })
		b.Think = function(s) s:SetStyle(win.Tab == t.id and "solid" or "ghost") end
	end
	-- шапка службы и смена
	local badge = vgui.Create("DPanel", side)
	badge:Dock(BOTTOM)
	badge:SetTall(UI.S(110))
	badge.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, UI.Alpha(col, 24))
		if R and R.Icon then statusIcon(R.Icon, w / 2, UI.S(36), UI.S(48), col) end
		draw.SimpleText(R and R.Name or d.role, NYRP.Font("bold", 15), w / 2, UI.S(76), color_white, TEXT_ALIGN_CENTER)
	end
	local duty = UI.AddButton(side, onDuty and "Закончить дежурство" or "Заступить на дежурство", onDuty and "logout" or "play",
		function() act(ent, "duty") end, { dock = BOTTOM, accent = onDuty and UI.Col.red or col, style = "solid" })
	duty:DockMargin(0, UI.S(8), 0, UI.S(8))
	local re = UI.AddButton(side, "Обновить", "refresh", function() act(ent, "refresh") end, { dock = BOTTOM })
	re:DockMargin(0, UI.S(8), 0, 0)

	local ok = false
	for _, t in ipairs(tabs) do if t.id == keepTab then ok = true end end
	show(ok and keepTab or "charter")
end)

-- подсказка в руках у задержанного
hook.Add("HUDPaint", "nyrp.cuffs", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not F.Cuffed(ply) then return end
	local w, h = ScrW(), ScrH()
	local tw = UI.S(300)
	UI.RoundedRect(UI.S(12), w / 2 - tw / 2, h - UI.S(150), tw, UI.S(44), Color(10, 12, 20, 210))
	statusIcon("handcuffs", w / 2 - tw / 2 + UI.S(26), h - UI.S(128), UI.S(26), Color(230, 70, 60))
	draw.SimpleText("Вы в наручниках", NYRP.Font("semibold", 16), w / 2 - tw / 2 + UI.S(50), h - UI.S(128), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
